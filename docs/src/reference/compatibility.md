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
