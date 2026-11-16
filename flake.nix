{
  description = "nim-cli-spec - declarative command-line descriptions for Nim (clispec)";

  inputs = {
    nixos-modules.url = "github:metacraft-labs/devops-modules";
    nixpkgs.follows = "nixos-modules/nixpkgs-unstable";
    flake-parts.follows = "nixos-modules/flake-parts";
    git-hooks.follows = "nixos-modules/git-hooks-nix";
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      perSystem =
        { pkgs, system, ... }:
        let
          version = builtins.replaceStrings [ "\n" "\r" ] [ "" "" ] (builtins.readFile ./version.txt);
          # A second, newer Nim for `just lint`'s cross-OS check only: the
          # metacraft-labs/nim fork (Nim 2.3.1 devel). Its standard library
          # differs from 2.2's on Windows (`FileHandle` is `int` there, not
          # `cint`), so code that type-checks for Windows with 2.2 can fail
          # with it. It is taken from the reprobuild flake that `nixos-modules`
          # already pins, so this repository defines no second build of it and
          # follows that pin when `nix flake update nixos-modules` moves it.
          # The main compiler stays nixpkgs' `nim`.
          nimFork = inputs.nixos-modules.inputs.reprobuild.packages.${system}.nim-fork;
        in
        {
          # The dev env `repro.nim`'s `devEnv` activates (`useFlakeDevShell()`)
          # and CI enters through setup-dev-env. It must stand on its own: CI
          # checks this repository out without the workspace around it.
          #
          # `mkShell`'s stdenv supplies the C back-end `nim c` shells out to
          # (gcc on Linux, clang on macOS), matching the `uses:` floor in
          # `repro.nim`. The library and its tests need nothing beyond `nim`
          # and the standard library.
          #
          # No shellHook installs git hooks. The rules live in the committed
          # `.pre-commit-config.yaml` (the flake provides the tools, the
          # committed config provides the rules), installed with
          # `prek install`. The shell only provides the tools that config runs:
          # its `language: system` hooks and `uv`, without which prek cannot
          # build the python hook environments on NixOS.
          devShells.default = pkgs.mkShell {
            packages = with pkgs; [
              nim
              just
              git
              # pre-commit tooling for the committed config
              prek
              uv
              editorconfig-checker
              nixfmt
              prettier
              # The shells the real-shell completion test
              # (`tests/e2e_cs_m5_real_shell_completion.nim`, `just e2e`)
              # drives in a pseudo-terminal. bash comes with mkShell's stdenv.
              bashInteractive
              zsh
              fish
              powershell
            ];
            # Every shell above is provisioned, so the real-shell test fails
            # rather than skips when one of them cannot be found.
            CLISPEC_E2E_REQUIRE = "bash,zsh,fish,pwsh";
            # The further compilers `just lint` runs its cross-OS check with
            # (see the Justfile); the recipe refuses to run without one.
            CLISPEC_EXTRA_NIM = "${nimFork}/bin/nim";
          };

          # The library is source: consumers put `src/` on their Nim path.
          packages.default = pkgs.stdenvNoCC.mkDerivation {
            pname = "nim-cli-spec";
            inherit version;
            src = ./.;
            dontBuild = true;
            installPhase = ''
              mkdir -p $out
              cp -R src clispec.nimble version.txt README.md LICENSE $out/
            '';
          };
        };
    };
}
