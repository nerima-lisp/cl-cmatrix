# cl-cmatrix

`cl-cmatrix` is a **Matrix-style digital rain terminal screensaver** for
SBCL. Each terminal column falls independently: a bright head character
leads a color-graded trail that dims toward the terminal background over
its length, drawn with [cl-tty-kit](https://github.com/nerima-lisp/cl-tty-kit)'s
256-color support. The screen reflows automatically when the terminal is
resized, and the animation quits cleanly -- always restoring the terminal's
prior, non-raw state -- on `q`, `Escape`, or Ctrl-C.

This is not a port of the classic `cmatrix`'s proprietary katakana bitmap
font: the default glyph set is plain printable ASCII, a simpler and entirely
original choice, and every character of the implementation is original Lisp.

Every source of randomness in the animation -- fall timing, glyph choice,
and reset -- is routed through an injected `RANDOM-STATE` rather than the
global `*RANDOM-STATE*`, so a run started from a fixed seed produces
byte-identical output on every replay. That is what the test suite in `t/`
relies on.

Start with [Getting Started](getting-started.md), then see the
[API Reference](reference/api.md) for `cl-cmatrix:run-matrix` and the rest of
the public surface.
