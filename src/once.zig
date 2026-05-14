//! `topia once`: read the clipboard, transform, write it back.
//! Now a thin wrapper over `clipboard.Backend`.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const clipboard = @import("clipboard.zig");
const transform = @import("transform");

pub const Error = clipboard.Error;

pub fn run(gpa: Allocator, io: Io, level: transform.Level) Error!void {
    const backend = clipboard.systemBackend() orelse return error.ClipboardUnsupportedPlatform;

    const raw = try backend.read(gpa, io);
    defer gpa.free(raw);

    const trimmed = try transform.transform(gpa, raw, level);
    defer gpa.free(trimmed);

    try backend.write(io, trimmed);
}
