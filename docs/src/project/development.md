# Development

See the org-wide [CONTRIBUTING](https://github.com/nerima-lisp/.github/blob/main/CONTRIBUTING.md)
guide and [PACKAGE_STANDARD](https://github.com/nerima-lisp/.github/blob/main/PACKAGE_STANDARD.md)
for workflow, branching, and release conventions. This page covers only what
is specific to building, testing, and measuring `cl-cmatrix` itself.

## Development environment

```sh
nix develop          # SBCL with CL_SOURCE_REGISTRY set to every sibling
nix build             # -> ./result/bin/cl-cmatrix, the delivered binary
nix build .#cl-cmatrix   # the ASDF system as a library, no binary
nix flake check       # every gate below, the same set CI runs
```

### Flake outputs

| Output | What it is |
|---|---|
| `packages.cl-cmatrix` | The `cl-cmatrix` ASDF system, built as a library. |
| `packages.default` | The delivered `cl-cmatrix` binary. |
| `packages.docs` | This documentation site, built with `--strict`. |
| `apps.default` / `apps.cl-cmatrix` | Run the delivered binary (`nix run .`). |
| `apps.test` | Run the test suite (`nix run .#test`). |
| `checks.default` | The test-suite gate `nix flake check` runs. |
| `checks.coverage` | The `sb-cover` report plus the expression/branch floor gate. |
| `checks.formatting` | The treefmt gate; `nix fmt` fixes what it flags. |
| `checks.docs` | Asserts the `--strict` docs build produced a site. |
| `devShells.default` | `nix develop`'s shell. |
| `formatter` | Backs `nix fmt`. |

## Running the tests

```sh
nix run .#test        # sbcl --script run-tests.lisp, the same runner CI uses
nix flake check       # tests + coverage + formatting + docs together
```

Tests live in `t/`, one file per `src/` file, and run under
[`cl-weave`](https://github.com/nerima-lisp/cl-weave). Fall timing, glyph
choice, and column reset are all routed through an injectable
`random-state`, so the deterministic tests pin exact resulting column state
from a fixed seed rather than asserting on rendered output. Parametrized
cases use `cl-weave`'s `it-each` table-test macro instead of a hand-rolled
loop over `expect`, so each input gets its own named pass/fail; shared setup
uses `before-each` fixtures over a dynamic variable instead of copy-pasted
`let` bindings.
`t/concurrent-test.lisp` additionally checks deterministic executor-backed
advances for wide matrices and keeps the serial fallback covered.

`run-matrix` itself, and `main`/`image-entry-point` (`src/cli.lisp`), are
never called from the main test process: all three end in either a real
terminal session or `host-kit:quit`, a genuine process exit. `t/cli-test.lisp`
exercises `main` and `image-entry-point` for real via `cl-weave`'s
`it-isolated`, in a forked SBCL image instead. See
[Architecture](../reference/architecture.md#why-run-matrix-main-and-image-entry-point-are-tested-out-of-process)
for why.

### Mutation testing

Beyond example-based `describe`/`it`/`expect` tests, `t/mutation-test.lisp`
uses `cl-weave`'s `run-mutations`/`assert-mutation-score` against
`column-row-lit-p` (`src/column.lisp`): it mutates that function's body
(flipping comparison operators) and re-checks each variant against the same
case battery a unit test would use. `sb-cover` line coverage proves a line
executed, not that a wrong result there would be caught -- a mutation the
battery fails to notice ("survived") marks exactly that gap. The function's
body is read live from `src/column.lisp` on every run, never copied into the
test file, so there is nothing here to fall out of sync with the real
implementation.

### Coverage

```sh
nix build .#checks.<system>.coverage -o coverage-report
```

`$out` is the `sb-cover` HTML report itself, produced by `cl-nix-forge`'s
`mkCoverageReport`. `scripts/coverage-entry.lisp` runs as its entry point:
it loads and runs the test suite, then gates on `cl-weave:coverage-statistics`
against two floors -- 90% branch (cleared: measured 92.59%) and 80%
expression (measured 86.41%). The two floors differ because the remaining
expression gap is structural, not a testability shortfall: `sb-cover` never
credits compile-time-only forms (`in-package`, `defpackage` bodies, a bare
`defmacro`'s own template) or a `defstruct` slot's `:type` declaration, and
every `defparameter` whose value was more than a bare literal was already
rewritten into a called function to get credit where that was possible.
`run-matrix`'s and `main`'s true I/O bodies are covered for real, but only
via the out-of-process `it-isolated` tests above -- invisible to this
process's own coverage data by `sb-cover`'s per-process design, not a gap in
testing. `scripts/coverage-entry.lisp`'s own header comment has the full,
line-by-line accounting if you want to re-derive the number yourself; read it
before proposing to raise either floor.

## Source layout

```text
src/
├── package.lisp        both packages, every import/export
├── conditions.lisp      cl-cmatrix-error and its subclasses
├── config.lisp          shared defaults and parallelization threshold
├── glyphs.lisp           built-in glyph sets, the :charset registry
├── color-scheme.lisp     built-in color schemes, their registry
├── registry.lisp         shared list-*/​*-p registry-query macro
├── column.lisp           one falling character stream
├── state.lisp            matrix-state, the pure whole-screen struct
├── concurrent.lisp       worker configuration and parallel column advance
├── render-context.lisp   render-owned style memoization
├── render.lisp           matrix-state -> cl-tty-kit screen
├── input.lisp            typed key-event quit dispatch and CPS helpers
├── run-state.lisp        mutable realtime driver state and tick helpers
├── runtime.lisp          terminal session, tick loop, and run-matrix
├── cli-options.lisp      declarative command-line option metadata
└── cli.lisp              cl-cmatrix/cli: flags, main, image-entry-point
t/                        one test file per source concern above
docs/                     this site (mkdocs.yml + src/)
```

## Documentation

```sh
nix build .#docs --print-build-logs
```

`--strict` fails the build on a broken link, a bad anchor, or a page missing
from `mkdocs.yml`'s `nav`. Exported-symbol changes, lambda-list changes, and
new or changed conditions belong in the same pull request as the code change
-- see [API reference](../reference/api.md) and
[Conditions](../reference/conditions.md).

## Formatting

```sh
nix fmt
```

One `treefmt` evaluation drives both `nix fmt` and `checks.formatting`, so
the formatter and CI can never disagree about what "formatted" means. It
formats Nix sources only; Lisp and Markdown are not treefmt's concern here.
