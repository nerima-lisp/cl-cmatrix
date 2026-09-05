# Architecture

## Two packages, one binary

`src/package.lisp` defines two packages. `cl-cmatrix` is the animation
engine: pure state construction, advance, and resize, plus the
[`cl-tty-kit`](https://nerima-lisp.github.io/cl-tty-kit/) rendering and the
real-time driver loop built on top of it. `cl-cmatrix/cli` is a thin
command-line front end over that engine, importing `run-matrix`, the three
registry lookups it needs to turn flags into keyword arguments
(`list-color-schemes`, `list-charsets`, `charset-glyphs`), and the three
default constants it echoes into `--help` (`+default-fps+`,
`+default-update-delay+`, `+default-workers+`).

The split exists so `(asdf:load-system "cl-cmatrix")` stays usable as a
library with no `cl-cli`-flavoured argv parsing along for the ride --
`cl-cowsay` follows the same shape. Neither package `:use`s a sibling
package (`CODING_STANDARD.md`'s "`:use` is `#:cl` only"); every `cl-tty-kit`,
`cl-concurrent-kit`, `cl-cli`, and `host-kit` symbol either package calls is
imported by name, so its origin stays visible at every call site's package
qualification.

| File | Owns |
|---|---|
| `src/package.lisp` | Both `defpackage` forms and every import/export. |
| `src/conditions.lisp` | `cl-cmatrix-error`, its six subclasses, and the macro that defines them. |
| `src/config.lisp` | The upstream-derived tuning constants, the shared defaults, and the wide-matrix parallelization threshold. |
| `src/glyphs.lisp` | The four built-in glyph sets and the `:charset` registry. |
| `src/color-scheme.lisp` | The twelve built-in color schemes and their registry. |
| `src/registry.lisp` | `define-registry-queries`, shared by the two registries above. |
| `src/column.lisp` | `column`: one animated column's cell buffer, plus both scrolling algorithms. |
| `src/state.lisp` | `matrix-state`: the pure, whole-screen struct `t/` tests directly, the serial advance, the async gate, and resize. |
| `src/concurrent.lisp` | Deterministic chunked column advance through a `cl-concurrent-kit` executor. |
| `src/render-context.lisp` | `render-context`: renderer-local style-cache ownership. |
| `src/render.lisp` | `matrix-draw`/`matrix-cell-style`, mapping `matrix-state` onto a `cl-tty-kit` screen. |
| `src/input.lisp` | Typed quit-event predicates and direct/CPS event dispatch. |
| `src/run-state.lisp` | `run-state`: renderer, typed input poller, resize polling, the runtime key bindings, and the tick model. |
| `src/runtime.lisp` | The real-time driver loop, executor lifetime, and `run-matrix` itself. |
| `src/cli-options.lisp` | Declarative `cl-cli` option metadata and registry-derived choices. |
| `src/cli.lisp` | `cl-cmatrix/cli`: flag parsing, `main`, `image-entry-point`. |

## What the engine exports and omits

`src/package.lisp`'s `:export` list is the v1.0.0 compatibility promise: the
six conditions with their readers, the two registries, the three default
constants, `matrix-state` with its width, height and tick readers,
`matrix-advance`, `matrix-resize`, the drawing trio
(`render-context`/`matrix-draw`/`matrix-cell-style`), and `run-matrix`. The
line is drawn at the engine -- build a state, advance it, reflow it, draw it,
which is enough to embed the animation in a caller's own loop -- and not at
the state's internals.

`column`, `run-state`, `src/config.lisp`'s tuning constants and the raw glyph
vectors are not exported. Those are the representations most likely to
move, and exporting a representation freezes the implementation behind it;
glyph sets and color schemes are therefore reached by *name* through the
registries rather than by their constants, so the vectors stay free to
change. A caller that needs an internal anyway can still reach it through
`cl-cmatrix::`, and writing those two colons is how it states that it is
holding something unsupported.

## Why a column is a buffer of cells, not a falling head

`column` (`src/column.lisp`) models a stream the way upstream cmatrix 2.0
does: not as a head position with a trail length behind it, but as a buffer
of `height + 1` independent cells that a scan rewrites in place on every
advance. There is no head row to move. A head is wherever this frame's scan
decided to plant one, recorded in the parallel `heads` bit vector; a stream
appears to fall because the scan writes a fresh character one row past the
bottom of each non-blank run and blanks that run's top row once it has grown
to its full `length`.

Index 0 of the buffer is an off-screen staging row that is never drawn. It
exists so the spawn test has somewhere to hold the "a new stream may start
here" marker, which is literally `cells[0] == :empty and cells[1] == :space`.
That is why `:empty` (upstream's `-1`, "nothing has ever been here") and
`:space` (upstream's `' '`, "a stream passed through and left") are distinct
cell states rather than one blank: collapsing them would not error anywhere,
it would silently arm every column's spawn on the wrong frame.

The same buffer serves both scrolling modes, because upstream keeps one
matrix for both. New style draws internal rows 1..`height`; old style
(`-o`) really does shift the whole buffer down one row and draws internal
rows 0..`height - 1`. `%advance-matrix-column` dispatches on the requested
mode, never on the shape of the data.

One consequence reaches all the way out to the renderer. Because a cell no
longer knows its distance from a head, `src/render.lisp` recovers that at
draw time: it scans for maximal runs of non-blank cells, treats each run's
bottom row as the head end, and uses `bottom - row` as the offset into the
memoized style vector, clamped to that vector's last index since a run may
legitimately outgrow the column's nominal `length`.

## Why there are half as many columns as screen columns

`matrix-state` holds `(ceiling width 2)` columns, not `width` of them.
Upstream scans `for (j = 0; j <= COLS - 1; j += 2)`, animating every other
screen column and leaving the odd ones permanently blank, and that gap is the
single most recognisable thing about how cmatrix looks. Column index `I` is
therefore rendered at screen `x = 2I`, and odd screen columns are never
touched. `matrix-state-column-count` is the one place the conversion lives,
and `t/state-machine-test.lisp` asserts the invariant directly rather than
letting it be re-derived per test.

## Why `matrix-state` and `run-state` are separate structs

`matrix-state` (`src/state.lisp`) holds only what `matrix-advance` needs: the
columns, the screen dimensions, the color scheme name, the glyph set, the
render-mode flags (`bold`, `partial-bold-p`, `no-bold-p`, `old-style-p`,
`lambda-p`, `random-bold-p`, `change-glyphs-p`), the async gate's state
(`asyncp` and the cycling `async-count`), a frame counter, and an injected
`random-state`. Nothing in it touches a terminal or owns renderer caches.

There is **no speed slot**. Pace belongs to the driver loop, not
to the animation state: `run-state` (`src/run-state.lisp`) wraps a
`matrix-state` together with a `cl-tty-kit` renderer, a typed input poller, a
render context, an optional persistent `cl-concurrent-kit` executor, its
worker count, the tick model, and a quit flag -- the I/O, pacing and
parallelism half `run-matrix`'s tick loop needs. `src/runtime.lisp` owns
terminal-session setup, executor selection and lifetime, and realtime
tick-loop composition; `src/concurrent.lisp` owns the deterministic chunk
transition helpers, while `src/input.lisp` owns the quit policy.
`run-matrix` still accepts `:speed` and still signals `invalid-speed` for a
bad one -- it just resolves it into a tick count instead of storing it on the
animation.

Keeping them separate is what lets `t/`'s deterministic tests call
`matrix-advance` directly, seed a `random-state`, and assert on exact
resulting column state, with no renderer, no terminal, and no real time
involved. A single merged struct would force every one of those tests
through a terminal session just to construct it.

## Why pace is a tick count and not a sleep interval

`cl-tty-kit:tick-loop-run-realtime` binds its `:interval` once, before its
loop, so nothing pressed at runtime can change how long it sleeps. Pace
therefore cannot be expressed as an interval. It is expressed as a count
instead: the loop always sleeps `+base-tick-seconds+` (1/100 s, chosen to
equal upstream's own `napms(update * 10)` unit), and `run-state-advance`
moves the matrix only once every `update-ticks` of those base ticks.

That indirection is what buys two things at once. Input polling and
rendering stay responsive at 100 Hz no matter how slow the animation itself
is running, and the runtime `0`-`9` keys can reset the delay mid-run --
upstream's `update = keypress - 48`, where a larger digit is slower -- by
recomputing a tick count rather than by reaching into a loop that will never
re-read its interval. `run-state` keeps `speed` for exactly this reason: a
`0`-`9` press supplies a raw upstream delay that has to be re-scaled by
`--speed` before it becomes a new `update-ticks`.

A column's *stagger* is a separate mechanism from the loop's pace. `-a`
gives each column an `update` threshold drawn from 1..3, while a shared
counter cycles 1..4; a column advances on a frame only when the count
exceeds its own threshold, which is upstream's
`count > updates[j] || asynch == 0`. A column whose threshold is not met is
carried over as the very same object and draws no randomness at all, which
is both what makes the stagger visible and what `t/advance-test.lisp` pins
by object identity.

## Why columns are advanced in chunks

Each tick creates a new `matrix-state`, so the old columns can be advanced
independently. `src/concurrent.lisp` derives deterministic child random
states in chunk order *before* submitting any work, partitions columns into
fixed ranges, and calls `cl-concurrent-kit:executor-map`. Results are copied
back by range rather than by completion order, so worker scheduling cannot
reorder the next state. The async gate is applied identically on both paths,
so serial and parallel runs always agree on *which* columns move on a given
frame -- they disagree only on which random numbers those columns draw, which
is why the parallel path is deterministic without being stream-identical to
the serial one.

`run-matrix` creates at most one executor for a whole run and stores it on
`run-state`, avoiding worker-pool creation on every tick. It is bound only
when the run starts asynchronous *and* the startup width reaches
`+parallel-column-threshold+`; otherwise the slot stays `nil` for the run's
lifetime and every advance takes the serial path, because dispatch overhead
would outweigh the available column work. The binding is made once, outside
the loop, so a matrix that only becomes eligible later -- through a resize,
or through the `a` key -- stays serial for the rest of that run.

## Why `run-matrix`, `main`, and `image-entry-point` are tested out of process

`run-matrix` drives `cl-tty-kit:with-terminal-session` in raw mode, which
signals immediately outside a real terminal rather than silently no-oping
(unlike that session's other features, which degrade gracefully). `main` and
`image-entry-point` (`src/cli.lisp`) both end in `host-kit:quit`, a genuine
process exit that would kill the test runner if called in-process. Both are
therefore exercised for real, but only in a subprocess: `t/cli-test.lisp`'s
`it-isolated` cases invoke `main` and `image-entry-point` in a forked SBCL
image, not the parent test process. See
[Development](../project/development.md#coverage) for what that means for
the measured coverage floor -- a subprocess's execution is genuine, but
invisible to the parent process's own `sb-cover` data.

## Why one macro backs both registries

`+color-schemes+` (`src/color-scheme.lisp`) and `+charsets+`
(`src/glyphs.lisp`) are both a `defparameter` alist of `(keyword . value)`
conses, and both needed the identical pair of lookups: `list-<name>s`
enumerating every registered key, and `<name>-p` testing membership.
`src/registry.lisp`'s `define-registry-queries` is the single declarative
form both now expand into, replacing what used to be hand-written
boilerplate at each call site.

A third lookup shape -- an actual value fetch that signals
[`unknown-color-scheme`](conditions.md#unknown-color-scheme) or
[`unknown-charset`](conditions.md#unknown-charset) when the key is
unregistered -- stays hand-written at each site instead. Its name and
visibility differ too much between the two registries (public
`charset-glyphs` returning the looked-up value directly, versus a private
per-scheme accessor feeding three further generated readers) for folding it
into the shared macro without obscuring the difference.

`:rainbow` is *not* an entry in `+color-schemes+`. It has no RGB
triples of its own and instead means "resolve a real registered scheme per
column", which `matrix-draw` is the only place to do. `color-choice-p`
accepts both a registered name and `:rainbow`, and is the predicate anything
read from `--color` is validated against; `color-scheme-p` is the narrower
one.

## Where this system diverges from upstream

Three divergences are recorded at the site that makes each choice.

The **color model** is ours. Upstream paints a whole stream one color with a
white head; `matrix-cell-style` instead blends the scheme's bright RGB toward
its dark RGB with distance from the head, so a stream fades rather than
stopping flat, and `:rainbow` gives each column its own scheme.

**Resize reflows rather than restarts.** Upstream calls `var_init()` on a
terminal resize, wiping every column back to its initial state.
`matrix-resize` keeps the running animation and only reflows it: surviving
columns are preserved, newly exposed ones are spawned from a copy of the
state's random state, and a height change re-lays each buffer while keeping
the rows that remain visible. A resize that blanks the screen is worse than
one that reflows.

**`-u 0` is capped at one base tick.** Upstream busy-loops there, calling
`napms(0)` and redrawing as fast as the terminal will accept. We floor at a
single base tick, so `-u 0` runs at 100 frames per second. The animation is
indistinguishable at that rate on a real terminal, and the alternative is a
screensaver that pins a core for as long as it is up.

A fourth difference is a bug fix rather than a divergence: upstream never
assigns `is_head` in old-style mode, so its head-rendering branch reads
whatever `malloc` returned. Its own comment says what was intended, so
`%advance-old-style-column` sets the head bit when it plants a head marker
and clears it otherwise.
