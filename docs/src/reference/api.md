# API Reference

Everything below is exported from the `cl-cmatrix` package. The command-line
front end lives in the separate `cl-cmatrix/cli` package (`make-cmatrix-app`,
`main`, `image-entry-point`) and is documented by `cl-cmatrix --help`.

## Running the animation

### `run-matrix`

```lisp
(run-matrix &key (speed 1) (color :green) (stream *standard-output*)
                 (input-stream *standard-input*) (fd 0)
                 (fps 30) (random-state (make-random-state t)))
```

Run the full-screen animation on `stream` until a quit key (`q`, `Q`,
`Escape`, or Ctrl-C) is read from `input-stream`. Enters raw mode and the
terminal's alternate screen for the duration and always restores both.
`speed` and `color` are as in [`make-matrix-state`](#make-matrix-state).
`random-state` seeds the fall-timing and glyph randomness. Returns the final
[`matrix-state`](#matrix-state).

## Building and advancing state

### `make-matrix-state`

```lisp
(make-matrix-state width height &key (speed 1) (color :green)
                                      (glyphs +default-glyphs+)
                                      (random-state (make-random-state t)))
```

Create a `matrix-state` of `width` by `height` columns. `speed` is a
positive real fall-speed multiplier (larger falls faster); `color` names one
of [`list-color-schemes`](#list-color-schemes). Signals
[`invalid-dimensions`](#invalid-dimensions), [`invalid-speed`](#invalid-speed),
or [`unknown-color-scheme`](#unknown-color-scheme) on bad input.

### `matrix-advance`

```lisp
(matrix-advance state)
```

Advance every column of `state` by one tick, returning a new `matrix-state`.
Pure given an already-positioned `random-state`: the same seed and tick
count always reach the same column state.

### `matrix-resize`

```lisp
(matrix-resize state new-width new-height)
```

Return `state` reflowed to `new-width` by `new-height`. Existing columns are
kept exactly; a widened matrix spawns fresh columns from `state`'s own
random state.

### `matrix-state`

The struct itself. Readers: `matrix-state-width`, `matrix-state-height`,
`matrix-state-columns` (a `simple-vector` of [`column`](#column)),
`matrix-state-random-state`, `matrix-state-speed`, `matrix-state-color`,
`matrix-state-glyphs`, `matrix-state-tick`.

## Columns

### `column`

One falling character stream. Readers: `column-head` (the row of its
brightest character), `column-length` (how many rows behind the head are
lit), `column-interval` and `column-counter` (fall-timing state),
`column-glyphs` (the raw glyph ring buffer -- prefer `column-glyph-at-row`).

### `column-glyph-at-row` / `column-row-lit-p`

```lisp
(column-glyph-at-row column row)
(column-row-lit-p column row)
```

The glyph `column` shows at `row`, and whether `row` is currently part of
`column`'s lit trail.

## Color schemes

### `list-color-schemes`

```lisp
(list-color-schemes)
```

Return every registered scheme name: `:green` (the default), `:cyan`,
`:red`, `:blue`, `:magenta`, `:yellow`, `:white`.

### `color-scheme-head-rgb` / `color-scheme-bright-rgb` / `color-scheme-dark-rgb`

```lisp
(color-scheme-head-rgb name)
(color-scheme-bright-rgb name)
(color-scheme-dark-rgb name)
```

The head color, the trail's brightest color, and the color it dims toward,
as RGB triples. Signal [`unknown-color-scheme`](#unknown-color-scheme) for
an unregistered `name`.

## Glyphs

### `+default-glyphs+`

Every printable ASCII character except space (94 characters). Any non-empty
`simple-vector` of characters may be passed to `make-matrix-state`'s
`:glyphs` instead.

### `random-glyph`

```lisp
(random-glyph glyphs random-state)
```

Return a character drawn uniformly at random from `glyphs`, using
`random-state`.

## Rendering

### `matrix-draw`

```lisp
(matrix-draw screen state)
```

Draw every column of `state`'s current frame onto a `cl-tty-kit` `screen`.

### `matrix-cell-style`

```lisp
(matrix-cell-style color offset trail-length)
```

The `cl-tty-kit` style for a cell `offset` rows behind its column's head,
under the named color scheme `color`.

## Conditions

### `cl-cmatrix-error`

Base condition for every error `cl-cmatrix` signals.

### `invalid-dimensions`

Signaled when a width or height is not a positive integer.
`invalid-dimensions-width` / `invalid-dimensions-height` read the offending
values back.

### `invalid-speed`

Signaled when `speed` is not a positive real. `invalid-speed-speed` reads
the offending value back.

### `unknown-color-scheme`

Signaled when `color` names no registered scheme.
`unknown-color-scheme-name` reads the offending name back.
