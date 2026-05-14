const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const clipboard = @import("clipboard.zig");
const transform = @import("transform");

pub const sentinel_bytes = "\xE2\x80\x8B"; // U+200B ZWSP

pub fn hasSentinel(bytes: []const u8) bool {
    return std.mem.endsWith(u8, bytes, sentinel_bytes);
}

pub fn appendSentinel(allocator: Allocator, bytes: []const u8) Allocator.Error![]u8 {
    var out = try allocator.alloc(u8, bytes.len + sentinel_bytes.len);
    @memcpy(out[0..bytes.len], bytes);
    @memcpy(out[bytes.len..], sentinel_bytes);
    return out;
}

test "hasSentinel: detects trailing ZWSP" {
    try std.testing.expect(hasSentinel("hello\xE2\x80\x8B"));
}

test "hasSentinel: false on plain content" {
    try std.testing.expect(!hasSentinel("hello"));
}

test "hasSentinel: false on ZWSP in the middle" {
    try std.testing.expect(!hasSentinel("a\xE2\x80\x8Bb"));
}

test "hasSentinel: false on empty" {
    try std.testing.expect(!hasSentinel(""));
}

test "appendSentinel: appends exactly one ZWSP" {
    const gpa = std.testing.allocator;
    const out = try appendSentinel(gpa, "abc");
    defer gpa.free(out);
    try std.testing.expectEqualStrings("abc\xE2\x80\x8B", out);
}

const Wyhash = std.hash.Wyhash;

/// Two-slot dedupe used by the daemon loop. Avoids re-transforming
/// content the daemon either just wrote (`last_written`) or just
/// observed without changing (`last_seen`).
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

pub const TickOutcome = enum {
    skipped_sentinel,
    skipped_dedupe,
    transformed,
};

/// One iteration of the daemon loop. Reads the clipboard, decides whether
/// the content is ours (sentinel) or already-handled (dedupe), and writes
/// the trimmed + sentinel-suffixed result back when appropriate.
pub fn tick(
    gpa: Allocator,
    io: Io,
    backend: clipboard.Backend,
    dedupe: *Dedupe,
    level: transform.Level,
) clipboard.Error!TickOutcome {
    const raw = try backend.read(gpa, io);
    defer gpa.free(raw);

    if (hasSentinel(raw)) return .skipped_sentinel;
    if (dedupe.shouldSkip(raw)) return .skipped_dedupe;
    dedupe.markSeen(raw);

    const trimmed = try transform.transform(gpa, raw, level);
    defer gpa.free(trimmed);

    const marked = try appendSentinel(gpa, trimmed);
    defer gpa.free(marked);

    try backend.write(io, marked);
    dedupe.markWritten(trimmed);
    return .transformed;
}

test "tick: dirty paste gets trimmed, sentinel-marked, written" {
    const gpa = std.testing.allocator;
    var mem: clipboard.Memory = .init(gpa);
    defer mem.deinit();
    try mem.setSlot("$ echo hi");

    var dedupe: Dedupe = .{};
    const outcome = try tick(gpa, std.testing.io, mem.backend(), &dedupe, .normal);
    try std.testing.expectEqual(TickOutcome.transformed, outcome);
    try std.testing.expectEqual(@as(usize, 1), mem.writes.items.len);
    try std.testing.expectEqualStrings("echo hi\xE2\x80\x8B", mem.writes.items[0]);
}

test "tick: second tick over our own output is a no-op" {
    const gpa = std.testing.allocator;
    var mem: clipboard.Memory = .init(gpa);
    defer mem.deinit();
    try mem.setSlot("$ echo hi");

    var dedupe: Dedupe = .{};
    _ = try tick(gpa, std.testing.io, mem.backend(), &dedupe, .normal);
    const outcome = try tick(gpa, std.testing.io, mem.backend(), &dedupe, .normal);
    try std.testing.expectEqual(TickOutcome.skipped_sentinel, outcome);
    try std.testing.expectEqual(@as(usize, 1), mem.writes.items.len);
}

test "tick: external manager strips sentinel but bytes match last_written" {
    const gpa = std.testing.allocator;
    var mem: clipboard.Memory = .init(gpa);
    defer mem.deinit();
    try mem.setSlot("$ echo hi");

    var dedupe: Dedupe = .{};
    _ = try tick(gpa, std.testing.io, mem.backend(), &dedupe, .normal);

    // simulate an external clipboard manager rewriting our output without sentinel
    try mem.setSlot("echo hi");
    const outcome = try tick(gpa, std.testing.io, mem.backend(), &dedupe, .normal);
    try std.testing.expectEqual(TickOutcome.skipped_dedupe, outcome);
}
