//! Strip ANSI CSI (`ESC [ ... final`) and OSC (`ESC ] ... ST|BEL`) escape
//! sequences. A malformed or unterminated sequence is passed through verbatim
//! so the user can see what arrived.

const std = @import("std");
const Allocator = std.mem.Allocator;

const esc = 0x1B;
const bel = 0x07;

pub fn apply(allocator: Allocator, input: []const u8) Allocator.Error![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    try out.ensureTotalCapacity(allocator, input.len);

    var byte_index: usize = 0;
    while (byte_index < input.len) {
        const c = input[byte_index];
        if (c != esc or byte_index + 1 >= input.len) {
            try out.append(allocator, c);
            byte_index += 1;
            continue;
        }

        const next = input[byte_index + 1];
        switch (next) {
            // CSI: parameters in 0x30..0x3F, intermediates in 0x20..0x2F,
            // terminated by final byte in 0x40..0x7E.
            '[' => {
                var scan = byte_index + 2;
                while (scan < input.len) : (scan += 1) {
                    const b = input[scan];
                    if (b >= 0x40 and b <= 0x7E) break;
                }
                if (scan < input.len) {
                    byte_index = scan + 1;
                } else {
                    try out.append(allocator, c);
                    byte_index += 1;
                }
            },
            // OSC: terminated by BEL (0x07) or ST (ESC \).
            ']' => {
                var scan = byte_index + 2;
                var terminator_size: usize = 0;
                while (scan < input.len) : (scan += 1) {
                    const b = input[scan];
                    if (b == bel) {
                        terminator_size = 1;
                        break;
                    }
                    if (b == esc and scan + 1 < input.len and input[scan + 1] == '\\') {
                        terminator_size = 2;
                        break;
                    }
                }
                if (terminator_size != 0) {
                    byte_index = scan + terminator_size;
                } else {
                    try out.append(allocator, c);
                    byte_index += 1;
                }
            },
            else => {
                try out.append(allocator, c);
                byte_index += 1;
            },
        }
    }
    return out.toOwnedSlice(allocator);
}

test "ansi: strips SGR color codes" {
    const out = try apply(std.testing.allocator, "\x1b[31mhello\x1b[0m");
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("hello", out);
}

test "ansi: strips OSC title with BEL terminator" {
    const out = try apply(std.testing.allocator, "\x1b]0;title\x07echo");
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("echo", out);
}

test "ansi: strips OSC with ST terminator" {
    const out = try apply(std.testing.allocator, "\x1b]0;t\x1b\\after");
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("after", out);
}

test "ansi: passes through unrelated text" {
    const out = try apply(std.testing.allocator, "echo hi");
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("echo hi", out);
}
