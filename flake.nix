{
  description = "cl-cmatrix: a Matrix-style digital rain terminal screensaver for SBCL";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    cl-nix-forge = {
      url = "github:nerima-lisp/cl-nix-forge/v0.5.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    cl-weave = {
      url = "github:nerima-lisp/cl-weave/v1.3.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    cl-tty-kit = {
      url = "github:nerima-lisp/cl-tty-kit/v1.5.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    cl-codec-kit = {
      url = "github:nerima-lisp/cl-codec-kit/v0.5.0";
      flake = false;
    };

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
    cl-nix-forge.lib.${builtins.head systems}.mkPackageFlake {
      inherit
        self
        systems
        nixpkgs
        meta
        ;
      pname = "cl-cmatrix";

      asd = ./cl-cmatrix.asd;

      root = ./.;

      sourceInclude = [ ./docs/src ];

      lispDependencies = ctx: [
        (ctx.cl.fromDerivation {
          drv = cl-tty-kit.packages.${ctx.system}.cl-tty-kit;
          lispDependencies = [ (clCodecKit ctx) ];
        })
        (clConcurrentKit ctx)
        cl-cli.packages.${ctx.system}.cl-cli
      ];

      lispCheckDependencies = ctx: [ cl-weave.packages.${ctx.system}.cl-weave ];

      timeoutSeconds = 120;

      executable = {
        dynamicSpaceSize = 1024;
        installSource = true;

        programPath = "src/cl-cmatrix";
      };

      docs.root = ./docs;

      treefmt.evalModule = treefmt-nix.lib.evalModule;

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
