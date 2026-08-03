# API Reference

Everything below is exported from the `cl-cmatrix` package. The command-line
front end lives in the separate `cl-cmatrix/cli` package (`make-cmatrix-app`,
`main`, `image-entry-point`) and is documented by `cl-cmatrix --help`.

## Running the animation

### `run-matrix`

```lisp
(run-matrix &key (speed 1) (color :green) (glyphs +default-glyphs+) (bold nil)
                 (stream *standard-output*)
                 (input-stream *standard-input*) (fd 0)
                 (fps 30) (random-state (make-random-state t)))
```

Run the full-screen animation on `stream` until a quit key (`q`, `Q`,
`Escape`, or Ctrl-C) is read from `input-stream`. Enters raw mode and the
terminal's alternate screen for the duration and always restores both.
`speed`, `color`, `glyphs`, and `bold` are as in
[`make-matrix-state`](#make-matrix-state). `fps` is the target tick rate
(default 30, see [`+default-fps+`](#default-fps)). `random-state` seeds the
fall-timing and glyph randomness. Returns the final
[`matrix-state`](#matrix-state).

## Building a custom driver loop

`run-matrix` bundles terminal setup, a real-time tick loop, and quit-key
handling around a [`matrix-state`](#matrix-state). A caller who wants
different I/O -- a custom event loop, a non-terminal renderer, or its own
quit-key policy -- can drive the animation directly with the pieces below
instead of calling `run-matrix`.

### `+default-fps+`

`run-matrix`'s default tick rate: 30 ticks per second.

### `run-state`

```lisp
(make-run-state &key matrix renderer quitp input-stream)
```

The mutable driver state threaded through
`cl-tty-kit:tick-loop-run-realtime`. Readers: `run-state-matrix` (the
[`matrix-state`](#matrix-state) proper), `run-state-renderer` (the
double-buffered `cl-tty-kit` repaint helper), `run-state-quitp` (set once a
quit key has been seen), `run-state-input-stream` (where `poll-quit-key`
looks for one). Kept separate from `matrix-state` so that struct stays free
of I/O and can go on being used by the pure, deterministic tests in `t/`.

### `run-state-poll`

```lisp
(run-state-poll run-state &key (fd 0) (terminal-size-fn #'terminal-size))
```

Observe the real terminal ahead of `run-state`'s next tick: reflow for the
current terminal size (via `terminal-size-fn`), resize the renderer to
match, and record whether a quit key has arrived on `run-state`'s
`input-stream`. Returns `run-state`, mutated in place -- this is the `:poll`
half of the poll/advance split `cl-tty-kit:tick-loop-run-realtime`'s own
`:poll` argument drives (added in `cl-tty-kit` v1.4.0), run once before
every tick's `run-state-advance`.

### `run-state-advance`

```lisp
(run-state-advance run-state)
```

Advance `run-state`'s underlying `matrix-state` by one tick via
[`matrix-advance`](#matrix-advance). Returns `run-state`, mutated in place --
the pure-given-`random-state` half of the poll/advance split; terminal
observation is `run-state-poll`'s job instead. Never used by the
deterministic bounded-tick tests, which only exercise `matrix-advance`
directly.

### `run-state-render`

```lisp
(run-state-render run-state)
```

Redraw `run-state`'s renderer back buffer from its current `matrix-state`
and return the diffed ANSI frame string for this tick.

### `quit-key-character-p` / `poll-quit-key` / `poll-quit-key-cps`

```lisp
(quit-key-character-p character)
(poll-quit-key stream)
(poll-quit-key-cps stream on-quit on-continue)
```

`quit-key-character-p` is true when `character` should stop the animation:
`q`, `Q`, or `Escape`, or the raw Ctrl-C byte (character code 3).
`poll-quit-key` consumes every character currently available on `stream`
without blocking, returning true as soon as one of them satisfies
`quit-key-character-p` (the rest, if any, are still consumed, since none of
them will be looked at again). Used instead of a blocking read because a
real-time animation loop cannot afford to wait on a key that may never
come; works against any character stream -- including a
`string-input-stream` in a test -- not only a live terminal.

`poll-quit-key-cps` is `poll-quit-key`'s own implementation, in
continuation-passing style: it calls `on-quit` with the offending character
the moment one is found, or `on-continue` with no arguments once `stream` is
exhausted without one. `poll-quit-key` is a thin direct-style wrapper over
it. Use `poll-quit-key-cps` directly when a caller wants the actual quit
character rather than only a boolean -- for example to log which of
q/Q/Escape/Ctrl-C ended a run.

Together these compose the loop `run-matrix` itself drives: `make-run-state`
builds the initial state around a `matrix-state` and a renderer, each tick
calls `run-state-poll` (which polls `poll-quit-key` on the `input-stream`),
then `run-state-advance`, then `run-state-render`, and the loop stops once
`run-state-quitp` is true.

## Building and advancing state

### `make-matrix-state`

```lisp
(make-matrix-state width height &key (speed 1) (color :green)
                                      (glyphs +default-glyphs+)
                                      (bold nil)
                                      (random-state (make-random-state t)))
```

Create a `matrix-state` of `width` by `height` columns. `speed` is a
positive real fall-speed multiplier (larger falls faster); `color` names one
of [`list-color-schemes`](#list-color-schemes), or `:rainbow` to draw each
column from a different scheme (see [`matrix-draw`](#matrix-draw)). `glyphs`
is the glyph set columns draw from (see [`charset-glyphs`](#charset-glyphs)
for the built-in sets). `bold`, when true, renders every lit row bold rather
than only the head. Signals [`invalid-dimensions`](#invalid-dimensions),
[`invalid-speed`](#invalid-speed), or
[`unknown-color-scheme`](#unknown-color-scheme) on bad input.

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
`matrix-state-glyphs`, `matrix-state-bold`, `matrix-state-tick`.

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
`:red`, `:blue`, `:magenta`, `:yellow`, `:white`, `:purple`, `:orange`,
`:amber`, `:pink`.

### `color-scheme-p`

```lisp
(color-scheme-p name)
```

True when `name` is a registered color scheme.

### `color-choice-p`

```lisp
(color-choice-p name)
```

True when `name` is a valid `--color`/`make-matrix-state` `:color` value: a
registered scheme name, or `:rainbow` (see [`matrix-draw`](#matrix-draw) for
how `:rainbow` resolves to a real scheme per column).

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

### `+katakana-glyphs+`

Half-width katakana glyphs, U+FF66 through U+FF9D inclusive (56
characters) -- the closest a Unicode terminal font gets to the classic
`cmatrix` bitmap font's look.

### `+binary-glyphs+`

A two-character glyph set of just `#\0` and `#\1`, for a binary-rain look.

### `random-glyph`

```lisp
(random-glyph glyphs random-state)
```

Return a character drawn uniformly at random from `glyphs`, using
`random-state`.

### `list-charsets`

```lisp
(list-charsets)
```

Return every registered `--charset` name: `:ascii` (the default),
`:katakana`, `:binary`.

### `charset-p`

```lisp
(charset-p name)
```

True when `name` is a registered charset.

### `charset-glyphs`

```lisp
(charset-glyphs name)
```

Return the glyph `simple-vector` `name` names (`:ascii` ->
[`+default-glyphs+`](#default-glyphs), `:katakana` ->
[`+katakana-glyphs+`](#katakana-glyphs), `:binary` ->
[`+binary-glyphs+`](#binary-glyphs)). Signals
[`unknown-charset`](#unknown-charset) when `name` is not registered.

## Rendering

### `matrix-draw`

```lisp
(matrix-draw screen state)
```

Draw every column of `state`'s current frame onto a `cl-tty-kit` `screen`.
When `state`'s `color` is `:rainbow`, each column is resolved to a
different real scheme by column index (cycling through
[`list-color-schemes`](#list-color-schemes)) rather than all columns
sharing one.

### `matrix-cell-style`

```lisp
(matrix-cell-style color offset trail-length &optional bold)
```

The `cl-tty-kit` style for a cell `offset` rows behind its column's head,
under the named color scheme `color` (a real registered scheme, never
`:rainbow`). The head (`offset` 0) is always bold; `bold`, when true, also
renders every other lit row bold.

## Conditions

See [Conditions](conditions.md) for the full hierarchy and each condition's
slots. Summarized here as part of the exhaustive symbol list:

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

Signaled when `color` names no registered scheme and is not `:rainbow`.
`unknown-color-scheme-name` reads the offending name back.

### `unknown-charset`

Signaled by [`charset-glyphs`](#charset-glyphs) when `name` names no charset
registered in [`list-charsets`](#list-charsets). `unknown-charset-name`
reads the offending name back.
