//! Emit shell `precmd`-style snippets that call `topia once` after every
//! prompt redraw. The user is expected to `eval "$(topia shell-hook zsh)"`
//! in their rc file.

const std = @import("std");
const Io = std.Io;

pub const Shell = enum { zsh, bash, fish };

pub fn parse(name: []const u8) ?Shell {
    if (std.mem.eql(u8, name, "zsh")) return .zsh;
    if (std.mem.eql(u8, name, "bash")) return .bash;
    if (std.mem.eql(u8, name, "fish")) return .fish;
    return null;
}

const zsh_snippet =
    \\topia_precmd() { topia once >/dev/null 2>&1 || true; }
    \\typeset -ga precmd_functions
    \\if [[ -z "${precmd_functions[(r)topia_precmd]:-}" ]]; then
    \\  precmd_functions+=(topia_precmd)
    \\fi
    \\
;

const bash_snippet =
    \\_topia_precmd() { topia once >/dev/null 2>&1 || true; }
    \\case ";${PROMPT_COMMAND:-};" in
    \\  *";_topia_precmd;"*) ;;
    \\  *) PROMPT_COMMAND="_topia_precmd;${PROMPT_COMMAND:-}" ;;
    \\esac
    \\
;

const fish_snippet =
    \\function __topia_precmd --on-event fish_prompt
    \\  topia once >/dev/null 2>&1; or true
    \\end
    \\
;

pub fn write(shell: Shell, writer: *Io.Writer) Io.Writer.Error!void {
    const text = switch (shell) {
        .zsh => zsh_snippet,
        .bash => bash_snippet,
        .fish => fish_snippet,
    };
    try writer.writeAll(text);
}

test "shell_hook: parse names" {
    try std.testing.expectEqual(@as(?Shell, .zsh), parse("zsh"));
    try std.testing.expectEqual(@as(?Shell, .bash), parse("bash"));
    try std.testing.expectEqual(@as(?Shell, .fish), parse("fish"));
    try std.testing.expectEqual(@as(?Shell, null), parse("nu"));
}
