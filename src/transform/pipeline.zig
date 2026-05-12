const std = @import("std");
const Allocator = std.mem.Allocator;

const continuations = @import("rules/continuations.zig");
const ansi = @import("rules/ansi.zig");
const prompts = @import("rules/prompts.zig");
const box_drawing = @import("rules/box_drawing.zig");
const zero_widths = @import("rules/zero_widths.zig");
const smart_quotes = @import("rules/smart_quotes.zig");
const dashes = @import("rules/dashes.zig");
const whitespace = @import("rules/whitespace.zig");

/// Aggressiveness levels are subsets of the full rule set. See the design
/// note's "Rule library" section for the source of truth.
pub const Level = enum { low, normal, high };

/// Each rule is a pure `[]const u8 -> []u8` function that allocates its own
/// output buffer. The pipeline frees the previous stage between rules.
pub const Rule = *const fn (Allocator, []const u8) Allocator.Error![]u8;

const low_rules = [_]Rule{
    continuations.apply,
    ansi.apply,
};

const normal_rules = [_]Rule{
    continuations.apply,
    ansi.apply,
    prompts.apply,
    box_drawing.apply,
    zero_widths.apply,
};

const high_rules = [_]Rule{
    continuations.apply,
    ansi.apply,
    prompts.apply,
    box_drawing.apply,
    zero_widths.apply,
    smart_quotes.apply,
    dashes.apply,
    whitespace.apply,
};

/// Apply the configured rule set to `input` and return a freshly allocated
/// trimmed copy. Caller owns the returned slice.
pub fn transform(allocator: Allocator, input: []const u8, level: Level) Allocator.Error![]u8 {
    const rules: []const Rule = switch (level) {
        .low => &low_rules,
        .normal => &normal_rules,
        .high => &high_rules,
    };

    var current = try allocator.dupe(u8, input);
    errdefer allocator.free(current);

    for (rules) |rule| {
        const next = try rule(allocator, current);
        allocator.free(current);
        current = next;
    }
    return current;
}

test "transform: no-op on empty input" {
    const out = try transform(std.testing.allocator, "", .normal);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("", out);
}

test "transform: low level joins line continuations" {
    const out = try transform(std.testing.allocator, "echo \\\nhello", .low);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("echo  hello", out);
}

test "transform: normal level strips prompt prefix" {
    const out = try transform(std.testing.allocator, "$ echo hi", .normal);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("echo hi", out);
}

test {
    _ = continuations;
    _ = ansi;
    _ = prompts;
    _ = box_drawing;
    _ = zero_widths;
    _ = smart_quotes;
    _ = dashes;
    _ = whitespace;
}
