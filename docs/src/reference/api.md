# API Reference

Everything below is exported from the `cl-cmatrix` package, and everything
exported from `cl-cmatrix` is below. The command-line front end lives in the
separate `cl-cmatrix/cli` package (`make-cmatrix-app`, `main`,
`image-entry-point`) and is documented by `cl-cmatrix --help`.

The line is drawn at the **engine**: build a state, advance it, reflow it,
draw it -- enough to embed the animation in a caller's own loop -- but not at
the state's internals. Glyph sets and color schemes are reached by *name*
through the registries rather than through the vectors behind them.

## Stability promise

From v1.0.0 onward, every symbol on this page is a compatibility promise.
Removing one, or changing what it accepts or returns, requires a major version
bump. The authoritative list is the `(:export ...)` block in
`src/package.lisp`; to enumerate it from a running image:

```lisp
(let ((names '()))
  (do-external-symbols (symbol (find-package "CL-CMATRIX") (sort names #'string<))
    (push (symbol-name symbol) names)))
```

Nothing else is covered. `column`, `run-state` and its poll/advance/render
helpers, `matrix-state`'s internal slots, `render-context`'s cache accessor,
the tuning constants, the raw glyph vectors, and the `color-scheme-*-rgb`
readers are all internal, and may change in any release -- they are the
representations most likely to move, and freezing a representation freezes the
implementation behind it.

A caller can still reach any of them by writing `cl-cmatrix::` instead of
`cl-cmatrix:`. Those two colons are the declaration that it is holding
something unsupported: no deprecation cycle, no changelog entry, and no
guarantee the symbol exists in the next release.

## Running the animation

### `run-matrix`

```lisp
(run-matrix &key (speed 1) (color :green) (glyphs (charset-glyphs :ascii)) (bold nil)
                 (partial-bold-p nil) (no-bold-p nil)
                 (old-style-p nil) (lambda-p nil) (asyncp t)
                 (random-bold-p nil) (change-glyphs-p nil)
                 (screensaverp nil) (lockp nil) message
                 (stream *standard-output*)
                 (input-stream *standard-input*) (fd 0)
                 (fps +default-fps+) update-delay
                 (workers +default-workers+)
                 (random-state (make-random-state t)))
```

