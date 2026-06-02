//! Heuristic: join "soft-wrapped" lines that look like prose continuations.
//!
//! A newline is replaced with a single space when:
//!   1. The line just ended doesn't end with a sentence terminator (`.`, `!`, `?`),
//!      a code-syntax closer (`{`, `}`, `;`), and isn't a single-line comment.
//!   2. The line just ended does NOT have an unclosed `'` or `"` quote — those
//!      mark mid-string wraps (e.g., terminal-wrapped `--flag='value1,RE\n ASON'`)
//!      where joining with a space corrupts the literal.
//!   3. The next line starts with at least one whitespace char (a continuation
//!      indent), and its first non-whitespace content is NOT a structural
//!      marker — list bullet (`- `, `* `, `+ `, `> `), header (`#`), C-style
//!      line comment (`//`), numbered list (`1. ` / `1) `), code fence (```),
//!      or horizontal rule.
//!
//! Conservative on purpose: prefers leaving a break over wrongly joining.

const std = @import("std");
const Allocator = std.mem.Allocator;

const sentence_terminators = ".!?";

pub fn apply(allocator: Allocator, input: []const u8) Allocator.Error![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    try out.ensureTotalCapacity(allocator, input.len);

    var cursor: usize = 0;
    while (cursor < input.len) {
        const newline_at = std.mem.indexOfScalarPos(u8, input, cursor, '\n') orelse {
            try out.appendSlice(allocator, input[cursor..]);
            break;
        };
        const line = input[cursor..newline_at];
        const next_start = newline_at + 1;

        if (next_start >= input.len) {
            try out.appendSlice(allocator, line);
            try out.append(allocator, '\n');
            break;
        }

        const next_newline = std.mem.indexOfScalarPos(u8, input, next_start, '\n') orelse input.len;
        const next_line = input[next_start..next_newline];

        if (shouldJoin(line, next_line)) {
            try out.appendSlice(allocator, line);
            try out.append(allocator, ' ');
            cursor = next_start + leadingWhitespace(next_line);
        } else {
            try out.appendSlice(allocator, line);
            try out.append(allocator, '\n');
            cursor = next_start;
        }
    }
    return out.toOwnedSlice(allocator);
}

fn leadingWhitespace(line: []const u8) usize {
    var offset: usize = 0;
    while (offset < line.len and (line[offset] == ' ' or line[offset] == '\t')) : (offset += 1) {}
    return offset;
}

fn shouldJoin(a: []const u8, b: []const u8) bool {
    if (a.len == 0 or b.len == 0) return false;

    const a_last = lastNonWhitespace(a) orelse return false;
    for (sentence_terminators) |t| if (a_last == t) return false;

    // Code-syntax line endings — `{`, `}`, and `;` rarely close prose, but
    // almost always close a code statement or block. Better to leave the
    // break alone than to join lines of code into a long ribbon.
    if (a_last == '{' or a_last == '}' or a_last == ';') return false;

    // Don't join if A is a single-line comment — its newline terminates
    // the comment in most syntaxes (Python/YAML/GraphQL/shell with `#`,
    // C/JS/Rust/Go with `//`).
    if (isCommentLine(a)) return false;

    // Don't join if A has an unclosed `'` or `"` quote. The break is then
    // almost certainly inside a string literal — a terminal-wrapped CLI
    // arg, JSON value with embedded newline, etc. — and adding a space
    // would silently corrupt the content.
    if (hasUnclosedQuote(a)) return false;

    const leading = leadingWhitespace(b);
    if (leading < 1) return false;

    const b_stripped = b[leading..];
    if (b_stripped.len == 0) return false;
    if (startsWithMarker(b_stripped)) return false;

    return true;
}

fn isCommentLine(line: []const u8) bool {
    const stripped_offset = leadingWhitespace(line);
    if (stripped_offset >= line.len) return false;
    const body = line[stripped_offset..];
    if (body.len == 0) return false;
    if (body[0] == '#') return true;
    if (body.len >= 2 and body[0] == '/' and body[1] == '/') return true;
    return false;
}

fn hasUnclosedQuote(line: []const u8) bool {
    var in_single = false;
    var in_double = false;
    var escape = false;
    for (line) |c| {
        if (escape) {
            escape = false;
            continue;
        }
        if ((in_single or in_double) and c == '\\') {
            escape = true;
            continue;
        }
        if (c == '\'' and !in_double) in_single = !in_single;
        if (c == '"' and !in_single) in_double = !in_double;
    }
    return in_single or in_double;
}

