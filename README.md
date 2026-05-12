# topiarius

A small cross-platform clipboard trimmer. Paste once, run once.

Takes shell snippets copied with the shape their source left them in —
prompt prefixes, backslash continuations, ANSI escapes, smart quotes,
box-drawing borders — and trims them back into paste-ready commands.

Binary: `topia`. The Latin word *topiarius* named the Roman gardener who
trimmed hedges into ornamental shapes.

## Status

v0.1 MVP. macOS and Linux clipboard via `pbpaste` / `pbcopy` /
`wl-paste` / `wl-copy` shell-outs. Daemon mode, native clipboard APIs,
and Windows support come in v0.2+.

## Build

Requires Zig 0.16.

```
zig build -Doptimize=ReleaseSafe
./zig-out/bin/topia --help
```

## Usage

```
topia transform [--low|--normal|--high]    Read stdin, trim, write stdout
topia once      [--low|--normal|--high]    Read clipboard, trim, write back
topia shell-hook (zsh|bash|fish)           Print precmd snippet for eval
```

Trim-on-paste by sourcing the hook in your shell rc:

```zsh
eval "$(topia shell-hook zsh)"
```

## Rule library

Aggressiveness levels are subsets of the full rule set:

- **low** — backslash + newline continuations, ANSI CSI/OSC escapes
- **normal** (default) — `low` + shell prompt prefixes (`$ `, `# `, `> `,
  `❯ `, `% `, `[user@host dir]$ `) + box-drawing characters + zero-width
  invisibles (ZWSP, ZWJ, ZWNJ, BOM)
- **high** — `normal` + curly-quote → straight-quote + em/en-dash →
  `--`/`-` + whitespace collapse

## Tests

```
zig build test
```

Unit tests live next to each rule. End-to-end cases live in
`test/fixtures/<name>[.<level>].in` with sibling `.out` files; the
fixture walker exercises each through `transform.transform`.

## Roadmap

- **v0.2** — `topia daemon` poll loop, native macOS clipboard via
  `@cImport(NSPasteboard)`, IPC socket, `topia install` for
  launchd / systemd units
- **v0.3** — event-driven Linux backends (`wlr-data-control` on Wayland,
  XFIXES on X11)
- **v0.4** — Windows backend via `AddClipboardFormatListener`
