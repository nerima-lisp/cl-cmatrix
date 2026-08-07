# cl-cmatrix

[![CI](https://github.com/nerima-lisp/cl-cmatrix/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/nerima-lisp/cl-cmatrix/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Documentation](https://img.shields.io/badge/docs-MkDocs%20Material-0a7a5a)](https://nerima-lisp.github.io/cl-cmatrix/)

A Matrix-style digital rain terminal screensaver for SBCL: one independently
falling character stream per terminal column, each with a bright head and a
256-color dimming trail. Reflows on terminal resize and quits cleanly on
q/Escape/Ctrl-C, always restoring the terminal's prior state. The default
glyph set is plain printable ASCII, not a port of the classic `cmatrix`'s
proprietary katakana bitmap font -- though a Unicode half-width katakana
glyph set is available via `--charset katakana` for a closer look, alongside
`--charset binary` and eleven color schemes, plus `rainbow` for a
different scheme per column.

Full documentation is published at <https://nerima-lisp.github.io/cl-cmatrix/>.
The source for that site lives in [docs/src/](docs/src/).

## Quick Start

```sh
cl-cmatrix                  # default green rain at normal speed
cl-cmatrix --speed 2 -c cyan
cl-cmatrix -c rainbow -g katakana -b   # rainbow katakana, bold trail
cl-cmatrix --seed 42                    # reproducible run
```

Or as a library:

```lisp
(asdf:load-system "cl-cmatrix")

(cl-cmatrix:run-matrix :speed 1.5 :color :cyan)
```

## Install

As a command, from a checkout:

```sh
nix build              # -> ./result/bin/cl-cmatrix
./result/bin/cl-cmatrix --speed 2 -c cyan
```

Or without cloning: `nix run github:nerima-lisp/cl-cmatrix`.

As a library, from another flake:

```nix
# flake.nix
inputs.cl-cmatrix = {
  url = "github:nerima-lisp/cl-cmatrix/v0.3.0";
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

## Development

```sh
nix develop          # SBCL with CL_SOURCE_REGISTRY already set
nix build            # -> ./result/bin/cl-cmatrix
nix run .#test       # run the test suite
nix flake check      # tests + formatting + docs, the same gate CI uses
nix fmt              # format Nix sources (treefmt)
```

Tests live in `t/` and run under [cl-weave](https://github.com/nerima-lisp/cl-weave),
the org's test framework. Fall timing, glyph choice, and reset are all routed
through an injectable `RANDOM-STATE`, so the deterministic tests pin exact
output from a fixed seed rather than asserting on visual output. Parametrized
cases use cl-weave's `it-each` table-test macro rather than a hand-rolled
loop over `expect`, so each input gets its own named pass/fail instead of one
aggregate result; shared setup uses `before-each` fixtures over a dynamic
variable rather than copy-pasted `let` bindings.

## Contributing

See the org-wide [CONTRIBUTING](https://github.com/nerima-lisp/.github/blob/main/CONTRIBUTING.md)
guide and the [package standard](https://github.com/nerima-lisp/.github/blob/main/PACKAGE_STANDARD.md).

## Support

See [SUPPORT](https://github.com/nerima-lisp/.github/blob/main/SUPPORT.md).

## License

MIT. See [LICENSE](LICENSE).
