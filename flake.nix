{
  description = "cl-cmatrix: a Matrix-style digital rain terminal screensaver for SBCL";

  inputs = {
    # nixos-unstable, not nixpkgs-unstable: it advances only after the NixOS
    # release tests pass, so it is less likely to land a broken build.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # `inputs.nixpkgs.follows` is mandatory on every input: without it each one
    # drags in its own nixpkgs, inflating flake.lock and rebuilding the same
    # derivations.

    # The org flake preset. Everything this file would otherwise spell out by
    # hand -- the `.asd` version extraction, `forAllSystems`, the treefmt eval
    # wired to both `formatter` and `checks.formatting`, the mkdocs package
    # plus its check, the run-tests.lisp gate, and the `apps.test`/
    # `apps.default` pair -- is one `mkPackageFlake` call below. Pinned to a
    # release TAG, never to the branch: a bare `github:nerima-lisp/cl-nix-forge`
    # follows that repository's default branch and would change this build
    # without warning.
    cl-nix-forge = {
      url = "github:nerima-lisp/cl-nix-forge/v0.5.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    cl-weave = {
      url = "github:nerima-lisp/cl-weave/v1.3.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Raw mode, the alternate screen, 256-color styling, the double-buffered
    # renderer, the real-time tick loop, and typed input events used by
    # src/input.lisp and src/run-state.lisp. v1.5.0 also exposes
    # MAKE-STREAM-INPUT-POLLER, so input handling consumes KEY-EVENT values
    # directly instead of polling raw characters.
    cl-tty-kit = {
      url = "github:nerima-lisp/cl-tty-kit/v1.5.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # cl-tty-kit v1.5.0 declares this runtime system directly. It is built from
    # source below so the complete dependency ancestry is visible to
    # cl-nix-forge on every supported platform.
    cl-codec-kit = {
      url = "github:nerima-lisp/cl-codec-kit/v0.5.0";
      flake = false;
    };

    # cl-tty-kit's transitive runtime closure. Keep these versions aligned with
    # cl-tty-kit v1.5.0 rather than relying on a sibling flake's registry.
    cl-host-kit = {
      url = "github:nerima-lisp/cl-host-kit/v0.3.1";
      flake = false;
    };
    cl-boundary-kit = {
      url = "github:nerima-lisp/cl-boundary-kit/v2.3.0";
      flake = false;
    };
    cl-date-kit = {
      url = "github:nerima-lisp/cl-date-kit/v1.0.0";
      flake = false;
    };
    cl-concurrent-kit = {
      url = "github:nerima-lisp/cl-concurrent-kit/v0.6.1";
      flake = false;
    };

    # Declarative CLI parsing plus --help/--version scaffolding, used by
    # src/cli.lisp. cl-cli remains a separately built sibling because its
    # package already carries its own ASDF ancestry.
    cl-cli = {
      url = "github:nerima-lisp/cl-cli/v1.3.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      cl-nix-forge,
      cl-weave,
      cl-tty-kit,
      cl-codec-kit,
      cl-host-kit,
      cl-boundary-kit,
      cl-date-kit,
      cl-concurrent-kit,
      cl-cli,
      treefmt-nix,
    }:
    let
      lib = nixpkgs.lib;

      # x86_64-linux is what CI gates; aarch64-darwin is the development machine.
      #
      # KNOWN, DELIBERATE DEVIATION from PACKAGE_STANDARD.md. That document's
      # 2026-08-01 revision retracted the two-system decision and now requires
      # `systems = [ "x86_64-linux" ]` alone, on the argument that declaring a
      # platform promises it works while the only thing checking it is someone
      # remembering to run a command locally. The org's own
      # scripts/check-conformance.sh reports this line as a failure, and that
      # report is correct rather than a false positive -- do not "fix" it by
      # editing the checker.
      #
      # It is kept anyway because development happens on darwin and the cost of
      # conforming is total: `mkPackageFlake` derives packages, checks, apps AND
      # devShells from this one list, so dropping aarch64-darwin would take `nix
      # build`, `nix develop` and every local `nix flake check` off the machine
      # the work is done on. The standard names that consequence and accepts it;
      # this repository accepts the opposite trade, and states which one it is
      # rather than claiming the standard permits it.
      #
      # What the deviation costs, stated so nobody mistakes it for a promise:
      # aarch64-darwin has no CI gate, so a build that works here is not
      # evidence it works anywhere. aarch64-linux and x86_64-darwin are nobody's
      # verification and are not declared at all.
      systems = [
        "x86_64-linux"
        "aarch64-darwin"
      ];

      meta = {
        description = "A Matrix-style digital rain terminal screensaver for SBCL";
        homepage = "https://github.com/nerima-lisp/cl-cmatrix";
        license = lib.licenses.mit;
        platforms = lib.platforms.unix;
        mainProgram = "cl-cmatrix";
      };

      clHostKit =
        ctx:
        ctx.cl.lispDerivation {
          pname = "cl-host-kit-cmatrix";
          lispSystem = "cl-host-kit";
          version = ctx.cl.fromAsdSystem "${cl-host-kit}/cl-host-kit.asd";
          src = cl-host-kit;
        };

      clBoundaryKit =
        ctx:
        ctx.cl.lispDerivation {
          lispSystem = "cl-boundary-kit";
          version = ctx.cl.fromAsdSystem "${cl-boundary-kit}/cl-boundary-kit.asd";
          src = cl-boundary-kit;
          lispDependencies = [ (clHostKit ctx) ];
        };

      clDateKit =
        ctx:
        ctx.cl.lispDerivation {
          lispSystem = "cl-date-kit";
          version = ctx.cl.fromAsdSystem "${cl-date-kit}/cl-date-kit.asd";
          src = cl-date-kit;
        };

      clConcurrentKit =
        ctx:
        ctx.cl.lispDerivation {
          lispSystem = "cl-concurrent-kit";
          version = ctx.cl.fromAsdSystem "${cl-concurrent-kit}/cl-concurrent-kit.asd";
          src = cl-concurrent-kit;
          lispDependencies = [
            (clBoundaryKit ctx)
            (clDateKit ctx)
          ];
        };

      clCodecKit =
        ctx:
        ctx.cl.lispDerivation {
          lispSystem = "cl-codec-kit";
          version = ctx.cl.fromAsdSystem "${cl-codec-kit}/cl-codec-kit.asd";
          src = cl-codec-kit;
        };
    in
    # `mkPackageFlake` spans systems -- it obtains a `pkgs` and its own
    # cl-nix-forge instance per entry in `systems` -- so the per-system `lib`
    # instance this function is *taken from* contributes nothing but the
    # function itself.
    cl-nix-forge.lib.${builtins.head systems}.mkPackageFlake {
      inherit
        self
        systems
        nixpkgs
        meta
        ;
      pname = "cl-cmatrix";

      # Single source of truth for the package version: the `:version` form in
      # cl-cmatrix.asd. A release only ever edits the .asd file and every
      # derivation carrying a version follows automatically.
      asd = ./cl-cmatrix.asd;

      # Path literal, not `self`: `lib.fileset` refuses a flake's string-like
      # `self`. `./.` is the same directory.
      root = ./.;

      # `mkLispSource` keeps an allowlist -- the .asd, run-tests.lisp, scripts,
      # src, t -- and docs/ is NOT in it, even though `docs.root` below builds
      # the site from the same tree: that is a separate derivation over a
      # separate source. t/docs-test.lisp reads docs/src through
      # `asdf:system-relative-pathname`, exactly as t/mutation-test.lisp reads
      # src/, so without this line the file is simply absent inside the sandbox
      # and the check fails at run time with a missing-pathname error that
      # looks nothing like the doc drift it exists to catch.
      #
      # The cost is real and accepted: an edit under docs/src now invalidates
      # the Lisp derivation and re-runs the whole suite. For a check whose
      # entire job is to fail when documentation and code disagree, re-running
      # on a documentation change is the behaviour we want, not a regression.
      # A path literal, not the string "docs/src": `lib.fileset` rejects
      # string-like values outright, and the error names `lib.fileset.unions`
      # rather than this argument.
      sourceInclude = [ ./docs/src ];

      # Source-based sibling systems are built as lispDerivations so their
      # ASDF ancestry is explicit. The pre-built cl-tty-kit package needs
      # fromDerivation because it comes from a sibling flake; its dependency
      # systems are supplied directly rather than left to ASDF discovery. Only
      # cl-codec-kit is supplied inside that opaque wrapper. cl-concurrent-kit
      # is supplied once below so its transitive closure is not duplicated.
      lispDependencies = ctx: [
        (ctx.cl.fromDerivation {
          drv = cl-tty-kit.packages.${ctx.system}.cl-tty-kit;
          lispDependencies = [ (clCodecKit ctx) ];
        })
        (clConcurrentKit ctx)
        cl-cli.packages.${ctx.system}.cl-cli
      ];

      # cl-weave is a dependency of `cl-cmatrix/test` only (see cl-cmatrix.asd),
      # so it is a CHECK dependency: it must not enter the library's closure.
      lispCheckDependencies = ctx: [ cl-weave.packages.${ctx.system}.cl-weave ];

      # Drives BOTH `checks.default` and `apps.test`, from this one number, so
      # the command a contributor runs by hand and the gate CI runs cannot
      # drift apart.
      timeoutSeconds = 120;

      # The delivered `cl-cmatrix` binary: `packages.default`, `apps.default`
      # and `apps.cl-cmatrix`, all three built from the same `lispDerivation`
      # arguments as `packages.cl-cmatrix`. Nothing here repeats what
      # cl-cmatrix.asd already declares -- `:build-operation "program-op"`,
      # `:build-pathname "cl-cmatrix"` and `:entry-point
      # "cl-cmatrix/cli::image-entry-point"` live in the system definition, so
      # `(asdf:operate 'asdf:program-op "cl-cmatrix")` in a REPL and `nix build`
      # produce the same binary. See cl-weave/flake.nix and cl-cowsay/flake.nix
      # for the pattern this follows.
      executable = {
        dynamicSpaceSize = 1024;
        installSource = true;

        # ASDF writes the program to the system's `:build-pathname` resolved
        # against its `:pathname`, and cl-cmatrix.asd sets `:pathname "src"`.
        # So `program-op` produces `src/cl-cmatrix`, not the `cl-cmatrix` at
        # the root that cl-nix-forge looks for by default
        # (lib/batteries/app.nix:294 defaults programPath to the system name,
        # and :311-313 fails the build when it is not there).
        #
        # This was invisible until CI grew a job that builds the binary. The
        # delivery path is platform-dependent: on Darwin, SBCL cannot dump a
        # working standalone executable, so cl-nix-forge takes a documented
        # workaround (app.nix:188) that saves a bare `.core` and wraps `sbcl
        # --core` -- a path on which this check never runs. Every local build
        # here is Darwin, so the Linux `program-op` path had never executed
        # anywhere: `nix flake check` evaluates `packages.*` and reports
        # "build skipped", and neither ci.yml nor release.yml ran `nix build`.
        # The first Linux build of the delivered binary in this repository's
        # history was the pty-e2e job added for v1.0.0, and it failed
        # immediately.
        programPath = "src/cl-cmatrix";
      };

      # docs/mkdocs.yml + docs/src/, built with `--strict` so a broken link or
      # a page missing from the nav is a build failure. `checks.docs` comes
      # with it.
      docs.root = ./docs;

      # ONE treefmt evaluation drives `nix fmt` and the `checks.formatting`
      # gate, so the formatter and CI can never disagree about what
      # "formatted" means.
      treefmt.evalModule = treefmt-nix.lib.evalModule;

      # `checks.coverage`, hence `nix build .#checks.<system>.coverage` and
      # `nix flake check`. `cl.mkCoverageReport` owns the exact
      # declaim/force-load/declaim SB-COVER sequence its own docs describe as
      # load-bearing (get it subtly wrong by hand -- e.g. touch "cl-cmatrix"
      # via any ASDF operation before that declaim, even transitively -- and
      # every run reports zero coverage, silently), so it drives the check
      # rather than a hand-rolled `mkScriptCheck` reimplementing the same
      # dance. It has deliberately no threshold option of its own (see
      # cl-nix-forge's checks.md "No minimum-coverage threshold" -- a
      # percentage gate would mean scraping SB-COVER's HTML, which has no
      # stability guarantee): it only makes the number visible. Enforcing an
      # actual floor is scripts/coverage-entry.lisp's job, run as this
      # ENTRYPOINT -- inside the same already-instrumented process, after
      # MKCOVERAGEREPORT's own force-load, so it only has to load and run the
      # test suite and read back CL-WEAVE:COVERAGE-STATISTICS. Since v1.0.0 its
      # floors are a RATCHET rather than fixed numbers: 86% expression and 93%
      # branch, each about a point under the measurement they were set from
      # (87.40% and 94.61%). Both clear nerima-lisp/.github's TEST_STANDARD.md
      # 90% branch requirement. The numbers live in that file, not here, and
      # are expected to be edited upward as coverage improves -- read its header
      # before touching either, because the five categories of line SB-COVER
      # structurally cannot credit are enumerated there, and they are why
      # expression coverage has a ceiling well below 100%.
      extraOutputs = ctx: {
        checks.coverage = ctx.cl.mkCoverageReport {
          drv = ctx.package;
          systems = [ "cl-cmatrix" ];
          entryPoint = "scripts/coverage-entry.lisp";
          timeoutSeconds = 420;
        };
      };
    };
}
