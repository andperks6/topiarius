//! Strip shell prompt prefixes from the start of each line.
//!
//! Handled prefixes (after any leading horizontal whitespace):
//!   - `$ `, `# `, `> `, `% ` (ASCII single-char)
//!   - `❯ ` (U+276F)
//!   - `[user@host dir]$ ` / `[...]# ` style — leading `[`, the bracket body
//!     contains a space, terminated by `]$ ` or `]# `.

const std = @import("std");
const Allocator = std.mem.Allocator;

const wedge = "\xE2\x9D\xAF"; // ❯ U+276F

pub fn apply(allocator: Allocator, input: []const u8) Allocator.Error![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    try out.ensureTotalCapacity(allocator, input.len);

    var line_start: usize = 0;
    while (line_start <= input.len) {
        const newline_index = std.mem.indexOfScalarPos(u8, input, line_start, '\n') orelse input.len;
        const line = input[line_start..newline_index];
        const trimmed_offset = leadingWhitespace(line);
        const body = line[trimmed_offset..];
        const skip = promptPrefixLen(body);
        try out.appendSlice(allocator, line[0..trimmed_offset]);
        try out.appendSlice(allocator, body[skip..]);
        if (newline_index < input.len) try out.append(allocator, '\n');
        line_start = newline_index + 1;
    }
    return out.toOwnedSlice(allocator);
}

fn leadingWhitespace(line: []const u8) usize {
    var offset: usize = 0;
    while (offset < line.len and (line[offset] == ' ' or line[offset] == '\t')) : (offset += 1) {}
    return offset;
}

fn promptPrefixLen(body: []const u8) usize {
    // Single ASCII char + space.
    if (body.len >= 2) {
        const c = body[0];
        if ((c == '$' or c == '#' or c == '>' or c == '%') and body[1] == ' ') {
            return 2;
        }
    }
    // `❯ ` (U+276F = 3 bytes) + space.
    if (body.len >= wedge.len + 1 and std.mem.startsWith(u8, body, wedge) and body[wedge.len] == ' ') {
        return wedge.len + 1;
    }
    // `[anything with a space]$ ` or `]# `.
    if (body.len >= 4 and body[0] == '[') {
        if (std.mem.indexOfScalar(u8, body[1..], ']')) |rel_end| {
            const inside = body[1 .. 1 + rel_end];
            const after = body[1 + rel_end ..]; // includes the `]`
            if (after.len >= 3 and (after[1] == '$' or after[1] == '#') and after[2] == ' ') {
                if (std.mem.indexOfScalar(u8, inside, ' ') != null) {
                    return 1 + rel_end + 3;
                }
            }
        }
    }
    return 0;
}

test "prompts: dollar prefix" {
    const out = try apply(std.testing.allocator, "$ echo hi");
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("echo hi", out);
}

test "prompts: hash prefix" {
    const out = try apply(std.testing.allocator, "# apt update");
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("apt update", out);
}

test "prompts: wedge prefix" {
    const out = try apply(std.testing.allocator, "\xE2\x9D\xAF ls");
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("ls", out);
}

test "prompts: host bracket prefix" {
    const out = try apply(std.testing.allocator, "[user@host ~]$ pwd");
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("pwd", out);
}

test "prompts: multiple lines" {
    const out = try apply(std.testing.allocator, "$ a\n$ b\n");
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("a\nb\n", out);
}

test "prompts: leaves non-prompt lines alone" {
    const out = try apply(std.testing.allocator, "$echo\n  $ x\nplain");
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("$echo\n  x\nplain", out);
}
