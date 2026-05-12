//! Join `\` + newline runs into a single space. Handles `\` + `\n` and
//! `\` + `\r\n`. Other `\` usages are preserved.

const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn apply(allocator: Allocator, input: []const u8) Allocator.Error![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    try out.ensureTotalCapacity(allocator, input.len);

    var byte_index: usize = 0;
    while (byte_index < input.len) : (byte_index += 1) {
        const c = input[byte_index];
        if (c == '\\' and byte_index + 1 < input.len) {
            const next = input[byte_index + 1];
            if (next == '\n') {
                try out.append(allocator, ' ');
                byte_index += 1;
                continue;
            }
            if (next == '\r' and byte_index + 2 < input.len and input[byte_index + 2] == '\n') {
                try out.append(allocator, ' ');
                byte_index += 2;
                continue;
            }
        }
        try out.append(allocator, c);
    }
    return out.toOwnedSlice(allocator);
}

test "continuations: simple" {
    const out = try apply(std.testing.allocator, "echo a \\\nb");
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("echo a  b", out);
}

test "continuations: crlf" {
    const out = try apply(std.testing.allocator, "echo \\\r\nhi");
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("echo  hi", out);
}

test "continuations: preserves unrelated backslash" {
    const out = try apply(std.testing.allocator, "echo \\n");
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("echo \\n", out);
}
