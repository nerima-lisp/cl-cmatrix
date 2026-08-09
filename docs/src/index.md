# cl-cmatrix

`cl-cmatrix` is a **Matrix-style digital rain terminal screensaver** for
SBCL. Streams fall independently down every other screen column, each one
bright at its leading character and dimming toward the terminal background
over its trail, drawn with
[cl-tty-kit](https://github.com/nerima-lisp/cl-tty-kit)'s 256-color support.
The screen reflows automatically when the terminal is resized, and the
animation quits cleanly -- always restoring the terminal's prior, non-raw
state -- on `q`, `Escape`, or Ctrl-C.

The animation follows upstream `cmatrix` 2.0 rather than reinterpreting it.
Streams animate every other screen column and leave the odd ones blank; a
column is a buffer of cells that a scan rewrites in place, not a head
dragging a trail behind it; the default glyphs are upstream's own `!`
through `z` (U+0021-U+007A); and `-c` draws the CJK Symbols and Punctuation
block (U+3000-U+303E) that upstream's `-c` draws. It follows upstream's
algorithm, not its source: every character of the implementation is
original Lisp.

The color gradient is the deliberate departure, and the one place this
project does not follow upstream. Upstream paints a whole stream in a single
color and whitens only its head; here every trail is a 256-color fade from a
white head through a named scheme's bright color down to the background,
with `rainbow` drawing each column from a different scheme.

Half-width katakana (`--charset katakana`) and a 0/1 set
(`--charset binary`) are extensions of ours with no upstream equivalent.
Katakana is the closest a Unicode terminal font gets to the film's look
without depending on upstream's non-free bitmap font -- which is exactly why
it is not what `-c` selects here.

Every source of randomness in the animation -- fall timing, glyph choice,
and reset -- is routed through an injected `RANDOM-STATE` rather than the
global `*RANDOM-STATE*`, so a run started from a fixed seed produces
byte-identical output on every replay. That is what the test suite in `t/`
relies on.

Start with [Getting Started](getting-started.md), then see the
[API Reference](reference/api.md) for `cl-cmatrix:run-matrix` and the rest of
the public surface. [Conditions](reference/conditions.md) documents every
error `cl-cmatrix` signals, [Architecture](reference/architecture.md)
explains how the pieces fit together, and
[Compatibility](reference/compatibility.md) covers SBCL/platform
requirements.
