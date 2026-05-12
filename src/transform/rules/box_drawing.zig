//! Strip selected box-drawing characters used as block-quote markers in
//! command output. If a line starts with whitespace then a box char then
//! a space, the leading space is also removed so the underlying command
//! is flush-left.

const std = @import("std");
const Allocator = std.mem.Allocator;

// All target codepoints share a 3-byte UTF-8 encoding.
const targets = [_][3]u8{
    .{ 0xE2, 0x94, 0x82 }, // │ U+2502
    .{ 0xE2, 0x94, 0x83 }, // ┃ U+2503
    .{ 0xE2, 0x95, 0x91 }, // ║ U+2551
    .{ 0xE2, 0x94, 0x86 }, // ┆ U+2506
    .{ 0xE2, 0x94, 0x87 }, // ┇ U+2507
    .{ 0xE2, 0x94, 0x8A }, // ┊ U+250A
    .{ 0xE2, 0x94, 0x8B }, // ┋ U+250B
};

fn matchTarget(input: []const u8, byte_index: usize) bool {
    if (byte_index + 3 > input.len) return false;
    for (targets) |t| {
        if (input[byte_index] == t[0] and
            input[byte_index + 1] == t[1] and
            input[byte_index + 2] == t[2])
        {
            return true;
        }
    }
    return false;
}

pub fn apply(allocator: Allocator, input: []const u8) Allocator.Error![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    try out.ensureTotalCapacity(allocator, input.len);

    var byte_index: usize = 0;
    var at_line_start_visual = true; // only ASCII whitespace seen since newline

    while (byte_index < input.len) {
        if (matchTarget(input, byte_index)) {
            byte_index += 3;
            if (at_line_start_visual and byte_index < input.len and input[byte_index] == ' ') {
                byte_index += 1;
            }
            // Don't reset at_line_start_visual; if a line starts `│ ┃ x`,
            // both leading markers should be stripped together.
            continue;
        }
        const c = input[byte_index];
        try out.append(allocator, c);
        if (c == '\n') {
            at_line_start_visual = true;
        } else if (c != ' ' and c != '\t') {
            at_line_start_visual = false;
        }
        byte_index += 1;
    }
    return out.toOwnedSlice(allocator);
}

test "box_drawing: line-leading marker + space" {
    const out = try apply(std.testing.allocator, "\xE2\x94\x82 echo hi");
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("echo hi", out);
}

test "box_drawing: indented marker" {
    const out = try apply(std.testing.allocator, "  \xE2\x94\x83 x\n");
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("  x\n", out);
}

test "box_drawing: marker mid-line drops char only" {
    const out = try apply(std.testing.allocator, "a\xE2\x94\x82b");
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("ab", out);
}
