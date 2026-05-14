//! Atomic shutdown-flag plumbing for the daemon loop. The flag is set
//! by signal handlers and polled between ticks; SIGINT/SIGTERM trigger
//! it, SIGHUP is installed-but-ignored so it doesn't kill the process.

const std = @import("std");
const builtin = @import("builtin");

var shutdown_flag: std.atomic.Value(bool) = .init(false);

pub fn shouldShutdown() bool {
    return shutdown_flag.load(.acquire);
}

pub fn requestShutdown() void {
    shutdown_flag.store(true, .release);
}

pub fn reset() void {
    shutdown_flag.store(false, .release);
}

fn handleShutdownSignal(sig: std.posix.SIG) callconv(.c) void {
    _ = sig;
    requestShutdown();
}

fn handleIgnoredSignal(sig: std.posix.SIG) callconv(.c) void {
    _ = sig;
}

pub fn installHandlers() void {
    if (builtin.os.tag == .windows) return; // POSIX-only path for v0.2-a

    const shutdown_action: std.posix.Sigaction = .{
        .handler = .{ .handler = handleShutdownSignal },
        .mask = std.mem.zeroes(std.posix.sigset_t),
        .flags = 0,
    };
    const ignore_action: std.posix.Sigaction = .{
        .handler = .{ .handler = handleIgnoredSignal },
        .mask = std.mem.zeroes(std.posix.sigset_t),
        .flags = 0,
    };

    std.posix.sigaction(.INT, &shutdown_action, null);
    std.posix.sigaction(.TERM, &shutdown_action, null);
    std.posix.sigaction(.HUP, &ignore_action, null);
}

test "shouldShutdown is false by default after reset" {
    reset();
    try std.testing.expect(!shouldShutdown());
}

test "requestShutdown sets the flag" {
    reset();
    requestShutdown();
    try std.testing.expect(shouldShutdown());
    reset();
}
