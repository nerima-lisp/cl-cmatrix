# API Reference

Everything below is exported from the `cl-cmatrix` package. The command-line
front end lives in the separate `cl-cmatrix/cli` package (`make-cmatrix-app`,
`main`, `image-entry-point`) and is documented by `cl-cmatrix --help`.

## Running the animation

### `run-matrix`

```lisp
(run-matrix &key (speed 1) (color :green) (glyphs +default-glyphs+) (bold nil)
                 (asyncp t) (random-bold-p nil) (change-glyphs-p nil)
                 (screensaverp nil) (lockp nil) message
                 (stream *standard-output*)
                 (input-stream *standard-input*) (fd 0)
                 (fps +default-fps+) update-delay
                 (workers +default-workers+)
                 (random-state (make-random-state t)))
```

Run the full-screen animation on `stream` until a typed quit event (`q`, `Q`,
`Escape`, or Ctrl-C) is observed from `input-stream`. The stream is adapted
once to CL-TTY-KIT's input poller; callers do not need to parse raw
characters. Enters raw mode and the terminal's alternate screen for the
duration and always restores both.
`speed`, `color`, `glyphs`, and `bold` are as in
[`make-matrix-state`](#make-matrix-state). `fps` is the long-form target tick
rate (default 30, see [`+default-fps+`](#default-fps)). When `update-delay` is
non-NIL, it takes precedence over `fps` and is interpreted as 10ms units in
the upstream-compatible range 0 through 10 (default 4 when driven by the
CLI; see [`+default-update-delay+`](#default-update-delay)). `workers` controls the
persistent `cl-concurrent-kit` worker pool used for sufficiently wide
matrices (default 4, see [`+default-workers+`](#default-workers)); narrow
matrices stay on the serial transition path. `random-state` seeds the
fall-timing and glyph randomness. `asyncp` selects asynchronous column timing;
`random-bold-p` and `change-glyphs-p` enable the corresponding per-column
effects. `screensaverp` exits on the first input event, while `lockp` starts
with quit keys and interactive interrupts ignored. A non-NIL `message` is
centered over the animation. Returns the final
[`matrix-state`](#matrix-state).
Signals [`invalid-fps`](#invalid-fps) when `fps` is not a positive real
number, or [`invalid-update-delay`](#invalid-update-delay) when `update-delay`
is outside its integer 0 through 10 range, before terminal setup begins.

## Building a custom driver loop

`run-matrix` bundles terminal setup, a real-time tick loop, and quit-key
handling around a [`matrix-state`](#matrix-state). A caller who wants
different I/O -- a custom event loop, a non-terminal renderer, or its own
quit-key policy -- can drive the animation directly with the pieces below
instead of calling `run-matrix`.

### `+default-fps+`

`run-matrix`'s default tick rate: 30 ticks per second.

### `+default-update-delay+`

The upstream-compatible default update delay: 4 units of 10 milliseconds.

### `+default-workers+`

`run-matrix`'s default number of worker threads for wide matrix transitions:
4. The executor is created once per wide `run-matrix` invocation rather than
once per tick; narrow matrices do not start worker threads.

### `run-state`

```lisp
(make-run-state &key matrix renderer quitp lockp screensaverp pausedp message
                         input-poller render-context workers executor)
```

The mutable driver state threaded through
`cl-tty-kit:tick-loop-run-realtime`. Readers: `run-state-matrix` (the
[`matrix-state`](#matrix-state) proper), `run-state-renderer` (the
double-buffered `cl-tty-kit` repaint helper), `run-state-quitp` (set once a
quit event has been seen), `run-state-input-poller` (a callable that returns
typed `cl-tty-kit:key-event` values), and `run-state-render-context` (the
renderer-local style cache), `run-state-workers` (the configured number of
worker threads), and `run-state-executor` (the optional persistent
`cl-concurrent-kit` executor). `run-state-lockp` records lock mode,
`run-state-screensaverp` makes the first input event quit, `run-state-pausedp`
records pause state, and `run-state-message` stores the optional centered
message. Kept separate from `matrix-state` so that the animation state stays
free of I/O, rendering caches, and executor ownership.

### `run-state-poll`

```lisp
(run-state-poll run-state &key (fd 0) (terminal-size-fn #'terminal-size))
```

Observe the real terminal ahead of `run-state`'s next tick: reflow for the
current terminal size (via `terminal-size-fn`), resize the renderer to
match, poll the injected input-poller, and record whether a quit event has
arrived. Returns `run-state`, mutated in place -- this is the `:poll` half of
the poll/advance split `cl-tty-kit:tick-loop-run-realtime` drives, run once
before every tick's `run-state-advance`.

### `run-state-advance`

```lisp
(run-state-advance run-state)
```

Advance `run-state`'s underlying `matrix-state` by one tick via
[`matrix-advance`](#matrix-advance). Returns `run-state`, mutated in place --
the animation-only half of the poll/advance split; terminal observation is
`run-state-poll`'s job instead. Wide matrices use the executor stored on
`run-state`; `matrix-advance` copies the random state before consuming it, so
caller-owned state is not mutated.

### `run-state-render`

```lisp
(run-state-render run-state)
```

Redraw `run-state`'s renderer back buffer from its current `matrix-state`
and return the diffed ANSI frame string for this tick.

### `quit-key-event-p` / `poll-quit-events` / `poll-quit-events-cps`

```lisp
(quit-key-event-p event)
(poll-quit-events events)
(poll-quit-events-cps events on-quit on-continue)
```

`quit-key-event-p` is true for a pressed CL-TTY-KIT `key-event` carrying
`q`, `Q`, Ctrl-C, or the special `:escape` code. `poll-quit-events` searches
a sequence of typed events and returns true when one is a quit event.

`poll-quit-events-cps` is the continuation-passing implementation: it calls
`on-quit` with the offending event, or `on-continue` with no arguments when
the sequence contains no quit event. The direct wrapper is useful for the
usual boolean policy; the CPS form lets a caller log or dispatch the exact
event without rebuilding the scan.

Together these compose the loop `run-matrix` itself drives: `make-run-state`
builds the initial state around a `matrix-state`, renderer, typed input
poller, and render context. Each tick calls `run-state-poll`, then
`run-state-advance`, then `run-state-render`, and the loop stops once
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
(matrix-advance state &key executor (workers +default-workers+))
```

Advance every column of `state` by one tick, returning a new `matrix-state`.
When `executor` is supplied and the matrix is sufficiently wide, columns are
processed in deterministic chunks through `cl-concurrent-kit:executor-map`;
the returned chunks are restored by column range, not worker completion order.
Without an executor, or for a narrow matrix, the serial path is used. The
transition is deterministic for an already-positioned state: the same state
and tick count always reach the same column state. Each transition consumes a
copy of the stored random state, leaving the input state's random state
untouched.

### `matrix-resize`

```lisp
(matrix-resize state new-width new-height)
```

Return `state` reflowed to `new-width` by `new-height`. Existing columns are
kept exactly; a widened matrix spawns fresh columns from a copy of `state`'s
own random state.

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
`:amber`, `:pink`, `:black`.

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
(matrix-draw screen state context)
```

Draw every column of `state`'s current frame onto a `cl-tty-kit` `screen`.
`context` is a [`render-context`](#render-context) owning the style cache for
that renderer. Reuse one context for a renderer instead of putting cache
data in `matrix-state`.
When `state`'s `color` is `:rainbow`, each column is resolved to a
different real scheme by column index (cycling through
[`list-color-schemes`](#list-color-schemes)) rather than all columns
sharing one.

### `render-context`

```lisp
(make-render-context)
(render-context-style-cache context)
```

Renderer-local memoization for `matrix-draw`. Keeping the cache here makes
animation transitions data-only and lets independent renderers maintain
independent style tables.

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

### `invalid-fps`

Signaled by [`run-matrix`](#run-matrix) when `fps` is not a positive real.
`invalid-fps-fps` reads the offending value back.

### `invalid-update-delay`

Signaled by [`run-matrix`](#run-matrix) when `update-delay` is outside the
integer range 0 through 10. `invalid-update-delay-delay` reads the offending
value back.

### `unknown-color-scheme`

Signaled when `color` names no registered scheme and is not `:rainbow`.
`unknown-color-scheme-name` reads the offending name back.

### `unknown-charset`

Signaled by [`charset-glyphs`](#charset-glyphs) when `name` names no charset
registered in [`list-charsets`](#list-charsets). `unknown-charset-name`
reads the offending name back.
