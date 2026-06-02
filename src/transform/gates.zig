//! Bypass conditions for the transform pipeline. When a gate matches, the
//! pipeline returns the input verbatim and runs NO rules. Use sparingly —
//! gates exist for content shapes where any transformation is unwanted
//! (structured data formats, mainly).

const std = @import("std");

/// True when the input should bypass every rule in the pipeline.
pub fn shouldSkipAll(input: []const u8) bool {
    return looksLikeStructuredJson(input);
}

/// JSON object or array, ignoring surrounding whitespace. Heuristic only:
/// we don't parse, we just check that the first and last non-whitespace
/// bytes form a matching `{`/`}` or `[`/`]` pair. Robust enough to catch
/// the common "I pasted a JSON blob" case without ever calling a parser.
fn looksLikeStructuredJson(input: []const u8) bool {
    const first = firstNonWhitespace(input) orelse return false;
    const last = lastNonWhitespace(input) orelse return false;
    return (first == '{' and last == '}') or (first == '[' and last == ']');
}

fn firstNonWhitespace(input: []const u8) ?u8 {
    for (input) |c| {
        if (c != ' ' and c != '\t' and c != '\n' and c != '\r') return c;
    }
    return null;
}

fn lastNonWhitespace(input: []const u8) ?u8 {
    var i = input.len;
    while (i > 0) {
        i -= 1;
        const c = input[i];
        if (c != ' ' and c != '\t' and c != '\n' and c != '\r') return c;
    }
    return null;
}

test "shouldSkipAll: simple JSON object" {
    try std.testing.expect(shouldSkipAll(
        \\{"key": "value"}
    ));
}

test "shouldSkipAll: indented JSON object" {
    try std.testing.expect(shouldSkipAll(
        \\{
        \\  "Version": "2012-10-17",
        \\  "Statement": [
        \\    {"Effect": "Allow"}
        \\  ]
        \\}
    ));
}

test "shouldSkipAll: JSON array" {
    try std.testing.expect(shouldSkipAll(
        \\["a", "b", "c"]
    ));
}

test "shouldSkipAll: JSON with surrounding whitespace" {
    try std.testing.expect(shouldSkipAll("\n\n  { \"x\": 1 }  \n"));
}

test "shouldSkipAll: not JSON — prose" {
    try std.testing.expect(!shouldSkipAll("just some prose."));
}

test "shouldSkipAll: not JSON — empty" {
    try std.testing.expect(!shouldSkipAll(""));
}

test "shouldSkipAll: not JSON — incomplete object" {
    try std.testing.expect(!shouldSkipAll("{ unfinished"));
}

test "shouldSkipAll: not JSON — incomplete array" {
    try std.testing.expect(!shouldSkipAll("[1, 2"));
}

test "shouldSkipAll: not JSON — starts with { but ends with letter" {
    try std.testing.expect(!shouldSkipAll("{a,b,c} expands to a b c"));
}

test "shouldSkipAll: not JSON — shell brace expansion alone is treated as JSON-like (acceptable false positive)" {
    // `{a,b,c}` starts with `{` and ends with `}` — our heuristic treats it
    // as JSON-like and bypasses the pipeline. This is a known false positive
    // and an acceptable tradeoff: shell brace expansion in a clipboard paste
    // is rare, and not transforming it is harmless.
    try std.testing.expect(shouldSkipAll("{a,b,c}"));
}
