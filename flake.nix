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
      url = "github:nerima-lisp/cl-nix-forge/v0.4.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    cl-weave = {
      url = "github:nerima-lisp/cl-weave/v1.1.4";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Raw mode, the alternate screen, 256-color styling, the double-buffered
    # renderer, and the real-time tick loop, used by src/loop.lisp and
    # src/render.lisp. Pinned to v1.1.0: that is the tag carrying
    # src/tick-loop.lisp (TICK-LOOP-RUN-REALTIME), which this project's
    # animation loop depends on directly.
    cl-tty-kit = {
      url = "github:nerima-lisp/cl-tty-kit/v1.2.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Declarative CLI parsing plus --help/--version scaffolding, used by
    # src/cli.lisp.
    cl-cli = {
      url = "github:nerima-lisp/cl-cli/v1.2.0";
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
      cl-cli,
      treefmt-nix,
    }:
    let
      lib = nixpkgs.lib;

      # x86_64-linux is what CI gates; aarch64-darwin is the development
      # machine. Every per-system output -- packages, checks, apps AND devShells
      # -- comes from this one list, so leaving aarch64-darwin out takes `nix
      # build` and `nix develop` off the development machine as well. That trade
      # was made on 2026-08-01 and reverted on 2026-08-02; aarch64-darwin carries
      # no CI gate, which PACKAGE_STANDARD.md's "systems" section accepts
      # explicitly. aarch64-linux and x86_64-darwin are nobody's verification and
      # are not declared.
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

      # cl-tty-kit and cl-cli are BUILT DERIVATIONS (each sibling's ASDF
      # system, from its own flake's `packages.<system>`), not source
      # directories -- putting a sibling's uncompiled source on the registry
      # instead would have ASDF try to write fasls next to it, inside the
      # read-only Nix store.
      lispDependencies =
        ctx: [
          cl-tty-kit.packages.${ctx.system}.cl-tty-kit
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
      };

      # docs/mkdocs.yml + docs/src/, built with `--strict` so a broken link or
      # a page missing from the nav is a build failure. `checks.docs` comes
      # with it.
      docs.root = ./docs;

      # ONE treefmt evaluation drives `nix fmt` and the `checks.formatting`
      # gate, so the formatter and CI can never disagree about what
      # "formatted" means.
      treefmt.evalModule = treefmt-nix.lib.evalModule;
    };
}
