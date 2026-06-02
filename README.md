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

## Install

### Homebrew (macOS, Linux)

```sh
brew tap andperks6/topiarius
brew install topiarius
```

### Pre-built binary

Grab a binary for your platform from the [latest
release](https://github.com/andperks6/topiarius/releases/latest) and put it
on your `$PATH`. macOS Gatekeeper may quarantine downloaded files; clear it
with:

```sh
xattr -d com.apple.quarantine ~/Downloads/topia-aarch64-macos
chmod +x ~/Downloads/topia-aarch64-macos
mv ~/Downloads/topia-aarch64-macos /usr/local/bin/topia
```

### From source

Requires Zig 0.16.

```sh
zig build -Doptimize=ReleaseSafe
./zig-out/bin/topia --help
```

Cross-compile every supported target in one go:

```sh
zig build release
ls zig-out/release/
# topia-aarch64-linux  topia-aarch64-macos  topia-x86_64-linux  topia-x86_64-macos
```

## Usage

```
topia transform [--low|--normal|--high]    Read stdin, trim, write stdout
topia once      [--low|--normal|--high]    Read clipboard, trim, write back
topia daemon    [--low|--normal|--high]    Poll the clipboard and trim in place
topia shell-hook (zsh|bash|fish)           Print precmd snippet for eval
```

Trim-on-paste by sourcing the hook in your shell rc:

```zsh
eval "$(topia shell-hook zsh)"
```

## Running as a daemon

`topia daemon` is a foreground poll loop: it reads the clipboard every
250 ms, trims dirty pastes, and remembers a hash of each write so it
never re-trims work it already did. Run it under your service manager
of choice (launchd plist / systemd user unit emission lands in v0.2-d):

```sh
topia daemon --normal
```

`SIGINT` and `SIGTERM` shut it down cleanly. `SIGHUP` is reserved for
future config reload and currently a no-op.

**Known limitation:** v0.2-a shells out to `pbpaste` / `pbcopy` /
`wl-paste` / `wl-copy`. Those tools strip MIME-type hints, so the
daemon cannot honor `NSPasteboardTypeTransient` or Wayland's
`password` MIME marker yet. Privacy gating ships with v0.2-b once the
native `@cImport` backends are in.

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

- **v0.2-a** (current) — `topia daemon` poll loop on existing shell-out backends
- **v0.2-b** — native macOS clipboard via `@cImport(NSPasteboard)` + privacy gating
- **v0.2-c** — IPC socket (`topia status / reload / toggle / stats`)
- **v0.2-d** — `topia install` emitting launchd plist / systemd user unit
- **v0.3** — event-driven Linux backends (`wlr-data-control` on Wayland, XFIXES on X11)
- **v0.4** — Windows backend via `AddClipboardFormatListener`
