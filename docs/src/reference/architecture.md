# Architecture

## Two packages, one binary

`src/package.lisp` defines two packages. `cl-cmatrix` is the animation
engine: pure state construction, advance, and resize, plus the
[`cl-tty-kit`](https://nerima-lisp.github.io/cl-tty-kit/) rendering and the
real-time driver loop built on top of it. `cl-cmatrix/cli` is a thin
command-line front end over that engine, importing only `run-matrix` and the
handful of registry lookups (`list-color-schemes`, `list-charsets`,
`charset-glyphs`) it needs to translate flags into keyword arguments.

The split exists so `(asdf:load-system "cl-cmatrix")` stays usable as a
library with no `cl-cli`-flavoured argv parsing along for the ride --
`cl-cowsay` follows the same shape. Neither package `:use`s a sibling
package (`CODING_STANDARD.md`'s "`:use` is `#:cl` only"); every `cl-tty-kit`,
`cl-cli`, and `host-kit` symbol either package calls is imported by name, so
its origin stays visible at every call site's package qualification.

| File | Owns |
|---|---|
| `src/package.lisp` | Both `defpackage` forms and every import/export. |
| `src/conditions.lisp` | `cl-cmatrix-error` and its four subclasses. |
| `src/glyphs.lisp` | The three built-in glyph sets and the `:charset` registry. |
| `src/color-scheme.lisp` | The eleven built-in color schemes and their registry. |
| `src/registry.lisp` | `define-registry-queries`, shared by the two registries above. |
| `src/column.lisp` | `column`: one falling character stream's state and fall logic. |
| `src/state.lisp` | `matrix-state`: the pure, whole-screen struct `t/` tests directly. |
| `src/render.lisp` | `matrix-draw`/`matrix-cell-style`, mapping `matrix-state` onto a `cl-tty-kit` screen. |
| `src/loop.lisp` | `run-state`, the real-time driver loop, and `run-matrix` itself. |
| `src/cli.lisp` | `cl-cmatrix/cli`: flag parsing, `main`, `image-entry-point`. |

## Why `matrix-state` and `run-state` are separate structs

`matrix-state` (`src/state.lisp`) holds only what `matrix-advance` needs:
columns, dimensions, speed, color, glyphs, and an injected `random-state`.
Nothing in it touches a terminal. `run-state` (`src/loop.lisp`) wraps a
`matrix-state` together with a `cl-tty-kit` renderer, the input stream, and
a quit flag -- the I/O half `run-matrix`'s tick loop needs.

Keeping them separate is what lets `t/`'s deterministic tests call
`matrix-advance` directly, seed a `random-state`, and assert on exact
resulting column state, with no renderer, no terminal, and no real time
involved. A single merged struct would force every one of those tests
through a real or faked terminal session just to construct it.

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
into the shared macro to read as anything but a forced abstraction.
