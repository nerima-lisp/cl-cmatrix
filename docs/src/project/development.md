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

Every `nix build` on this page that is not building the binary passes an
explicit `-o`/`--out-link`. Several outputs here are built from the same
working tree, and each of them would otherwise claim the default `./result`
in turn -- so a bare `nix build .#docs` silently replaces the binary symlink
that the pseudo-terminal check below depends on.

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

Tests live in `t/` and run under
[`cl-weave`](https://github.com/nerima-lisp/cl-weave). Most files are named
for the `src/` file they exercise, but the mapping is by *concern*, not one
file per source file. Four files are named for a behaviour that spans
several sources -- `advance-test.lisp` (the determinism guarantee),
`resize-test.lisp` (reflow), `state-machine-test.lisp` (the invariants every
reachable state has to satisfy under arbitrary advance/resize sequences), and
`mutation-test.lisp` -- and two read files off disk rather than calling
loaded symbols: `mutation-test.lisp` reads `src/`, and `docs-test.lisp` reads
`docs/src` to check this documentation against the implementation. Adding a
`src/` file does not oblige you to add a matching `t/` file; leaving its
behaviour unexercised does.

Stream spawn timing, glyph choice, and each column's async threshold are all
drawn from an injectable `random-state`, so the deterministic tests pin exact
resulting column state from a fixed seed rather than asserting on rendered
output. Parametrized cases use `cl-weave`'s `it-each` table-test macro
instead of a hand-rolled loop over `expect`, so each input gets its own named
pass/fail; invariants that should hold across a generated input space use
`it-property`; shared setup uses `before-each` fixtures over a dynamic
variable instead of copy-pasted `let` bindings.
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
uses `cl-weave`'s `run-mutations`/`assert-mutation-score` against three pure
functions: `%column-advances-p` (`src/state.lisp`), the async gate that
decides whether a column moves this frame, and `column-head-p` and
`column-cell-at` (`src/column.lisp`), the two bounds-checked cell accessors.
It mutates each function's body -- flipping comparison and arithmetic
operators, boolean literals, and `if` branches -- and re-checks every variant
against the same case battery a unit test would use. `sb-cover` line coverage
proves a line executed, not that a wrong result there would be caught; a
mutation the battery fails to notice ("survived") marks exactly that gap.
Each body is read live from `src/` on every run, never copied into the test
file, so there is nothing here to fall out of sync with the real
implementation.

The helper asserts that the mutation list is non-empty because `cl-weave`
scores an unmutated function as 1.0. Bounds-check case tables begin with an
in-bounds case because looser mutants can signal on out-of-range inputs;
`cl-weave` records that as an error rather than a killed mutant.

### Pseudo-terminal end-to-end check

`t/pty-e2e.exp` drives the delivered binary through a real pseudo-terminal.
The in-process `cl-weave` suite structurally cannot cover this: `run-matrix`
is never called there, and what matters here -- entering the alternate screen,
hiding the cursor, restoring both on the way out, and handing the terminal
back in the `termios` state it was borrowed in -- only happens once a raw-mode
full-screen program is attached to something that can actually be put into raw
mode. A pipe cannot.

The script spawns `cl-cmatrix --fps 1 --seed 1` twice on an 80x24 pty under
`TERM=xterm-256color` and asserts the exact control sequences in order:
alternate-screen entry, then cursor hide, then -- after `q` in the first case
and `SIGINT` in the second -- cursor restore, then alternate-screen exit. Both
cases require the process to exit 0 on its own rather than die from the
signal, so the second spawn `exec`s the binary and `SIGINT` reaches it rather
than the wrapping shell. The first case additionally compares
`stty -g` from before and after the run, masking off `PENDIN` (kernel state
set while canonical input is being restored, not a setting the program owns),
so a run that leaves the terminal in raw mode fails instead of merely looking
wrong afterwards. On any failure the captured pty transcript is written to
stderr.

CI runs it as the `pty-e2e` job in `.github/workflows/ci.yml`, separately
from `nix flake check`. It stays out of the flake because a check inside
the Nix build sandbox would depend on a pty being available there, and a
failure for that reason would be indistinguishable from the
terminal-restoration bug the script exists to catch.

To run it locally you need `expect`, plus `perl` and `stty` on `PATH`, and an
already-built binary:

```sh
nix build --out-link pty-binary
nix shell --inputs-from . nixpkgs#expect --command \
  expect t/pty-e2e.exp ./pty-binary/bin/cl-cmatrix
```

`--inputs-from .` takes `expect` from this flake's own pinned nixpkgs rather
than from whatever happens to be installed, which is what makes a local run
mean the same thing as the CI job. Setting `TMPDIR` is optional hygiene: the
script allocates its transcripts with `file tempfile` rather than building a
predictable path, so it works without the variable and does not race a
world-writable `/tmp`.

### Informational benchmarks

The benchmark suite measures matrix advancement and rendering without making
the run a pass/fail gate. It writes tab-separated results to
`BENCHMARK_OUTPUT` and one log per child process under `BENCHMARK_LOG_DIR`.
Keep those paths outside the repository when running locally:

```sh
nix develop --command sh -c \
  'BENCHMARK_PROCESSES=1 \
   BENCHMARK_TICKS=1000 \
   BENCHMARK_WARMUP=100 \
   BENCHMARK_SAMPLES=5 \
   BENCHMARK_SIZES=80x24 \
   BENCHMARK_OUTPUT=/tmp/cl-cmatrix-benchmark.tsv \
   BENCHMARK_LOG_DIR=/tmp/cl-cmatrix-benchmark-logs \
   ./scripts/benchmark-suite.sh'
```

Use comma-separated values in `BENCHMARK_SIZES` to measure multiple matrix
sizes. `BENCHMARK_PROCESSES`, `BENCHMARK_TICKS`, `BENCHMARK_WARMUP`, and
`BENCHMARK_SAMPLES` control process count and sampling volume; the suite also
accepts `BENCHMARK_TIMEOUT_SECONDS` for the per-process timeout.

`scripts/benchmark.lisp` is the measurement itself: one SBCL process, one
matrix size, a fixed seed, and three workloads -- matrix advance, advance plus
dirty render, and advance plus dirty render plus ANSI encode -- each reported
as per-sample, median, min/max and spread figures in ns/tick and
bytes-consed/tick. It applies no threshold and can be run on its own
(`sbcl --script scripts/benchmark.lisp --help` lists its options).
`scripts/benchmark-suite.sh` measures nothing of its own: it runs that runner
once per size and process index under the timeout, parses the matrix-advance
and dirty-render medians back out of each log into the TSV, and fails if a
size did not produce the expected number of rows. The ANSI-encode workload is
reported by the runner but not carried into the TSV.

### Coverage

```sh
nix build .#checks.<system>.coverage -o coverage-report
```

`$out` is the `sb-cover` HTML report itself, produced by `cl-nix-forge`'s
`mkCoverageReport`. `scripts/coverage-entry.lisp` runs as its entry point:
it loads and runs the test suite, then gates on `cl-weave:coverage-statistics`
against `+minimum-expression-percent+` and `+minimum-branch-percent+`, which
that file defines. The run prints both measurements next to both floors, so
the current numbers come from the build log rather than from this page.

Treat the floors as regression gates, not headroom. Raise a floor when new
coverage clears it; never lower one to make a red gate green.

The two floors are not the same number because the remaining expression gap
is structural rather than a testability shortfall. `sb-cover` never credits
compile-time-only forms -- an `in-package` form, a `defpackage` body, a bare
`defmacro`'s own template, a `defstruct` slot's `:type` declaration -- and
every `defparameter` whose value was more than a bare literal has already
been rewritten into a called function to get credit where that was possible.
`run-matrix`'s and `main`'s true I/O bodies are covered for real, but only
via the out-of-process `it-isolated` tests above, and are invisible to this
process's coverage data by `sb-cover`'s per-process design.
The remaining gap is a property of `sb-cover` and the process boundary, not a
reason to lower either floor.

## Source layout

```text
src/
├── package.lisp        both packages, every import/export
├── conditions.lisp      cl-cmatrix-error and its subclasses
├── config.lisp          upstream constants, defaults, parallel threshold
├── glyphs.lisp           built-in glyph sets, the :charset registry
├── color-scheme.lisp     built-in color schemes, their registry
├── registry.lisp         shared list-*/​*-p registry-query macro
├── column.lisp           one column's cell buffer, both scroll algorithms
├── state.lisp            matrix-state, the pure whole-screen struct
├── concurrent.lisp       worker configuration and parallel column advance
├── render-context.lisp   render-owned style memoization
├── render.lisp           matrix-state -> cl-tty-kit screen
├── input.lisp            typed key-event quit dispatch and CPS helpers
├── run-state.lisp        mutable realtime driver state and tick helpers
├── runtime.lisp          terminal session, tick loop, and run-matrix
├── cli-options.lisp      declarative command-line option metadata
└── cli.lisp              cl-cmatrix/cli: flags, main, image-entry-point
t/                        cl-weave specs (see "Running the tests" for how they
                          map onto src/), plus pty-e2e.exp
scripts/
├── benchmark-suite.sh    repeats the runner, reduces logs to TSV
├── benchmark.lisp        the single-process benchmark runner
└── coverage-entry.lisp   coverage entry point and floor gate
docs/                     this site (mkdocs.yml + src/)
```

## Documentation

```sh
nix build .#docs --out-link docs-site --print-build-logs
```

`--strict` fails the build on a broken link, a bad anchor, or a page missing
from `mkdocs.yml`'s `nav`. Pass `--out-link`: without it this build takes the
default `./result`, and the pseudo-terminal check above then drives whatever
that symlink last pointed at -- a documentation site with no `bin/` in it.

`t/docs-test.lisp` is the other half of this gate, and runs inside the normal
suite: it reads `docs/src` live and asserts that every symbol these pages
qualify with a single-colon package prefix really is exported, and that every
option spelling shown in a working command really is accepted. It is keyed on
the context that makes a token a claim, not on the token's shape -- a
double-colon qualifier is documented as reaching an internal, so it is
skipped rather than checked. Exported-symbol changes,
lambda-list changes, and new or changed conditions belong in the same pull
request as the code change -- see [API reference](../reference/api.md) and
[Conditions](../reference/conditions.md).

## Formatting

```sh
nix fmt
```

One `treefmt` evaluation drives both `nix fmt` and `checks.formatting`, so
the formatter and CI can never disagree about what "formatted" means. It
formats Nix sources only; Lisp and Markdown are not treefmt's concern here.
