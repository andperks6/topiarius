const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const clipboard = @import("clipboard.zig");
const transform = @import("transform");

const Wyhash = std.hash.Wyhash;

/// Two-slot dedupe used by the daemon loop. Avoids re-transforming
/// content the daemon either just wrote (`last_written`) or just
/// observed without changing (`last_seen`).
///
/// `last_written` doubles as our self-detection: when the next tick reads
/// the clipboard and finds the same bytes we just wrote, the hash matches
/// and we skip — no sentinel byte required.
pub const Dedupe = struct {
    last_written: ?u64 = null,
    last_seen: ?u64 = null,

    pub fn fingerprint(bytes: []const u8) u64 {
        return Wyhash.hash(0, bytes);
    }

    pub fn shouldSkip(self: Dedupe, bytes: []const u8) bool {
        const h = fingerprint(bytes);
        if (self.last_written) |w| if (w == h) return true;
        if (self.last_seen) |s| if (s == h) return true;
        return false;
    }

    pub fn markWritten(self: *Dedupe, bytes: []const u8) void {
        self.last_written = fingerprint(bytes);
    }

    pub fn markSeen(self: *Dedupe, bytes: []const u8) void {
        self.last_seen = fingerprint(bytes);
    }
};

test "Dedupe: empty state skips nothing" {
    const d: Dedupe = .{};
    try std.testing.expect(!d.shouldSkip("hello"));
}

test "Dedupe: shouldSkip after markWritten" {
    var d: Dedupe = .{};
    d.markWritten("hello");
    try std.testing.expect(d.shouldSkip("hello"));
    try std.testing.expect(!d.shouldSkip("world"));
}

test "Dedupe: shouldSkip after markSeen" {
    var d: Dedupe = .{};
    d.markSeen("hello");
    try std.testing.expect(d.shouldSkip("hello"));
    try std.testing.expect(!d.shouldSkip("other"));
}

/// Suppresses repeated identical error logs from the loop. Whenever the
/// last logged error differs (or success follows failure), the next
/// occurrence logs again.
pub const ErrorThrottle = struct {
    last: ?clipboard.Error = null,

    pub fn shouldLog(self: *ErrorThrottle, err: clipboard.Error) bool {
        if (self.last) |prev| if (prev == err) return false;
        self.last = err;
        return true;
    }

    pub fn clear(self: *ErrorThrottle) void {
        self.last = null;
    }
};

pub const TickOutcome = enum {
    skipped_dedupe,
    transformed,
};

/// One iteration of the daemon loop. Reads the clipboard, returns early if
/// the bytes match either dedupe slot, otherwise transforms and writes the
/// trimmed result back verbatim — no sentinel, no clipboard pollution.
pub fn tick(
    gpa: Allocator,
    io: Io,
    backend: clipboard.Backend,
    dedupe: *Dedupe,
    level: transform.Level,
) clipboard.Error!TickOutcome {
    const raw = try backend.read(gpa, io);
    defer gpa.free(raw);

    if (dedupe.shouldSkip(raw)) return .skipped_dedupe;
    dedupe.markSeen(raw);

    const trimmed = try transform.transform(gpa, raw, level);
    defer gpa.free(trimmed);

    try backend.write(io, trimmed);
    dedupe.markWritten(trimmed);
    return .transformed;
}

test "tick: dirty paste gets trimmed and written verbatim" {
    const gpa = std.testing.allocator;
    var mem: clipboard.Memory = .init(gpa);
    defer mem.deinit();
    try mem.setSlot("$ echo hi");

    var dedupe: Dedupe = .{};
    const outcome = try tick(gpa, std.testing.io, mem.backend(), &dedupe, .normal);
    try std.testing.expectEqual(TickOutcome.transformed, outcome);
    try std.testing.expectEqual(@as(usize, 1), mem.writes.items.len);
    try std.testing.expectEqualStrings("echo hi", mem.writes.items[0]);
}

test "tick: second tick over our own output is a no-op via dedupe" {
    const gpa = std.testing.allocator;
    var mem: clipboard.Memory = .init(gpa);
    defer mem.deinit();
    try mem.setSlot("$ echo hi");

    var dedupe: Dedupe = .{};
    _ = try tick(gpa, std.testing.io, mem.backend(), &dedupe, .normal);
    const outcome = try tick(gpa, std.testing.io, mem.backend(), &dedupe, .normal);
    try std.testing.expectEqual(TickOutcome.skipped_dedupe, outcome);
    try std.testing.expectEqual(@as(usize, 1), mem.writes.items.len);
}

test "tick: external manager re-broadcasting trimmed bytes is a no-op" {
    const gpa = std.testing.allocator;
    var mem: clipboard.Memory = .init(gpa);
    defer mem.deinit();
    try mem.setSlot("$ echo hi");

    var dedupe: Dedupe = .{};
    _ = try tick(gpa, std.testing.io, mem.backend(), &dedupe, .normal);

    // Simulate an external clipboard manager re-writing the trimmed bytes.
    try mem.setSlot("echo hi");
    const outcome = try tick(gpa, std.testing.io, mem.backend(), &dedupe, .normal);
    try std.testing.expectEqual(TickOutcome.skipped_dedupe, outcome);
    try std.testing.expectEqual(@as(usize, 1), mem.writes.items.len);
}

test "ErrorThrottle: first occurrence logs, repeats do not" {
    var t: ErrorThrottle = .{};
    try std.testing.expect(t.shouldLog(error.ClipboardReadFailed));
    try std.testing.expect(!t.shouldLog(error.ClipboardReadFailed));
    try std.testing.expect(t.shouldLog(error.ClipboardWriteFailed));
    try std.testing.expect(!t.shouldLog(error.ClipboardWriteFailed));
}

test "ErrorThrottle: clear resets state" {
    var t: ErrorThrottle = .{};
    _ = t.shouldLog(error.ClipboardReadFailed);
    t.clear();
    try std.testing.expect(t.shouldLog(error.ClipboardReadFailed));
}

const signal = @import("signal.zig");

pub const poll_interval_ms: i64 = 250;

/// Run the daemon loop until the shutdown flag is set. Spins on
/// `backend.read` errors; logs each *new* error once.
pub fn run(
    gpa: Allocator,
    io: Io,
    backend: clipboard.Backend,
    level: transform.Level,
) clipboard.Error!void {
    var dedupe: Dedupe = .{};
    var throttle: ErrorThrottle = .{};

    while (!signal.shouldShutdown()) {
        const outcome = tick(gpa, io, backend, &dedupe, level) catch |err| {
            if (throttle.shouldLog(err)) {
                logErr(io, err) catch {};
            }
            sleepTick(io) catch return;
            continue;
        };
        _ = outcome;
        throttle.clear();
        sleepTick(io) catch return;
    }
}

fn sleepTick(io: Io) Io.Cancelable!void {
    return io.sleep(.fromMilliseconds(poll_interval_ms), .awake);
}

fn logErr(io: Io, err: clipboard.Error) !void {
    var buf: [128]u8 = undefined;
    var stderr: Io.File.Writer = .init(.stderr(), io, &buf);
    try stderr.interface.print("topia[daemon]: {s}\n", .{@errorName(err)});
    try stderr.interface.flush();
}
