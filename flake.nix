{
  description = "nim-cli-spec - declarative command-line descriptions for Nim (clispec)";

  inputs = {
    nixos-modules.url = "github:metacraft-labs/devops-modules";
    nixpkgs.follows = "nixos-modules/nixpkgs-unstable";
    flake-parts.follows = "nixos-modules/flake-parts";
    git-hooks.follows = "nixos-modules/git-hooks-nix";

    # The optional TOML format adapter (`src/clispec/toml_source.nim`) reads
    # files with status-im's nim-toml-serialization. The library itself
    # never imports it; only that module and the tests that drive it do, so
    # these sources are put on the tests' path (`CLISPEC_FORMAT_PATHS`) and
    # nowhere else. The revisions are a set known to work together:
    # toml-serialization v0.2.18 and the serialization, faststreams, stew
    # and results revisions whose sources match it.
    nim-toml-serialization-src = {
      url = "github:status-im/nim-toml-serialization/b5b387e6fb2a7cc75d54a269b07cc6218361bd46";
      flake = false;
    };
    nim-serialization-src = {
      url = "github:status-im/nim-serialization/1790d8a931fce125d6722f7ee8432ee8c054d297";
      flake = false;
    };
    nim-faststreams-src = {
      url = "github:status-im/nim-faststreams/50889cd16ec8771106cdd0eeea460039e8571e06";
      flake = false;
    };
    nim-stew-src = {
      url = "github:status-im/nim-stew/30dadcd14b5ec1631935d9037213ece6871cc11a";
      flake = false;
    };
    nim-results-src = {
      url = "github:arnetheduck/nim-results/55b41b285def7b7b98dd5b9669f352d1fdc35c2b";
      flake = false;
    };
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
        { pkgs, ... }:
        let
          version = builtins.replaceStrings [ "\n" "\r" ] [ "" "" ] (builtins.readFile ./version.txt);
        in
        {
          # The dev env `repro.nim`'s `devEnv` activates (`useFlakeDevShell()`)
          # and CI enters through setup-dev-env. It must stand on its own: CI
          # checks this repository out without the workspace around it.
          #
          # `mkShell`'s stdenv supplies the C back-end `nim c` shells out to
          # (gcc on Linux, clang on macOS), matching the `uses:` floor in
          # `repro.nim`. The tests need nothing beyond `nim` and the standard
          # library.
          #
          # No shellHook installs git hooks. The rules live in the committed
          # `.pre-commit-config.yaml` (the flake provides the tools, the
          # committed config provides the rules), installed with
          # `prek install`. The shell only provides the tools that config runs:
          # its `language: system` hooks and `uv`, without which prek cannot
          # build the python hook environments on NixOS.
          devShells.default = pkgs.mkShell {
            # The `--path:` flags the TOML adapter's tests need (see the
            # inputs above); the Justfile passes them to every test compile.
            CLISPEC_FORMAT_PATHS = builtins.concatStringsSep " " (
              map (src: "--path:${src}") [
                inputs.nim-toml-serialization-src
                inputs.nim-serialization-src
                inputs.nim-faststreams-src
                inputs.nim-stew-src
                inputs.nim-results-src
              ]
            );
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
            ];
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