Run the full-screen animation on `stream` until a quit event (`q`, `Q`,
`Escape`, or Ctrl-C) arrives from `input-stream`. The stream is adapted once
to CL-TTY-KIT's typed input poller; callers do not parse raw characters.
Enters raw mode and the terminal's alternate screen for the duration, hides
the cursor, and always restores all three -- including after a condition or an
interrupt. Returns the final [`matrix-state`](#matrix-state).

`color`, `glyphs`, `bold`, `partial-bold-p`, `no-bold-p`, `old-style-p`,
`lambda-p`, `asyncp`, `random-bold-p`, and `change-glyphs-p` are as in
[`make-matrix-state`](#make-matrix-state).

**Pace.** The loop itself always ticks at a fixed base period of 1/100 second,
polling input and rendering at that rate; the animation *advances* once every
so many of those ticks. `update-delay` is upstream's 10-millisecond delay unit
(an integer 0 through 10) and, when non-NIL, takes precedence over `fps`.
`speed` divides the delay, so `2` runs twice as fast -- it is this project's
own extension, not upstream's. Otherwise `fps` is converted to the nearest
whole number of base ticks per frame. The runtime `0`-`9` keys reset the delay
the same way upstream's `update = keypress - 48` does, where a larger digit is
slower.

`-u 0` is capped at one base tick per advance rather than busy-looping as
upstream does. This is a deliberate deviation: the animation is
indistinguishable at 100 frames per second on a real terminal, and the
alternative pins a core for as long as the screensaver is up.

**`speed` scales the delay and nothing else.** When `update-delay` is NIL and
`fps` is therefore in charge, the starting pace is `fps` alone: `speed` is
still validated -- a bad value still signals
[`invalid-speed`](#invalid-speed) -- but a good one has no effect on it. It
comes back the moment a runtime `0`-`9` key is pressed, because that key puts
the delay path back in charge and `speed` divides the delay from then on.

On the command line the two are mutually exclusive by construction: passing
`--fps` suppresses `--update-delay` entirely, so **`cl-cmatrix --speed 2 --fps
60` runs at 60 and silently ignores the `2`** until a digit key is pressed.
Combine `--speed` with `-u`, not with `--fps`.

**Concurrency.** `workers` sizes a persistent `cl-concurrent-kit` executor,
created once per invocation rather than once per tick. It is only started for
an asynchronous run whose matrix is wide enough to amortize it; narrow or
synchronous matrices stay on the serial transition path and start no threads.

**Other arguments.** `screensaverp` makes any key exit after the first frame.
`lockp` starts in lock mode, where quit keys and interactive interrupts are
ignored. A non-NIL `message` is drawn centered over the animation. `fd` is the
file descriptor consulted for terminal size and input polling. `random-state`
seeds the glyph and timing randomness; supply a fixed seed for a reproducible
run.

**Conditions.** Signals [`invalid-speed`](#invalid-speed) when `speed` is not
a positive real, [`invalid-fps`](#invalid-fps) when `fps` is not a positive
real, and [`invalid-update-delay`](#invalid-update-delay) when `update-delay`
is not an integer in 0 through 10. All three are checked before any terminal
setup begins.

## Building a custom driver loop

`run-matrix` bundles terminal setup, a real-time tick loop, and quit-key
handling around a [`matrix-state`](#matrix-state). A caller wanting different
I/O -- a custom event loop, a non-terminal renderer, its own quit-key policy --
composes the engine directly instead. The three pieces are a state, a
`cl-tty-kit` renderer, and a [`render-context`](#render-context):

```lisp
(let* ((state (cl-cmatrix:make-matrix-state 80 24
                                            :color :green
                                            :glyphs (cl-cmatrix:charset-glyphs :katakana)
                                            :random-state (sb-ext:seed-random-state 42)))
       (renderer (cl-tty-kit:make-renderer 80 24))
       (context (cl-cmatrix:make-render-context)))
  (dotimes (tick 60)
    (setf state (cl-cmatrix:matrix-advance state))
    (cl-tty-kit:renderer-clear renderer)
    (cl-cmatrix:matrix-draw (cl-tty-kit:renderer-screen renderer) state context)
    ;; The diffed ANSI frame for this tick; write it wherever you like.
    (cl-tty-kit:renderer-render renderer))
  (cl-cmatrix:matrix-state-tick state))
;; => 60
```

Reuse one `render-context` for the lifetime of a renderer rather than making
one per frame; that is what its style cache is for. Call
[`matrix-resize`](#matrix-resize) and `cl-tty-kit:renderer-resize` together
when the output surface changes size.

## Building and advancing state

### `matrix-state`

The animation's state at one frame: an immutable-by-convention value that
[`matrix-advance`](#matrix-advance) and [`matrix-resize`](#matrix-resize)
return new copies of rather than mutating.

Public readers are `matrix-state-width`, `matrix-state-height`, and
`matrix-state-tick` (the number of advances since construction). Every other
slot -- the column vector, the random state, the color and glyph selections,
and the render-mode flags -- is internal.

Width is a count of *screen* cells, not of falling streams. Upstream cmatrix
scans `for (j = 0; j <= COLS - 1; j += 2)`, animating every other screen
column and leaving the odd ones permanently blank, so a state of width `w`
holds `(ceiling w 2)` streams and draws stream `i` at screen x = `2i`. That
gap is the single most recognisable thing about how cmatrix looks.

### `make-matrix-state`

```lisp
(make-matrix-state width height &key (color :green) (glyphs (charset-glyphs :ascii))
                                     (bold nil) (partial-bold-p nil)
                                     (no-bold-p nil) (old-style-p nil)
                                     (lambda-p nil) (asyncp t)
                                     (random-bold-p nil) (change-glyphs-p nil)
                                     (random-state (make-random-state t)))
```

Create a `matrix-state` covering `width` by `height` screen cells.

- `color` names one of [`list-color-schemes`](#list-color-schemes), or
  `:rainbow` to draw each stream from a different scheme (see
  [`matrix-draw`](#matrix-draw)).
- `glyphs` is the non-empty `simple-vector` of characters streams draw from.
  Use [`charset-glyphs`](#charset-glyphs) for the built-in sets, or pass any
  vector of your own. Anything else -- an empty vector, a vector holding a
  non-character, a string, an adjustable vector, or the charset *name* where
  the vector belongs -- signals [`invalid-glyphs`](#invalid-glyphs) at
  construction.

  The default above is written `(charset-glyphs :ascii)` rather than as the
  constant the lambda list actually names. The two are the same object, and
  the spelling shown is the one a caller can write: the constant behind it is
  internal, so naming it here would document a default that cannot be typed
  (see [Stability promise](#stability-promise)).
- `bold` renders every lit row bold; `partial-bold-p` selects upstream's
  character-parity subset instead; `no-bold-p` disables bold styling entirely.
- `old-style-p` selects upstream's old-style scrolling. `lambda-p` is
  upstream's `-m`: a render mode that draws every non-head character as a
  lambda. It is a *mode*, not a character set -- the head always shows its
  real glyph.
- `asyncp`, when false, advances every stream on every frame; when true,
  each stream waits for its own threshold in a shared 1..4 counter cycle,
  which is what makes the fall look ragged.
- `random-bold-p` varies the bold cells deterministically from the tick, and
  `change-glyphs-p` repaints every character cell whenever a stream advances.
- `random-state` is an actual CL random-state object. It is **copied**, so
  constructing a state never mutates caller-owned randomness. Inject one built
  by `sb-ext:seed-random-state` for a reproducible run; the default is a
  nondeterministic one.

Signals [`invalid-dimensions`](#invalid-dimensions) when `width` or `height`
is not a positive integer, [`unknown-color-scheme`](#unknown-color-scheme)
when `color` is neither a registered scheme nor `:rainbow`, and
[`invalid-glyphs`](#invalid-glyphs) when `glyphs` is not a non-empty
`simple-vector` of characters. All three are checked before a single stream is
spawned, so a rejected call allocates nothing.

### `matrix-advance`

```lisp
(matrix-advance state &key executor (workers +default-workers+))
```

Advance `state` by one frame, returning a new `matrix-state`. Each transition
consumes a *copy* of the stored random state, so the input state and its
random-state object are left untouched.

The serial path is pure and reproducible: the same state advanced the same
number of times always reaches the same result. When `executor` is supplied
**and** the matrix is wide enough to be worth it, columns are processed in
deterministic chunks through `cl-concurrent-kit:executor-map`, restored by
column range rather than by worker completion order. Otherwise the serial
path runs.

The parallel path is deterministic but **not stream-identical** to the serial
path: each chunk draws from its own child random state, seeded in chunk order
before any work is submitted. Both paths agree on *which* streams move on a
given frame; they disagree on which random numbers those streams draw. Do not
compare output across the two paths.

`workers` must be a positive integer.

### `matrix-resize`

```lisp
(matrix-resize state new-width new-height)
```

Return `state` reflowed to `new-width` by `new-height` screen cells. A height
change reflows every stream's buffer, preserving the rows that remain visible
-- deliberately not upstream's full re-initialisation. A width change keeps
the surviving streams exactly as they were, spawns fresh ones for newly
exposed columns from a copy of `state`'s own random state, and drops the
rightmost ones when narrowing. A resize mid-run is therefore exactly as
reproducible as everything else.

Signals [`invalid-dimensions`](#invalid-dimensions) when `new-width` or
`new-height` is not a positive integer.

## Rendering

### `render-context`

```lisp
(make-render-context)
```

Renderer-local memoization for [`matrix-draw`](#matrix-draw). The style cache
depends only on drawing configuration and trail length, so it lives here
instead of being copied through every state transition -- which keeps
transitions data-only and lets independent renderers keep independent style
tables. Construct one per renderer and reuse it. The cache accessor itself is
internal.

### `matrix-draw`

```lisp
(matrix-draw screen state context)
```

Draw `state`'s current frame onto a `cl-tty-kit` screen. Stream index `i` is
drawn at screen x = `2i`; odd screen columns are never touched. All per-cell
writes happen inside one `cl-tty-kit:with-screen-batch`, so a full frame
coalesces into a single dirty-tracking generation.

When `state`'s color is `:rainbow`, each stream is resolved to a different
real scheme by index, cycling through
[`list-color-schemes`](#list-color-schemes) in its own order, so adjacent
streams fall in visibly different colors.

### `matrix-cell-style`

```lisp
(matrix-cell-style color offset trail-length &optional bold no-bold)
```

The `cl-tty-kit` style for a cell `offset` rows behind its stream's head
(`0` is the head itself) out of `trail-length` graded rows, under the named
scheme `color` -- a real registered scheme, never `:rainbow`.

The head is drawn bold in the scheme's head RGB unless `no-bold` is true.
Every other row blends the scheme's bright RGB toward its dark RGB by
`offset / (trail-length - 1)`, mapped to the nearest xterm 256-color index via
`cl-tty-kit:rgb-to-256`; `bold` renders those trail rows bold too, again
unless `no-bold` overrides it.

This graded fade is the one place cl-cmatrix diverges from upstream on
purpose: upstream colors a whole stream flat and whitens only its head.

## Registries

Glyph sets and color schemes are addressed by name so that the data behind
them stays free to change.

### `list-color-schemes`

```lisp
(list-color-schemes)
```

Every registered scheme name: `:green` (the default), `:cyan`, `:red`,
`:blue`, `:magenta`, `:yellow`, `:white`, `:purple`, `:orange`, `:amber`,
`:pink`, `:black`. Call it rather than transcribing the list; it is the
registry itself. Every scheme uses a bright white head and fades toward black;
`:black` keeps the white head with a fully black trail.

### `color-scheme-p`

```lisp
(color-scheme-p name)
```

True when `name` is a registered color scheme. It does **not** accept
`:rainbow`.

### `color-choice-p`

```lisp
(color-choice-p name)
```

True when `name` is a valid `:color` value: a registered scheme name, or
`:rainbow`. Use this, not [`color-scheme-p`](#color-scheme-p), to validate
anything destined for [`make-matrix-state`](#make-matrix-state) or the
`--color` flag.

### `list-charsets`

```lisp
(list-charsets)
```

Every registered charset name: `:ascii` (the default), `:classic`,
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

Return the glyph `simple-vector` `name` names -- the supported way to obtain a
built-in glyph set for [`make-matrix-state`](#make-matrix-state)'s `:glyphs`.

| Name | Glyphs | Origin |
| --- | --- | --- |
| `:ascii` | U+0021 through U+007A, `!` through `z` | Upstream's default draw, `rand() % 90 + 33`. Deliberately stops short of `{`, `\|`, `}` and `~`. |
| `:classic` | U+3000 through U+303E, CJK Symbols and Punctuation | What upstream's `-c` selects, reproduced by code point. |
| `:katakana` | U+FF66 through U+FF9D, half-width katakana | Ours, not upstream's. The closest a Unicode terminal font gets to the film's look. |
| `:binary` | `0` and `1` | Ours; upstream has no equivalent. |

Signals [`unknown-charset`](#unknown-charset) when `name` is not registered.

**The result is shared, and must not be modified.** `charset-glyphs` returns
the registry's own vector rather than a copy, so two calls with the same
`name` return `eq` vectors. Destructively modifying one --
`(setf (aref (charset-glyphs :binary) 0) #\x)` -- corrupts that charset for
every later caller in the process, permanently: nothing rebuilds the registry
after load, so the damage outlives the call, the state, and the animation.

Copying on every call was considered and rejected. The expected use is to pass
the result straight to [`make-matrix-state`](#make-matrix-state)'s `glyphs`,
which stores the vector and only ever reads it; charging that path an
allocation proportional to the glyph set, on every call, to defend against a
mutation no correct caller performs is the wrong trade. If you want a vector
you may modify, ask for one: `(copy-seq (charset-glyphs :binary))`.

## Defaults

The values `run-matrix` itself uses, exported so a caller can reproduce or
adjust them without hard-coding the numbers.

### `+default-fps+`

`run-matrix`'s default tick rate: 30 ticks per second.

### `+default-update-delay+`

The upstream-compatible default update delay: 4 units of 10 milliseconds.
This is the default the CLI's `-u` applies; `run-matrix`'s own `update-delay`
argument defaults to NIL, which leaves `fps` in charge.

### `+default-workers+`

`run-matrix`'s default worker-pool size: 4.

## Conditions

Every condition `cl-cmatrix` signals derives from `cl-cmatrix-error`, so one
`handler-case` clause catches them all. See [Conditions](conditions.md) for
the full hierarchy; the exhaustive symbol list follows.

### `cl-cmatrix-error`

Base condition for every error `cl-cmatrix` signals.

### `invalid-dimensions`

Signaled when a width or height is not a positive integer.
`invalid-dimensions-width` and `invalid-dimensions-height` read the offending
values back.

### `invalid-glyphs`

Signaled by [`make-matrix-state`](#make-matrix-state) when `glyphs` is not a
non-empty `simple-vector` of characters. `invalid-glyphs-glyphs` reads the
offending value back. A vector from
[`charset-glyphs`](#charset-glyphs) always satisfies the contract.

### `invalid-speed`

Signaled by [`run-matrix`](#run-matrix) when `speed` is not a positive real.
`invalid-speed-speed` reads the offending value back.

### `invalid-fps`

Signaled by [`run-matrix`](#run-matrix) when `fps` is not a positive real.
`invalid-fps-fps` reads the offending value back.

### `invalid-update-delay`

Signaled by [`run-matrix`](#run-matrix) when `update-delay` is outside the
inclusive integer range 0 through 10. `invalid-update-delay-delay` reads the
offending value back.

### `unknown-color-scheme`

Signaled when a color names no registered scheme and is not `:rainbow`.
`unknown-color-scheme-name` reads the offending name back.

### `unknown-charset`

Signaled by [`charset-glyphs`](#charset-glyphs) when `name` names no charset
registered in [`list-charsets`](#list-charsets). `unknown-charset-name` reads
the offending name back.

## Migrating from 0.2.0

There is no 0.3.0. No such tag was ever cut, so 1.0.0 follows 0.2.0 directly.
Everything below was checked against the tag itself; to check any of it
independently, read the 0.2.0 source rather than this page:

```sh
git show v0.2.0:src/cli.lisp
git show v0.2.0:src/package.lisp
```

**1. Four short options kept their spelling and changed their meaning.**
Read this first. It is the only class of change here that a 0.2.0 command
line survives: the flag still parses, nothing warns, and the animation does
something else.

| Short | v0.2.0 | v1.0.0 |
| --- | --- | --- |
| `-s` | `--speed`, a float multiplier | `--screensaver`, a flag |
| `-c` | `--color`, a value | `--japanese`, a flag selecting the classic CJK glyph set |
| `-u` | `--fps`, an integer 1 through 240 | `--update-delay`, an integer 0 through 10 |
| `-b` | bold the whole trail | bold a subset of the trail; `-B` is now the whole trail |

What the old spellings do now:

```sh
cl-cmatrix -s 2       # was: speed 2. Now: a flag, so it reads no value and starts screensaver mode.
cl-cmatrix -c green   # was: the green scheme. Now: a flag, so green is not read as a color.
cl-cmatrix -u 60      # was: 60 ticks per second. Now: rejected, -u only accepts 0 through 10.
cl-cmatrix -b         # was: the whole trail bold. Now: only a subset of it.
```

What to write instead. Every long name from 0.2.0 still exists, and every one
except `--bold` still means what it did -- only the letters moved -- so the
long form is the safe rewrite:

```sh
cl-cmatrix --speed 2      # --speed has no short form at all in 1.0.0
cl-cmatrix -C green       # or --color green, unchanged since 0.2.0
cl-cmatrix --fps 60       # or pick an upstream delay instead: -u 4
cl-cmatrix -B             # or --all-bold
```

**2. The public API shrank.** 0.2.0 exported the columns, the driver's own
state machine, `matrix-state`'s representation slots, the raw glyph vectors,
and the color scheme's RGB triples. 1.0.0 exports none of them, and the
distinction that matters to a port is *how* each one went away.

**Un-exported, but still there.** Each of these still resolves under
`cl-cmatrix::`, with the caveat in
[Stability promise](#stability-promise) -- no deprecation cycle and no
guarantee it survives the next release, but a working escape hatch today:

```
+binary-glyphs+           +default-glyphs+          +katakana-glyphs+
color-scheme-bright-rgb   color-scheme-dark-rgb     color-scheme-head-rgb
column                    column-length             make-run-state
matrix-state-bold         matrix-state-color        matrix-state-columns
matrix-state-glyphs       matrix-state-random-state random-glyph
run-state                 run-state-advance         run-state-matrix
run-state-poll            run-state-quitp           run-state-render
run-state-renderer
```

**Gone entirely.** Adding two colons will *not* reach these -- the symbol
does not exist in 1.0.0 at all, so a port has to be rewritten rather than
re-qualified:

```
column-counter            column-glyph-at-row       column-glyphs
column-head               column-interval           column-row-lit-p
matrix-state-speed        poll-quit-key             poll-quit-key-cps
quit-key-character-p      run-state-input-stream
```

The six `column-*` readers went when the column representation did: a column
now holds parallel cell and head buffers indexed by internal row, which no
per-column reader in 0.2.0's vocabulary describes. `matrix-state-speed` went
with `:speed` (item 4). The three quit-key helpers and `run-state-input-stream`
went together when input moved to CL-TTY-KIT's typed poller: a run-state now
holds a poller rather than a stream, and the poller delivers key *events*
rather than characters. The internal successor to the quit-key predicates is
`cl-cmatrix::quit-key-event-p`.

Two removals have a supported replacement rather than merely a double-colon
one: reach a glyph vector through [`charset-glyphs`](#charset-glyphs), and
drive your own loop with the recipe in
[Building a custom driver loop](#building-a-custom-driver-loop) instead of
with the `run-state` helpers.

The additions are the two new pace defaults `+default-update-delay+` and
`+default-workers+` (see [Defaults](#defaults)), the two new pace conditions
[`invalid-fps`](#invalid-fps) and
[`invalid-update-delay`](#invalid-update-delay) with their readers,
[`invalid-glyphs`](#invalid-glyphs) with its reader, and
[`render-context`](#render-context) with its `make-render-context`
constructor. `invalid-glyphs` can only narrow what a working 0.2.0 call is
allowed to pass: a `glyphs` argument it rejects is one that already failed,
later and less legibly, in 0.2.0. Nothing in 0.2.0 can have been holding a `render-context`:
0.2.0 had no such type, and the style cache it now owns lived on
`matrix-state` there.

**3. Glyph sets are reached by name.** Code that named a constant should name
a charset instead. The vectors behind `:ascii`, `:katakana` and `:binary` are
byte-for-byte what 0.2.0's constants held.

| v0.2.0 | v1.0.0 |
| --- | --- |
| `+default-glyphs+` | `(charset-glyphs :ascii)` |
| `+katakana-glyphs+` | `(charset-glyphs :katakana)` |
| `+binary-glyphs+` | `(charset-glyphs :binary)` |

`:classic` -- the CJK Symbols and Punctuation block upstream's `-c` draws --
is new in 1.0.0. 0.2.0 had no equivalent, so nothing migrates to it.

**4. `make-matrix-state` no longer accepts `:speed`.** In 0.2.0 it took a
`:speed` multiplier, stored it on the state, and signalled `invalid-speed`
itself. Fall speed turned out not to be a per-state property: the driver loop
owns pace. Drop the argument from direct `make-matrix-state` calls;
[`run-matrix`](#run-matrix) still takes `:speed`, as the divisor of the
update delay, and is now the only place `invalid-speed` is signalled from.
`matrix-state-speed` went with it (see item 2).

**5. What did *not* change, despite looking like it should have.** These
resemble the moves above closely enough to invite a rewrite that would break
a working command line or a working call:

- Half-width katakana is spelled exactly as it was in 0.2.0 --
  `--charset katakana`, or `-g katakana` -- and still covers U+FF66 through
  U+FF9D. It did not move to `-c`, and there is nothing to migrate.
- `-g`, `-b`, `--seed`, `--color`, `--speed` and `--fps` are all still
  accepted spellings. Only what `-b` selects, and which letters `--color`,
  `--speed` and `--fps` answer to, changed.
- Every condition 0.2.0 exported is still exported under the same name,
  including [`invalid-speed`](#invalid-speed).
- [`charset-glyphs`](#charset-glyphs), [`list-charsets`](#list-charsets),
  [`charset-p`](#charset-p), [`matrix-advance`](#matrix-advance),
  [`matrix-resize`](#matrix-resize), [`matrix-draw`](#matrix-draw),
  [`matrix-cell-style`](#matrix-cell-style) and
  [`run-matrix`](#run-matrix) kept their names.
- `-m` is new in 1.0.0, not a changed flag: 0.2.0 had no `-m` and no lambda
  glyph set. It is a render *mode* over whichever glyph set is in force,
  which is why it is not a `--charset` value -- heads keep their real glyphs,
  and a glyph set could not express that.
