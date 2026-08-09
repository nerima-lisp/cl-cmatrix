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
`-n`), changing glyphs (`-k`), the lambda render mode (`-m`), rainbow columns
(`-r`), the centered message (`-M`), synchronous/old-style timing (`-o`),
classic CJK glyphs (`-c`), color selection (`-C`), upstream update delay (`-u`),
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
| `-c` classic Japanese glyphs | `-c`, `--classic`, `--japanese` | Draws upstream's own range: CJK Symbols and Punctuation, U+3000-U+303E. |
| `-C` color | `-C`, `--color` | Accepts the registered schemes and `rainbow`. |
| `-s` screensaver | `-s`, `-S`, `--screensaver` | `-S` remains as a compatibility alias. |
| `-u` update delay | `-u`, `--update-delay`, `--delay` | Integer 0..10 in 10ms units; default 4. |
| `--fps` extension | `--fps` | 1..240 ticks per second; explicit `--fps` takes precedence over `-u`. |
| `-f` force Linux `$TERM` | `-f`, `--force-linux-term` | Sets `TERM=linux` only while this invocation runs. |

## `-c` is upstream's `-c`, and katakana is ours

Upstream's `-c` sets `randmin = 12288` and draws `rand() % 63 + 12288`: the
63 code points from U+3000 to U+303E, the CJK Symbols and Punctuation block.
`cl-cmatrix -c` draws that same range, so the two programs agree on what the
flag means.

Half-width katakana (U+FF66-U+FF9D) is an extension of this project with no
upstream counterpart, reachable only through
[`--charset katakana`](../getting-started.md#glyph-sets-and-what-c-actually-draws).
It is the closer match to the film's look, since upstream's own film-like
glyphs come from a non-free bitmap font this project does not ship. That
resemblance is precisely why it is not bound to `-c`: a `-c` that drew a
different range from upstream's `-c` would look better and be wrong, and a
user comparing the two programs side by side would see them disagree. During
development `-c` did select katakana, with `--katakana` as a further spelling
of it; that is fixed, and `--katakana` is now rejected as an unknown option
rather than kept as an alias.

| Flag | Glyphs | Origin |
| --- | --- | --- |
| `-c`, `--classic`, `--japanese` | U+3000-U+303E, 63 CJK symbols | Upstream cmatrix's `-c`, reproduced by code point |
| `--charset katakana`, `-g katakana` | U+FF66-U+FF9D, 56 half-width katakana | This project only; no upstream equivalent |

`-m`/`--lambda` is not a glyph set. It is upstream's render mode, drawing a
lambda in place of every non-head character over whichever set is in force,
so it composes with `-c` and `--charset` rather than overriding them. There
is no `--charset lambda`; that spelling is rejected.

## Charset rendering

`-c` and `--charset katakana` both draw outside ASCII, so each renders as
intended only in a terminal and font covering its range -- U+3000 through
U+303E for `-c`, U+FF66 through U+FF9D for katakana. A terminal falling back
to a substitute glyph or a box for those code points still runs the animation
correctly, since the glyph choice is cosmetic, but will not show the intended
character shapes. `--charset ascii` (the default) and `--charset binary` need
nothing beyond a plain printable-ASCII-capable terminal.

## Permanent non-goals

Linux console font selection (`-l`) and X window mode (`-x`) are **not going
to be implemented**. They are declined by design rather than pending, and
`cl-cmatrix` rejects them with an unknown-option error.

Both live outside the portable text-terminal abstraction `cl-tty-kit`
provides: `-l` reprograms a Linux virtual-console font and `-x` opens a
window, so each needs a platform-specific console or window-system backend
that neither this project nor `cl-tty-kit` has, on platforms this project
does not gate. Accepting them silently as no-ops would be the less compatible
choice -- a script that passes `-x` and gets a plain terminal animation has
been misled, whereas a script that passes `-x` and gets an error learns
immediately that this is a different program. Treat their absence as settled,
not as a gap awaiting a contribution.

## Release stability

Releases are tagged (`vX.Y.Z`) and consumers depending on `cl-cmatrix` from
another flake must pin to a tag rather than follow the default branch --
see [Getting started](../getting-started.md) for the exact input shape. A
bare `github:nerima-lisp/cl-cmatrix` reference tracks `main` and can change
the build without warning.
