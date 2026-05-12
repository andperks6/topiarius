//! Strip zero-width invisibles: ZWSP (U+200B), ZWNJ (U+200C), ZWJ (U+200D),
//! and BOM (U+FEFF). All appear in pasted content from rich-text editors and
//! survive copy/paste invisibly.

const std = @import("std");
const Allocator = std.mem.Allocator;

const e2_80_targets = [_]u8{ 0x8B, 0x8C, 0x8D }; // ZWSP, ZWNJ, ZWJ

fn matchHere(input: []const u8, byte_index: usize) usize {
    if (byte_index + 3 > input.len) return 0;
    // U+200B/C/D = 0xE2 0x80 0x8B/0x8C/0x8D
    if (input[byte_index] == 0xE2 and input[byte_index + 1] == 0x80) {
        const third = input[byte_index + 2];
        for (e2_80_targets) |t| if (third == t) return 3;
    }
    // U+FEFF = 0xEF 0xBB 0xBF
    if (input[byte_index] == 0xEF and input[byte_index + 1] == 0xBB and input[byte_index + 2] == 0xBF) {
        return 3;
    }
    return 0;
}

pub fn apply(allocator: Allocator, input: []const u8) Allocator.Error![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    try out.ensureTotalCapacity(allocator, input.len);

    var byte_index: usize = 0;
    while (byte_index < input.len) {
        const skip = matchHere(input, byte_index);
        if (skip != 0) {
            byte_index += skip;
            continue;
        }
        try out.append(allocator, input[byte_index]);
        byte_index += 1;
    }
    return out.toOwnedSlice(allocator);
}

test "zero_widths: strips ZWSP" {
    const out = try apply(std.testing.allocator, "a\xE2\x80\x8Bb");
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("ab", out);
}

test "zero_widths: strips BOM" {
    const out = try apply(std.testing.allocator, "\xEF\xBB\xBFecho");
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("echo", out);
}

test "zero_widths: preserves regular utf-8" {
    const out = try apply(std.testing.allocator, "café");
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("café", out);
}
