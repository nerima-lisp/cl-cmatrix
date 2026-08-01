# cl-cmatrix

[![CI](https://github.com/nerima-lisp/cl-cmatrix/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/nerima-lisp/cl-cmatrix/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Documentation](https://img.shields.io/badge/docs-MkDocs%20Material-0a7a5a)](https://nerima-lisp.github.io/cl-cmatrix/)

A Matrix-style digital rain terminal screensaver for SBCL: one independently
falling character stream per terminal column, each with a bright head and a
256-color dimming trail. Reflows on terminal resize and quits cleanly on
q/Escape/Ctrl-C, always restoring the terminal's prior state. Not a port of
the classic `cmatrix`'s katakana bitmap font -- the default glyph set is
plain printable ASCII, an original and simpler choice.

Full documentation is published at <https://nerima-lisp.github.io/cl-cmatrix/>.
The source for that site lives in [docs/src/](docs/src/).

## Quick Start

```sh
cl-cmatrix                  # default green rain at normal speed
cl-cmatrix --speed 2 -c cyan
```

Or as a library:

```lisp
(asdf:load-system "cl-cmatrix")

(cl-cmatrix:run-matrix :speed 1.5 :color :cyan)
```

## Install

```nix
# flake.nix
inputs.cl-cmatrix = {
  url = "github:nerima-lisp/cl-cmatrix/v0.1.0";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

Note the pinned tag. Consumers inside this org must pin a release tag rather
than follow the default branch.

## Documentation

- [Getting started](https://nerima-lisp.github.io/cl-cmatrix/getting-started/)
- [API reference](https://nerima-lisp.github.io/cl-cmatrix/reference/api/)

## Development

```sh
nix develop          # SBCL with CL_SOURCE_REGISTRY already set
nix run .#test       # run the test suite
nix flake check      # tests + formatting + docs, the same gate CI uses
nix fmt              # format Nix sources (treefmt)
```

Tests live in `t/` and run under [cl-weave](https://github.com/nerima-lisp/cl-weave),
the org's test framework. Fall timing, glyph choice, and reset are all routed
through an injectable `RANDOM-STATE`, so the deterministic tests pin exact
output from a fixed seed rather than asserting on visual output.

## Contributing

See the org-wide [CONTRIBUTING](https://github.com/nerima-lisp/.github/blob/main/CONTRIBUTING.md)
guide and the [package standard](https://github.com/nerima-lisp/.github/blob/main/PACKAGE_STANDARD.md).

## Support

See [SUPPORT](https://github.com/nerima-lisp/.github/blob/main/SUPPORT.md).

## License

MIT. See [LICENSE](LICENSE).