fn lastNonWhitespace(line: []const u8) ?u8 {
    var i = line.len;
    while (i > 0) {
        i -= 1;
        const c = line[i];
        if (c != ' ' and c != '\t') return c;
    }
    return null;
}

fn startsWithMarker(s: []const u8) bool {
    if (s.len < 2) return false;
    // Bullets: "- ", "* ", "+ ", "> "
    if ((s[0] == '-' or s[0] == '*' or s[0] == '+' or s[0] == '>') and s[1] == ' ') return true;
    // Markdown header / `#`-style comment
    if (s[0] == '#') return true;
    // C-style line comment
    if (s[0] == '/' and s[1] == '/') return true;
    // Fenced code block
    if (s.len >= 3 and std.mem.eql(u8, s[0..3], "```")) return true;
    // Horizontal rules
    if (s.len >= 3 and (std.mem.eql(u8, s[0..3], "---") or std.mem.eql(u8, s[0..3], "==="))) return true;
    // Numbered list "1. " or "1) "
    if (std.ascii.isDigit(s[0])) {
        var i: usize = 0;
        while (i < s.len and std.ascii.isDigit(s[i])) : (i += 1) {}
        if (i < s.len - 1 and (s[i] == '.' or s[i] == ')') and s[i + 1] == ' ') return true;
    }
    return false;
}

test "soft_wraps: joins continuation under same bullet" {
    const out = try apply(std.testing.allocator,
        "  - Resize obscure — toggle on select-mode handles. Now: clicking auto-enters\n  select so the toggle is visible.\n");
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings(
        "  - Resize obscure — toggle on select-mode handles. Now: clicking auto-enters select so the toggle is visible.\n",
        out,
    );
}

test "soft_wraps: keeps break before next bullet" {
    const out = try apply(std.testing.allocator, "  - foo.\n  - bar.\n");
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("  - foo.\n  - bar.\n", out);
}

test "soft_wraps: keeps break after sentence terminator" {
    const out = try apply(std.testing.allocator, "Done.\n  but later we add more.\n");
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("Done.\n  but later we add more.\n", out);
}

test "soft_wraps: keeps break when continuation has no leading whitespace" {
    const out = try apply(std.testing.allocator, "no terminator\nnext line flush left\n");
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("no terminator\nnext line flush left\n", out);
}

test "soft_wraps: keeps break inside unclosed quote (terminal mid-word wrap)" {
    // The kubectl-output case: terminal wrapped `REASON` mid-word inside a
    // single-quoted CLI flag. The unclosed `'` on the first line is the signal.
    const input = "cmd --flag='value1,RE\n ASON:value2'\n";
    const out = try apply(std.testing.allocator, input);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings(input, out);
}

test "soft_wraps: joins single-space prose continuation outside quotes" {
    const input = "Cross-org leak. Key is a static \"poc\" with no user\n namespacing applied.\n";
    const out = try apply(std.testing.allocator, input);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings(
        "Cross-org leak. Key is a static \"poc\" with no user namespacing applied.\n",
        out,
    );
}

test "soft_wraps: keeps break after `#` comment line (GraphQL/Python)" {
    const input =
        "  ) { project(id: $id) { id name\n" ++
        "  # Deprecated User.projectId column — what Project.users returns unbounded\n" ++
        "  rosterByDeprecatedProjectId: users { id firstName lastName }\n";
    const out = try apply(std.testing.allocator, input);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings(input, out);
}

test "soft_wraps: keeps break after `//` line comment (C/JS/Rust)" {
    const input =
        "function foo() {\n" ++
        "  // initialize state before mutation\n" ++
        "  state.value = compute();\n";
    const out = try apply(std.testing.allocator, input);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings(input, out);
}

test "soft_wraps: joins after comma" {
    const out = try apply(std.testing.allocator, "first part,\n  second part.\n");
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("first part, second part.\n", out);
}

test "soft_wraps: joins after colon" {
    const out = try apply(std.testing.allocator, "list intro:\n  follow-up sentence.\n");
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("list intro: follow-up sentence.\n", out);
}

test "soft_wraps: preserves break before numbered list" {
    const out = try apply(std.testing.allocator, "intro\n  1. first\n");
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("intro\n  1. first\n", out);
}

test "soft_wraps: preserves break before code fence" {
    const out = try apply(std.testing.allocator, "see below\n  ```sh\n");
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("see below\n  ```sh\n", out);
}

test "soft_wraps: empty lines stay" {
    const out = try apply(std.testing.allocator, "para one\n\n  para two starts here\n");
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("para one\n\n  para two starts here\n", out);
}
