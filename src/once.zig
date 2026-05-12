//! `topia once`: read the clipboard, transform, write it back.
//!
//! Shells out to platform clipboard tools per the MVP plan: `pbpaste`/`pbcopy`
//! on macOS, `wl-paste`/`wl-copy` on Wayland, `xclip` on X11. Native
//! `@cImport` integration is reserved for v0.2+.

const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const transform = @import("transform");

pub const Error = error{
    ClipboardUnsupportedPlatform,
    ClipboardReadFailed,
    ClipboardWriteFailed,
} || Allocator.Error;

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
        // Wayland/X11 selection: we prefer Wayland because xclip on a Wayland
        // session is usually XWayland and racy. The shell launcher should pick
        // its own preferred tool if it cares.
        .linux => .{
            .read_argv = &.{ "wl-paste", "--no-newline" },
            .write_argv = &.{"wl-copy"},
        },
        else => null,
    };
}

pub fn run(gpa: Allocator, io: Io, level: transform.Level) Error!void {
    const pair = platformPair() orelse return error.ClipboardUnsupportedPlatform;

    const read_result = std.process.run(gpa, io, .{
        .argv = pair.read_argv,
        .stdout_limit = .limited(8 * 1024 * 1024),
        .stderr_limit = .limited(64 * 1024),
    }) catch return error.ClipboardReadFailed;
    defer gpa.free(read_result.stdout);
    defer gpa.free(read_result.stderr);

    switch (read_result.term) {
        .exited => |code| if (code != 0) return error.ClipboardReadFailed,
        else => return error.ClipboardReadFailed,
    }

    const trimmed = try transform.transform(gpa, read_result.stdout, level);
    defer gpa.free(trimmed);

    var child = std.process.spawn(io, .{
        .argv = pair.write_argv,
        .stdin = .pipe,
        .stdout = .ignore,
        .stderr = .ignore,
    }) catch return error.ClipboardWriteFailed;
    defer child.kill(io);

    if (child.stdin) |*stdin_file| {
        var buf: [4096]u8 = undefined;
        var writer = stdin_file.writer(io, &buf);
        writer.interface.writeAll(trimmed) catch return error.ClipboardWriteFailed;
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
