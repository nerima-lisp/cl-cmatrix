# Getting Started

`cl-cmatrix` targets **SBCL** and depends on four sibling nerima-lisp
libraries: [`cl-tty-kit`](https://github.com/nerima-lisp/cl-tty-kit) for the
terminal session, renderer, and 256-color styling,
[`cl-cli`](https://github.com/nerima-lisp/cl-cli) for argument parsing, and
[`cl-host-kit`](https://github.com/nerima-lisp/cl-host-kit) for process exit,
the working directory, and pathname canonicalization -- in place of calling
ASDF's own bundled UIOP for those directly, plus
[`cl-concurrent-kit`](https://github.com/nerima-lisp/cl-concurrent-kit) for the
persistent worker executor used by wide matrices. The test system
additionally uses [`cl-weave`](https://github.com/nerima-lisp/cl-weave).

## With Nix

```sh
# Run the screensaver directly.
nix run github:nerima-lisp/cl-cmatrix

# Or from a checkout:
nix build .#cl-cmatrix   # build the library
nix run .                # run the delivered binary
nix flake check          # tests + coverage + formatting + docs, the CI gate
nix develop               # SBCL with CL_SOURCE_REGISTRY already set
```

## As a library, without Nix

Put `cl-cmatrix` and all four of its runtime dependencies -- `cl-tty-kit`,
`cl-concurrent-kit`, `cl-cli`, and `cl-host-kit` -- where ASDF can find them
(for example under `~/common-lisp/`), then:

```lisp
(asdf:load-system "cl-cmatrix")

(cl-cmatrix:run-matrix :speed 1.5 :color :cyan)
```

`run-matrix` takes over the terminal (raw mode, alternate screen) until a
quit key is pressed, and always restores it afterward. Pass `:workers` to
size the persistent worker pool, but the same width gate described below
applies: a pool is started only for a matrix at least 2048 columns wide.
`run-matrix`'s `:asyncp` defaults to true, so through the library the width
is the only remaining condition.

## The command line

```sh
cl-cmatrix                     # default green rain at normal speed
cl-cmatrix --speed 2            # fall twice as fast
cl-cmatrix -C cyan               # a different color scheme
cl-cmatrix -C rainbow            # a different scheme per column
cl-cmatrix -c                    # upstream's classic CJK glyphs (U+3000-U+303E)
cl-cmatrix --classic              # the same flag, spelled long (--japanese too)
cl-cmatrix -g katakana           # half-width katakana -- our extension, not -c
cl-cmatrix -m                    # draw every non-head glyph as a lambda
cl-cmatrix -b                    # bold part of the trail
cl-cmatrix -B                    # bold the whole trail, not only the head
cl-cmatrix --random-bold         # vary which trail cells are bold, per frame
cl-cmatrix -u 4                  # upstream delay: 4 x 10ms (the default)
cl-cmatrix --fps 60              # long-form extension: 60 ticks per second
cl-cmatrix -s                    # exit on the first input event
cl-cmatrix -L                    # lock; ignore quit keys and interrupts
cl-cmatrix -M 'hello'            # show a centered message
cl-cmatrix -f                    # force TERM=linux for this invocation
cl-cmatrix -t /dev/tty           # use a specific terminal device
cl-cmatrix -a --workers 8        # eight workers -- see the width gate below
cl-cmatrix --seed 42             # reproducible run
cl-cmatrix --help                # every flag, free from cl-cli
```

Press `q`, `Q`, `Escape`, or Ctrl-C to quit.

`--random-bold` has no short spelling, and it is the lowest-priority bold
option: `-B`, `-b`, and `-n` each suppress it when given alongside.

## `--workers` and the width gate

`--workers` sets the size of a worker pool that most terminals never start.
Two conditions must both hold before any pool exists: asynchronous per-column
timing must be on, and the matrix must be at least **2048 columns wide**. On
the command line asynchronous timing is off unless you pass `-a`, so
`--workers 8` on its own changes nothing at any width; through the library
`run-matrix`'s `:asyncp` is already true, leaving only the width.

2048 columns is not a size a terminal window reaches -- it is several times
wider than a full-screen terminal on a large display. Treat the flag as
reachable in benchmarks and synthetic runs rather than in daily use.
It is always accepted and always validated, and below the threshold the
animation simply advances serially, which is what avoids paying for worker
threads a narrow matrix cannot amortize.

## Glyph sets, and what `-c` actually draws

`-c` (also `--classic`, `--japanese`) selects the **CJK Symbols and
Punctuation** block, U+3000 through U+303E -- 、。〆〇「」【】〒 and the rest
of that range. That is what upstream `cmatrix`'s own `-c` draws, code point
for code point, so a `cl-cmatrix -c` run looks like an upstream `cmatrix -c`
run.

Half-width katakana (U+FF66-U+FF9D) is a **separate set of ours** with no
upstream equivalent, reachable only through `--charset katakana` (`-g
katakana`). It looks considerably more like the film than upstream's `-c`
does -- which is the temptation, and the reason it is kept off `-c`. Binding
the closer-looking set to the upstream-compatible flag would make `-c` quietly
disagree with the program it is compatible with. Pick by what you want:

```sh
cl-cmatrix -c              # what upstream cmatrix -c draws
cl-cmatrix -g katakana     # closer to the film, ours, not upstream-compatible
```

The four `--charset` values are `ascii` (the default, `!` through `z`),
`classic`, `katakana`, and `binary` (`0` and `1`). There is no `lambda`
charset: `-m`/`--lambda` is a *render mode* that substitutes a lambda for
every non-head character at draw time, so it composes with whichever glyph
set is in force rather than replacing it -- `cl-cmatrix -m -g binary` is
lambdas over a binary column, and a stream's head keeps its real character
either way.

## Reproducible runs

Every source of randomness -- fall timing, glyph choice, and column reset --
is routed through an injected `RANDOM-STATE` rather than the global
`*RANDOM-STATE*`. `--seed` does this from the command line; the same
injection is available as a library through `make-matrix-state`'s and
`run-matrix`'s own `:random-state`:

```lisp
(let ((state (cl-cmatrix:make-matrix-state
              80 24 :random-state (sb-ext:seed-random-state 42))))
  (dotimes (tick 100)
    (setf state (cl-cmatrix:matrix-advance state)))
  state)
```

Two calls with the same seed and the same number of ticks produce identical
column state every time -- this is how the test suite pins down exact,
non-visual assertions instead of comparing rendered frames.

See [API Reference](reference/api.md) for `cl-cmatrix:run-matrix`,
`cl-cmatrix:make-matrix-state`, and the rest of the public surface.
