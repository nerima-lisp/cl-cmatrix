# Compatibility

## SBCL only

`cl-cmatrix` requires SBCL. `src/package.lisp` refuses to load under any
other implementation with a clear error at `defpackage` time, rather than
failing later and less clearly on a missing symbol. The reason is
transitive, not a preference of this project's own: `cl-cmatrix` depends on
[`cl-tty-kit`](https://nerima-lisp.github.io/cl-tty-kit/) for raw mode, the
alternate screen, and the real-time tick loop, and `cl-tty-kit` is itself
SBCL-only. There is no portability layer to add here that would not also
need one in `cl-tty-kit` first.

## Platforms

Unix only (Linux, macOS). Raw terminal mode and the alternate screen are
POSIX terminal features with no Windows equivalent in `cl-tty-kit`.

CI gates `x86_64-linux`. `aarch64-darwin` is declared for local development
on that architecture but carries no CI gate of its own -- a package built
there is not independently verified the way the gated platform is.

## cmatrix controls

The animation and terminal controls that are meaningful in a POSIX text
terminal are available: asynchronous columns (`-a`), bold modes (`-b`, `-B`,
`-n`), changing glyphs (`-k`), lambda glyphs (`-m`), rainbow columns (`-r`),
the centered message (`-M`), synchronous/old-style timing (`-o`), classic
Japanese glyphs (`-c`), color selection (`-C`), upstream update delay (`-u`),
and screensaver mode (`-s`, `-S`, `--screensaver`), lock mode (`-L`,
`--lock`), Linux terminal forcing (`-f`, `--force-linux-term`), and alternate
tty selection (`-t`, `--tty`). Runtime keys include `q`, `Q`, `Escape`, Ctrl-C, `L`, `a`,
`b`, `B`, `n`, `k`, `m`, `p`, `P`, `0` through `9`, and the classic color keys.
In screensaver mode, the first input event exits. Lock mode ignores quit keys
and interactive interrupts; `-f` changes `TERM` only for the current
invocation.

The upstream short options that have a portable text-terminal equivalent keep
their upstream spelling:

| Upstream spelling | `cl-cmatrix` spelling | Reason |
| --- | --- | --- |
| `-c` classic Japanese glyphs | `-c`, `--classic`, `--katakana`, `--charset katakana` | Uses Unicode half-width katakana. |
| `-C` color | `-C`, `--color` | Accepts the registered schemes and `rainbow`. |
| `-s` screensaver | `-s`, `-S`, `--screensaver` | `-S` remains as a compatibility alias. |
| `-u` update delay | `-u`, `--update-delay`, `--delay` | Integer 0..10 in 10ms units; default 4. |
| `--fps` extension | `--fps` | 1..240 ticks per second; explicit `--fps` takes precedence over `-u`. |
| `-f` force Linux `$TERM` | `-f`, `--force-linux-term` | Sets `TERM=linux` only while this invocation runs. |

Linux console font selection (`-l`) and X window mode (`-x`) remain outside
the portable `cl-tty-kit` text-terminal abstraction and are intentionally not
accepted. They require platform-specific console or window-system backends;
silently accepting them as no-ops would be less compatible than rejecting
them.

## Charset rendering

[`--charset katakana`](../getting-started.md#the-command-line) and its
half-width katakana glyphs render correctly only in a terminal and font that
cover that Unicode range (U+FF66 through U+FF9D). A terminal falling back to
a substitute glyph or a box for those code points will still run the
animation correctly -- the glyph choice is cosmetic -- but will not show the
intended character shapes. `--charset ascii` (the default) and `--charset
binary` need nothing beyond a plain printable-ASCII-capable terminal.

## Release stability

Releases are tagged (`vX.Y.Z`) and consumers depending on `cl-cmatrix` from
another flake must pin to a tag rather than follow the default branch --
see [Getting started](../getting-started.md) for the exact input shape. A
bare `github:nerima-lisp/cl-cmatrix` reference tracks `main` and can change
the build without warning.
