//! Collapse runs of 3 or more horizontal whitespace characters (space or tab)
//! to a single space. Preserves 1- and 2-space runs, so column-aligned tables
//! and markdown bullet indentation stay intact while obvious paste-debris
//! gaps (5+ spaces between flags, etc.) get cleaned up.
//!
//! Newlines are untouched.

const std = @import("std");
const Allocator = std.mem.Allocator;

const min_run_to_collapse: usize = 3;

pub fn apply(allocator: Allocator, input: []const u8) Allocator.Error![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    try out.ensureTotalCapacity(allocator, input.len);

    var byte_index: usize = 0;
    while (byte_index < input.len) {
        const c = input[byte_index];
        if (c == ' ' or c == '\t') {
            var run_end = byte_index;
            while (run_end < input.len and (input[run_end] == ' ' or input[run_end] == '\t')) : (run_end += 1) {}
            const run_len = run_end - byte_index;
            if (run_len >= min_run_to_collapse) {
                try out.append(allocator, ' ');
            } else {
                try out.appendSlice(allocator, input[byte_index..run_end]);
            }
            byte_index = run_end;
            continue;
        }
        try out.append(allocator, c);
        byte_index += 1;
    }
    return out.toOwnedSlice(allocator);
}

test "gaps: collapses 6-space run" {
    const out = try apply(std.testing.allocator, "app=<app>      -o");
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("app=<app> -o", out);
}

test "gaps: leaves 2-space alignment alone" {
    const out = try apply(std.testing.allocator, "  - bullet item");
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("  - bullet item", out);
}

test "gaps: leaves single space alone" {
    const out = try apply(std.testing.allocator, "a b c");
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("a b c", out);
}

test "gaps: tab counts toward run length" {
    const out = try apply(std.testing.allocator, "x\t\t\ty");
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("x y", out);
}

test "gaps: collapses three spaces" {
    const out = try apply(std.testing.allocator, "a   b");
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("a b", out);
}

test "gaps: preserves newlines" {
    const out = try apply(std.testing.allocator, "a   b\nc   d");
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("a b\nc d", out);
}
