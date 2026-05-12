//! Replace curly Unicode quotes with their ASCII straight equivalents.
//!   U+201C "  → "
//!   U+201D "  → "
//!   U+2018 '  → '
//!   U+2019 '  → '

const std = @import("std");
const Allocator = std.mem.Allocator;

const Replace = struct {
    bytes: [3]u8,
    to: u8,
};

const replacements = [_]Replace{
    .{ .bytes = .{ 0xE2, 0x80, 0x9C }, .to = '"' },
    .{ .bytes = .{ 0xE2, 0x80, 0x9D }, .to = '"' },
    .{ .bytes = .{ 0xE2, 0x80, 0x98 }, .to = '\'' },
    .{ .bytes = .{ 0xE2, 0x80, 0x99 }, .to = '\'' },
};

pub fn apply(allocator: Allocator, input: []const u8) Allocator.Error![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    try out.ensureTotalCapacity(allocator, input.len);

    var byte_index: usize = 0;
    outer: while (byte_index < input.len) {
        if (byte_index + 3 <= input.len) {
            for (replacements) |r| {
                if (input[byte_index] == r.bytes[0] and
                    input[byte_index + 1] == r.bytes[1] and
                    input[byte_index + 2] == r.bytes[2])
                {
                    try out.append(allocator, r.to);
                    byte_index += 3;
                    continue :outer;
                }
            }
        }
        try out.append(allocator, input[byte_index]);
        byte_index += 1;
    }
    return out.toOwnedSlice(allocator);
}

test "smart_quotes: double quotes" {
    const out = try apply(std.testing.allocator, "echo \xE2\x80\x9Chi\xE2\x80\x9D");
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("echo \"hi\"", out);
}

test "smart_quotes: single quotes" {
    const out = try apply(std.testing.allocator, "it\xE2\x80\x99s");
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("it's", out);
}
