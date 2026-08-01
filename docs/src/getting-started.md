# Getting Started

`cl-cmatrix` targets **SBCL** and depends on two sibling nerima-lisp
libraries: [`cl-tty-kit`](https://github.com/nerima-lisp/cl-tty-kit) for the
terminal session, renderer, and 256-color styling, and
[`cl-cli`](https://github.com/nerima-lisp/cl-cli) for argument parsing. The
test system additionally uses
[`cl-weave`](https://github.com/nerima-lisp/cl-weave).

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

Put `cl-cmatrix`, `cl-tty-kit`, and `cl-cli` where ASDF can find them (for
example under `~/common-lisp/`), then:

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
cl-cmatrix --help                # every flag, free from cl-cli
```

Press `q`, `Q`, `Escape`, or Ctrl-C to quit.

## Reproducible runs

Every source of randomness -- fall timing, glyph choice, and column reset --
is routed through an injected `RANDOM-STATE` rather than the global
`*RANDOM-STATE*`:

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
