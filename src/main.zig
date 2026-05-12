const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const transform = @import("transform");
const shell_hook = @import("shell_hook.zig");
const once_cmd = @import("once.zig");

const usage =
    \\topia — clipboard trimmer
    \\
    \\Usage:
    \\  topia transform [--low|--normal|--high]    Read stdin, trim, write stdout
    \\  topia once      [--low|--normal|--high]    Read clipboard, trim, write back
    \\  topia shell-hook (zsh|bash|fish)           Print precmd snippet for eval
    \\
;

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;
    const arena = init.arena.allocator();

    const argv = try init.minimal.args.toSlice(arena);
    if (argv.len < 2) {
        try writeStderr(io, usage);
        std.process.exit(2);
    }
    const sub = argv[1];
    const rest = argv[2..];

    if (std.mem.eql(u8, sub, "transform")) {
        const level = try parseLevel(rest);
        try runTransform(gpa, io, level);
        return;
    }
    if (std.mem.eql(u8, sub, "once")) {
        const level = try parseLevel(rest);
        once_cmd.run(gpa, io, level) catch |err| {
            switch (err) {
                error.ClipboardUnsupportedPlatform => try writeStderr(io, "topia: clipboard not supported on this platform yet\n"),
                error.ClipboardReadFailed => try writeStderr(io, "topia: failed to read clipboard (is pbpaste/wl-paste installed?)\n"),
                error.ClipboardWriteFailed => try writeStderr(io, "topia: failed to write clipboard\n"),
                error.OutOfMemory => return err,
            }
            std.process.exit(1);
        };
        return;
    }
    if (std.mem.eql(u8, sub, "shell-hook")) {
        if (rest.len == 0) {
            try writeStderr(io, "topia shell-hook: missing shell name (zsh|bash|fish)\n");
            std.process.exit(2);
        }
        const shell = shell_hook.parse(rest[0]) orelse {
            try writeStderr(io, "topia shell-hook: unknown shell (expected zsh|bash|fish)\n");
            std.process.exit(2);
        };

        var buf: [1024]u8 = undefined;
        var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &buf);
        try shell_hook.write(shell, &stdout_file_writer.interface);
        try stdout_file_writer.interface.flush();
        return;
    }
    if (std.mem.eql(u8, sub, "--help") or std.mem.eql(u8, sub, "-h") or std.mem.eql(u8, sub, "help")) {
        var buf: [1024]u8 = undefined;
        var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &buf);
        try stdout_file_writer.interface.writeAll(usage);
        try stdout_file_writer.interface.flush();
        return;
    }

    try writeStderr(io, usage);
    std.process.exit(2);
}

fn parseLevel(args: []const [:0]const u8) !transform.Level {
    if (args.len == 0) return .normal;
    const flag = args[0];
    if (std.mem.eql(u8, flag, "--low")) return .low;
    if (std.mem.eql(u8, flag, "--normal")) return .normal;
    if (std.mem.eql(u8, flag, "--high")) return .high;
    return error.UnknownLevel;
}

fn runTransform(gpa: Allocator, io: Io, level: transform.Level) !void {
    var in_buf: [4096]u8 = undefined;
    var stdin_file_reader: Io.File.Reader = .init(.stdin(), io, &in_buf);
    const input = try stdin_file_reader.interface.allocRemaining(gpa, .unlimited);
    defer gpa.free(input);

    const trimmed = try transform.transform(gpa, input, level);
    defer gpa.free(trimmed);

    var out_buf: [4096]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &out_buf);
    try stdout_file_writer.interface.writeAll(trimmed);
    try stdout_file_writer.interface.flush();
}

fn writeStderr(io: Io, msg: []const u8) !void {
    var buf: [256]u8 = undefined;
    var stderr_file_writer: Io.File.Writer = .init(.stderr(), io, &buf);
    try stderr_file_writer.interface.writeAll(msg);
    try stderr_file_writer.interface.flush();
}
