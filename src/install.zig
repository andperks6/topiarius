//! Emit a launchd plist (macOS) or a systemd user unit (Linux) that runs
//! `topia daemon` in the background. The user is expected to pipe the
//! output to the right path and load it themselves:
//!
//!     topia install launchd > ~/Library/LaunchAgents/io.github.andperks6.topiarius.plist
//!     launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/io.github.andperks6.topiarius.plist
//!
//!     topia install systemd > ~/.config/systemd/user/topiarius.service
//!     systemctl --user enable --now topiarius
//!
//! No filesystem writes, no service-manager invocations. Same shape as
//! `topia shell-hook`.

const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;

const transform = @import("transform");

pub const Platform = enum { launchd, systemd };

pub const default_label = "io.github.andperks6.topiarius";

pub const Options = struct {
    binary_path: []const u8,
    level: transform.Level = .normal,
    label: []const u8 = default_label,
};

pub fn parse(name: []const u8) ?Platform {
    if (std.mem.eql(u8, name, "launchd")) return .launchd;
    if (std.mem.eql(u8, name, "systemd")) return .systemd;
    return null;
}

/// Returns the natural default for the host. `null` on unsupported
/// platforms (Windows, freestanding, …).
pub fn defaultPlatform() ?Platform {
    return switch (builtin.os.tag) {
        .macos => .launchd,
        .linux => .systemd,
        else => null,
    };
}

pub fn write(writer: *Io.Writer, platform: Platform, options: Options) Io.Writer.Error!void {
    switch (platform) {
        .launchd => try writeLaunchd(writer, options),
        .systemd => try writeSystemd(writer, options),
    }
}

fn writeLaunchd(writer: *Io.Writer, options: Options) Io.Writer.Error!void {
    try writer.print(
        \\<?xml version="1.0" encoding="UTF-8"?>
        \\<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        \\<plist version="1.0">
        \\<dict>
        \\  <key>Label</key>
        \\  <string>{s}</string>
        \\  <key>ProgramArguments</key>
        \\  <array>
        \\    <string>{s}</string>
        \\    <string>daemon</string>
        \\    <string>--{s}</string>
        \\  </array>
        \\  <key>RunAtLoad</key>
        \\  <true/>
        \\  <key>KeepAlive</key>
        \\  <true/>
        \\  <key>StandardOutPath</key>
        \\  <string>/tmp/topiarius.out.log</string>
        \\  <key>StandardErrorPath</key>
        \\  <string>/tmp/topiarius.err.log</string>
        \\</dict>
        \\</plist>
        \\
    , .{ options.label, options.binary_path, @tagName(options.level) });
}

fn writeSystemd(writer: *Io.Writer, options: Options) Io.Writer.Error!void {
    try writer.print(
        \\[Unit]
        \\Description=topiarius clipboard trimmer
        \\After=graphical-session.target
        \\
        \\[Service]
        \\Type=simple
        \\ExecStart={s} daemon --{s}
        \\Restart=on-failure
        \\RestartSec=5
        \\
        \\[Install]
        \\WantedBy=default.target
        \\
    , .{ options.binary_path, @tagName(options.level) });
}

test "install: parse" {
    try std.testing.expectEqual(@as(?Platform, .launchd), parse("launchd"));
    try std.testing.expectEqual(@as(?Platform, .systemd), parse("systemd"));
    try std.testing.expectEqual(@as(?Platform, null), parse("upstart"));
}

test "install: launchd output contains label, binary path, and level flag" {
    var buf: [4096]u8 = undefined;
    var fbs: Io.Writer = .fixed(&buf);
    try write(&fbs, .launchd, .{
        .binary_path = "/opt/homebrew/bin/topia",
        .level = .normal,
        .label = "io.github.test.topiarius",
    });
    const out = fbs.buffered();
    try std.testing.expect(std.mem.indexOf(u8, out, "<string>io.github.test.topiarius</string>") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "<string>/opt/homebrew/bin/topia</string>") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "<string>--normal</string>") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "<key>KeepAlive</key>") != null);
}

test "install: systemd output contains exec path and level flag" {
    var buf: [4096]u8 = undefined;
    var fbs: Io.Writer = .fixed(&buf);
    try write(&fbs, .systemd, .{
        .binary_path = "/usr/local/bin/topia",
        .level = .high,
    });
    const out = fbs.buffered();
    try std.testing.expect(std.mem.indexOf(u8, out, "ExecStart=/usr/local/bin/topia daemon --high") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "Restart=on-failure") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "WantedBy=default.target") != null);
}
