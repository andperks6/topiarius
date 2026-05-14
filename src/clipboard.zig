//! Clipboard backend abstraction. Two implementations:
//!   - `systemBackend()` shells out to `pbpaste`/`pbcopy` on macOS and
//!     `wl-paste`/`wl-copy` on Linux.
//!   - `memoryBackend()` is a test fake backed by a heap-allocated slot.

const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const Io = std.Io;

pub const Error = error{
    ClipboardUnsupportedPlatform,
    ClipboardReadFailed,
    ClipboardWriteFailed,
} || Allocator.Error;

pub const VTable = struct {
    read: *const fn (ctx: ?*anyopaque, gpa: Allocator, io: Io) Error![]u8,
    write: *const fn (ctx: ?*anyopaque, io: Io, bytes: []const u8) Error!void,
};

pub const Backend = struct {
    context: ?*anyopaque,
    vtable: *const VTable,

    pub fn read(self: Backend, gpa: Allocator, io: Io) Error![]u8 {
        return self.vtable.read(self.context, gpa, io);
    }

    pub fn write(self: Backend, io: Io, bytes: []const u8) Error!void {
        return self.vtable.write(self.context, io, bytes);
    }
};

const Pair = struct {
    read_argv: []const []const u8,
    write_argv: []const []const u8,
};

fn platformPair() ?Pair {
    return switch (builtin.os.tag) {
        .macos => .{
            .read_argv = &.{"pbpaste"},
            .write_argv = &.{"pbcopy"},
        },
        .linux => .{
            .read_argv = &.{ "wl-paste", "--no-newline" },
            .write_argv = &.{"wl-copy"},
        },
        else => null,
    };
}

fn systemRead(ctx: ?*anyopaque, gpa: Allocator, io: Io) Error![]u8 {
    _ = ctx;
    const pair = platformPair() orelse return error.ClipboardUnsupportedPlatform;
    const result = std.process.run(gpa, io, .{
        .argv = pair.read_argv,
        .stdout_limit = .limited(8 * 1024 * 1024),
        .stderr_limit = .limited(64 * 1024),
    }) catch return error.ClipboardReadFailed;
    defer gpa.free(result.stderr);
    errdefer gpa.free(result.stdout);
    switch (result.term) {
        .exited => |code| if (code != 0) return error.ClipboardReadFailed,
        else => return error.ClipboardReadFailed,
    }
    return result.stdout;
}

fn systemWrite(ctx: ?*anyopaque, io: Io, bytes: []const u8) Error!void {
    _ = ctx;
    const pair = platformPair() orelse return error.ClipboardUnsupportedPlatform;
    var child = std.process.spawn(io, .{
        .argv = pair.write_argv,
        .stdin = .pipe,
        .stdout = .ignore,
        .stderr = .ignore,
    }) catch return error.ClipboardWriteFailed;
    defer child.kill(io);

    if (child.stdin) |*stdin_file| {
        var buf: [4096]u8 = undefined;
        var writer: Io.File.Writer = .init(stdin_file.*, io, &buf);
        writer.interface.writeAll(bytes) catch return error.ClipboardWriteFailed;
        writer.interface.flush() catch return error.ClipboardWriteFailed;
        stdin_file.close(io);
        child.stdin = null;
    }

    const term = child.wait(io) catch return error.ClipboardWriteFailed;
    switch (term) {
        .exited => |code| if (code != 0) return error.ClipboardWriteFailed,
        else => return error.ClipboardWriteFailed,
    }
}

const system_vtable: VTable = .{ .read = systemRead, .write = systemWrite };

pub fn systemBackend() ?Backend {
    if (platformPair() == null) return null;
    return .{ .context = null, .vtable = &system_vtable };
}

/// In-memory backend for tests. Owns its slot; callers can inspect
/// `slot` and `writes` to assert behavior.
pub const Memory = struct {
    gpa: Allocator,
    slot: ?[]u8,
    writes: std.ArrayList([]u8),
    read_fail_until: usize = 0,
    read_call_count: usize = 0,

    pub fn init(gpa: Allocator) Memory {
        return .{
            .gpa = gpa,
            .slot = null,
            .writes = .empty,
        };
    }

    pub fn deinit(self: *Memory) void {
        if (self.slot) |s| self.gpa.free(s);
        for (self.writes.items) |w| self.gpa.free(w);
        self.writes.deinit(self.gpa);
    }

    pub fn setSlot(self: *Memory, bytes: []const u8) !void {
        const new_slot = try self.gpa.dupe(u8, bytes);
        if (self.slot) |s| self.gpa.free(s);
        self.slot = new_slot;
    }

    fn read(ctx: ?*anyopaque, gpa: Allocator, io: Io) Error![]u8 {
        _ = io;
        const self: *Memory = @ptrCast(@alignCast(ctx.?));
        self.read_call_count += 1;
        if (self.read_call_count <= self.read_fail_until) return error.ClipboardReadFailed;
        return gpa.dupe(u8, self.slot orelse "");
    }

    fn write(ctx: ?*anyopaque, io: Io, bytes: []const u8) Error!void {
        _ = io;
        const self: *Memory = @ptrCast(@alignCast(ctx.?));
        const copy = try self.gpa.dupe(u8, bytes);
        errdefer self.gpa.free(copy);
        try self.writes.append(self.gpa, copy);
        errdefer _ = self.writes.pop();

        const new_slot = try self.gpa.dupe(u8, bytes);
        if (self.slot) |s| self.gpa.free(s);
        self.slot = new_slot;
    }

    const vtable: VTable = .{ .read = Memory.read, .write = Memory.write };

    pub fn backend(self: *Memory) Backend {
        return .{ .context = self, .vtable = &Memory.vtable };
    }
};

pub fn memoryBackend(memory: *Memory) Backend {
    return memory.backend();
}

test "systemBackend returns a populated backend on this platform" {
    const backend = systemBackend();
    if (backend) |b| {
        // `read`/`write` are non-optional `*const fn` pointers, so the type
        // system guarantees they are populated. We assert they point at the
        // expected system implementations to confirm the vtable is wired up.
        try std.testing.expectEqual(&systemRead, b.vtable.read);
        try std.testing.expectEqual(&systemWrite, b.vtable.write);
    }
    // On unsupported platforms (Windows for now) `null` is acceptable.
}

test "memoryBackend round-trips writes into the slot" {
    const gpa = std.testing.allocator;
    var mem: Memory = .init(gpa);
    defer mem.deinit();

    const backend = memoryBackend(&mem);
    try backend.write(std.testing.io, "hello");
    const got = try backend.read(gpa, std.testing.io);
    defer gpa.free(got);
    try std.testing.expectEqualStrings("hello", got);
    try std.testing.expectEqual(@as(usize, 1), mem.writes.items.len);
}

test "memoryBackend can be primed to fail reads" {
    const gpa = std.testing.allocator;
    var mem: Memory = .init(gpa);
    defer mem.deinit();
    mem.read_fail_until = 2;

    const backend = memoryBackend(&mem);
    try std.testing.expectError(error.ClipboardReadFailed, backend.read(gpa, std.testing.io));
    try std.testing.expectError(error.ClipboardReadFailed, backend.read(gpa, std.testing.io));
    const got = try backend.read(gpa, std.testing.io);
    defer gpa.free(got);
    try std.testing.expectEqualStrings("", got);
}
