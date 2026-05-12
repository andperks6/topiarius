//! Collapse runs of ASCII horizontal whitespace (space/tab) to a single space
//! within each line; strip trailing whitespace at the end of every line; trim
//! leading/trailing whitespace from the whole string. Newlines are preserved.

const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn apply(allocator: Allocator, input: []const u8) Allocator.Error![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    try out.ensureTotalCapacity(allocator, input.len);

    var byte_index: usize = 0;
    var prev_was_space = false;
    while (byte_index < input.len) : (byte_index += 1) {
        const c = input[byte_index];
        if (c == ' ' or c == '\t') {
            if (!prev_was_space) try out.append(allocator, ' ');
            prev_was_space = true;
            continue;
        }
        if (c == '\n') {
            // Trim trailing space before the newline.
            if (prev_was_space and out.items.len > 0 and out.items[out.items.len - 1] == ' ') {
                _ = out.pop();
            }
            try out.append(allocator, '\n');
            prev_was_space = false;
            continue;
        }
        try out.append(allocator, c);
        prev_was_space = false;
    }
    // Trim trailing whitespace from the whole string.
    while (out.items.len > 0) {
        const last = out.items[out.items.len - 1];
        if (last == ' ' or last == '\n' or last == '\t') {
            _ = out.pop();
        } else break;
    }
    // Trim leading whitespace from the whole string.
    var start: usize = 0;
    while (start < out.items.len and (out.items[start] == ' ' or out.items[start] == '\n' or out.items[start] == '\t')) : (start += 1) {}
    if (start > 0) {
        std.mem.copyForwards(u8, out.items[0..], out.items[start..]);
        out.shrinkRetainingCapacity(out.items.len - start);
    }
    return out.toOwnedSlice(allocator);
}

test "whitespace: collapses runs" {
    const out = try apply(std.testing.allocator, "echo   a\t b");
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("echo a b", out);
}

test "whitespace: trims trailing per line" {
    const out = try apply(std.testing.allocator, "a   \nb");
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("a\nb", out);
}

test "whitespace: trims whole string ends" {
    const out = try apply(std.testing.allocator, "  hi  \n");
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("hi", out);
}
