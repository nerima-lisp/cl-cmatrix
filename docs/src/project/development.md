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

Use an explicit `-o`/`--out-link` for non-binary builds so their outputs do
not replace the default `./result` symlink used by the binary checks.

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
[`cl-weave`](https://github.com/nerima-lisp/cl-weave). Tests are organized by
concern, including determinism, resize reflow, state-machine invariants,
mutation coverage, concurrency, CLI isolation, and documentation checks.
Randomness is injectable, so deterministic tests assert exact state from fixed
seeds. `it-each`, `it-property`, and shared fixtures provide named cases and
generated invariant checks.

`run-matrix` itself, and `main`/`image-entry-point` (`src/cli.lisp`), are
never called from the main test process: all three end in either a real
terminal session or `host-kit:quit`, a genuine process exit. `t/cli-test.lisp`
exercises `main` and `image-entry-point` for real via `cl-weave`'s
`it-isolated`, in a forked SBCL image instead. See
[Architecture](../reference/architecture.md#why-run-matrix-main-and-image-entry-point-are-tested-out-of-process)
for why.

### Mutation testing

`t/mutation-test.lisp` uses `cl-weave` mutation testing against the pure state
and column-accessor functions. Mutants are read from `src/` and checked
against the unit-test cases; surviving mutants expose gaps that line coverage
would miss. The helper also requires a non-empty mutation set and starts
bounds-check cases with an in-bounds input so invalid mutants are classified
correctly.

### Pseudo-terminal end-to-end check

`t/pty-e2e.exp` drives the delivered binary through a real pseudo-terminal to
check alternate-screen and cursor control sequences, clean exit on `q` and
`SIGINT`, and restoration of the borrowed `termios` state.

It runs `cl-cmatrix --fps 1 --seed 1` twice on an 80x24 pty under
`TERM=xterm-256color`, and compares the terminal state before and after the
interactive case. Failures include the captured pty transcript.

CI runs it as the `pty-e2e` job in `.github/workflows/ci.yml`, separately from
`nix flake check` because the Nix build sandbox does not provide a pty.

To run it locally you need `expect`, plus `perl` and `stty` on `PATH`, and an
already-built binary:

```sh
nix build --out-link pty-binary
nix shell --inputs-from . nixpkgs#expect --command \
  expect t/pty-e2e.exp ./pty-binary/bin/cl-cmatrix
```

`--inputs-from .` uses this flake's pinned nixpkgs, matching CI. `TMPDIR` is
optional because the script creates unique temporary transcripts.

### Informational benchmarks

The benchmark suite measures matrix advancement and rendering without making
the run a pass/fail gate. It writes TSV results to `BENCHMARK_OUTPUT` and
child-process logs under `BENCHMARK_LOG_DIR`; keep both outside the repository:

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

Use comma-separated values in `BENCHMARK_SIZES` for multiple matrix sizes.
`BENCHMARK_PROCESSES`, `BENCHMARK_TICKS`, `BENCHMARK_WARMUP`,
`BENCHMARK_SAMPLES`, and `BENCHMARK_TIMEOUT_SECONDS` control the run.
`scripts/benchmark.lisp` reports advance, dirty-render, and ANSI-encode
workloads; `scripts/benchmark-suite.sh` aggregates the first two into TSV and
checks that every requested size produced the expected rows.

### Coverage

```sh
nix build .#checks.<system>.coverage -o coverage-report
```

The output is an `sb-cover` HTML report from `cl-nix-forge`'s
`mkCoverageReport`. `scripts/coverage-entry.lisp` runs the suite and gates
`cl-weave:coverage-statistics` against its expression and branch floors; the
build log prints the measured values beside those floors.

Treat the floors as regression gates, not headroom. Raise a floor when new
coverage clears it; never lower one to make a red gate green.

The expression floor is lower because `sb-cover` does not credit
compile-time-only forms and does not combine coverage from the out-of-process
CLI tests. This is a limitation of the measurement, not a reason to lower
either floor.

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
