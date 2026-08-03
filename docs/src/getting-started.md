# Getting Started

`cl-cmatrix` targets **SBCL** and depends on three sibling nerima-lisp
libraries: [`cl-tty-kit`](https://github.com/nerima-lisp/cl-tty-kit) for the
terminal session, renderer, and 256-color styling,
[`cl-cli`](https://github.com/nerima-lisp/cl-cli) for argument parsing, and
[`cl-host-kit`](https://github.com/nerima-lisp/cl-host-kit) for process exit,
the working directory, and pathname canonicalization -- in place of calling
ASDF's own bundled UIOP for those directly. The test system additionally
uses [`cl-weave`](https://github.com/nerima-lisp/cl-weave).

## With Nix

```sh
# Run the screensaver directly.
nix run github:nerima-lisp/cl-cmatrix

# Or from a checkout:
nix build .#cl-cmatrix   # build the library
nix run .                # run the delivered binary
nix flake check          # tests + formatting + docs, the same gate CI uses
nix develop               # SBCL with CL_SOURCE_REGISTRY already set
```

## As a library, without Nix

Put `cl-cmatrix`, `cl-tty-kit`, `cl-cli`, and `cl-host-kit` where ASDF can
find them (for example under `~/common-lisp/`), then:

```lisp
(asdf:load-system "cl-cmatrix")

(cl-cmatrix:run-matrix :speed 1.5 :color :cyan)
```

`run-matrix` takes over the terminal (raw mode, alternate screen) until a
quit key is pressed, and always restores it afterward.

## The command line

```sh
cl-cmatrix                     # default green rain at normal speed
cl-cmatrix --speed 2            # fall twice as fast
cl-cmatrix -c cyan               # a different color scheme
cl-cmatrix -c rainbow            # a different scheme per column
cl-cmatrix -g katakana           # half-width katakana glyphs instead of ASCII
cl-cmatrix -b                    # bold the whole trail, not only the head
cl-cmatrix -u 60                 # 60 ticks per second instead of 30
cl-cmatrix --seed 42             # reproducible run
cl-cmatrix --help                # every flag, free from cl-cli
```

Press `q`, `Q`, `Escape`, or Ctrl-C to quit.

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
