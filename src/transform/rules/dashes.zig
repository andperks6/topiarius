//! Normalize em-dash (U+2014) → "--" and en-dash (U+2013) → "-". Common in
//! pasted prose where the editor auto-converted ASCII dashes.

const std = @import("std");
const Allocator = std.mem.Allocator;

const em_dash = [_]u8{ 0xE2, 0x80, 0x94 };
const en_dash = [_]u8{ 0xE2, 0x80, 0x93 };

pub fn apply(allocator: Allocator, input: []const u8) Allocator.Error![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    try out.ensureTotalCapacity(allocator, input.len);

    var byte_index: usize = 0;
    while (byte_index < input.len) {
        if (byte_index + 3 <= input.len) {
            if (std.mem.eql(u8, input[byte_index .. byte_index + 3], &em_dash)) {
                try out.appendSlice(allocator, "--");
                byte_index += 3;
                continue;
            }
            if (std.mem.eql(u8, input[byte_index .. byte_index + 3], &en_dash)) {
                try out.append(allocator, '-');
                byte_index += 3;
                continue;
            }
        }
        try out.append(allocator, input[byte_index]);
        byte_index += 1;
    }
    return out.toOwnedSlice(allocator);
}

test "dashes: em to --" {
    const out = try apply(std.testing.allocator, "a\xE2\x80\x94b");
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("a--b", out);
}

test "dashes: en to -" {
    const out = try apply(std.testing.allocator, "1\xE2\x80\x935");
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("1-5", out);
}
