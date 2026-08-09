# cl-cmatrix

[![CI](https://github.com/nerima-lisp/cl-cmatrix/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/nerima-lisp/cl-cmatrix/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Documentation](https://img.shields.io/badge/docs-MkDocs%20Material-0a7a5a)](https://nerima-lisp.github.io/cl-cmatrix/)

A Matrix-style digital rain terminal screensaver for SBCL: independently
falling character streams with a bright head and a 256-color dimming trail.
Reflows on terminal resize and quits cleanly on q/Escape/Ctrl-C, always
restoring the terminal's prior state.

The animation follows upstream `cmatrix` 2.0 rather than reinterpreting it.
Streams animate every other screen column and leave the odd ones blank, a
column is a buffer of cells a scan rewrites in place rather than a head
dragging a trail, the default glyphs are upstream's own `!` through `z`
(U+0021-U+007A), and `-c` draws the CJK Symbols and Punctuation block
(U+3000-U+303E) that upstream's `-c` draws.

The color gradient is the deliberate departure, and the one place this
project does not follow upstream: every trail is a 256-color fade from a
white head through a named scheme's bright color down to the background,
with `rainbow` for a different scheme per column. Half-width katakana
(`--charset katakana`) and a 0/1 set (`--charset binary`) are extensions of
ours with no upstream equivalent -- katakana looks closer to the film than
upstream's own `-c`, which is exactly why it is not what `-c` selects here.
Run `cl-cmatrix --help` for the current color and charset choices.

Full documentation is published at <https://nerima-lisp.github.io/cl-cmatrix/>.
The source for that site lives in [docs/src/](docs/src/).

## Quick Start

```sh
cl-cmatrix                      # default green rain at normal speed
cl-cmatrix --speed 2 -C cyan
cl-cmatrix -C rainbow -c        # rainbow trails, upstream's classic CJK glyphs
cl-cmatrix -g katakana -B       # half-width katakana (our extension), bold trail
cl-cmatrix --seed 42            # reproducible run
```

Or as a library:

```lisp
(asdf:load-system "cl-cmatrix")

(cl-cmatrix:run-matrix :speed 1.5 :color :cyan)
```

Pass `:workers` to size the persistent `cl-concurrent-kit` worker pool. It is
started only for a matrix at least **2048 columns wide**; anything narrower
advances serially rather than pay for worker threads it cannot amortize. No
terminal window is that wide, so `--workers` on the command line is for
benchmarks and synthetic runs -- and there it also needs `-a`, since
asynchronous timing is off by default on the CLI while `run-matrix`'s
`:asyncp` defaults to true.

## Install

As a command, from a checkout:

```sh
nix build              # -> ./result/bin/cl-cmatrix
./result/bin/cl-cmatrix --speed 2 -C cyan
```

Or without cloning: `nix run github:nerima-lisp/cl-cmatrix`.

As a library, from another flake:

```nix
# flake.nix
inputs.cl-cmatrix = {
  url = "github:nerima-lisp/cl-cmatrix/v1.0.0";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

Note the pinned tag. Consumers inside this org must pin a release tag rather
than follow the default branch. On a `lispDependencies` edge, read
`cl-cmatrix.packages.<system>.cl-cmatrix` -- `packages.default` is the
delivered binary, not the ASDF system.

## Documentation

- [Getting started](https://nerima-lisp.github.io/cl-cmatrix/getting-started/)
- [API reference](https://nerima-lisp.github.io/cl-cmatrix/reference/api/)
- [Conditions](https://nerima-lisp.github.io/cl-cmatrix/reference/conditions/)
- [Architecture](https://nerima-lisp.github.io/cl-cmatrix/reference/architecture/)
- [Compatibility](https://nerima-lisp.github.io/cl-cmatrix/reference/compatibility/)
- [Development](https://nerima-lisp.github.io/cl-cmatrix/project/development/)

## Development

```sh
nix develop          # SBCL with CL_SOURCE_REGISTRY already set
nix build            # -> ./result/bin/cl-cmatrix
nix run .#test       # run the test suite
nix flake check      # tests + coverage + formatting + docs, the CI gate
nix fmt              # format Nix sources (treefmt)
```

For informational performance measurements, see the
[development benchmark instructions](https://nerima-lisp.github.io/cl-cmatrix/project/development/#informational-benchmarks).
The benchmark writes tab-separated results and does not enforce a performance
threshold.

Tests live in `t/` and run under [cl-weave](https://github.com/nerima-lisp/cl-weave),
the org's test framework. Fall timing, glyph choice, and reset are all routed
through an injectable `RANDOM-STATE`, so the deterministic tests pin exact
output from a fixed seed rather than asserting on visual output. Parametrized
cases use cl-weave's `it-each` table-test macro rather than a hand-rolled
loop over `expect`, so each input gets its own named pass/fail instead of one
aggregate result; shared setup uses `before-each` fixtures over a dynamic
variable rather than copy-pasted `let` bindings.

`t/pty-e2e.exp` sits alongside them but is not part of that suite. It drives
the built binary through a real pseudo-terminal to check alternate-screen and
terminal-state restoration, which an in-process test cannot observe, so it
needs `expect` and a prior `nix build` and stays a manual gate rather than
part of `nix flake check`.

## Contributing

See the org-wide [CONTRIBUTING](https://github.com/nerima-lisp/.github/blob/main/CONTRIBUTING.md)
guide and the [package standard](https://github.com/nerima-lisp/.github/blob/main/PACKAGE_STANDARD.md).

## Support

See [SUPPORT](https://github.com/nerima-lisp/.github/blob/main/SUPPORT.md).

## License

MIT. See [LICENSE](LICENSE).
