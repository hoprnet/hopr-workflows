{
  description = "Hopr Workflows flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    flake-utils.url = "github:numtide/flake-utils";
    flake-parts.url = "github:hercules-ci/flake-parts";
    nix-lib.url = "github:hoprnet/nix-lib";
    nix-lib.inputs.nixpkgs.follows = "nixpkgs";
    nix-lib.inputs.flake-parts.follows = "flake-parts";
    nix-lib.inputs.flake-utils.follows = "flake-utils";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";
    pre-commit.url = "github:cachix/git-hooks.nix";
    pre-commit.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      flake-utils,
      flake-parts,
      nix-lib,
      pre-commit,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = flake-utils.lib.defaultSystems;

      imports = [
        nix-lib.flakeModules.default
      ];

      perSystem =
        { system, ... }:
        let
          pkgs = import nixpkgs { inherit system; };
          pythonEnv = pkgs.python312.withPackages (
            ps: with ps; [
              google-cloud-artifact-registry
              google-auth
            ]
          );
          pre-commit-check = pre-commit.lib.${system}.run {
            src = ./.;
            hooks = {
              check-executables-have-shebangs.enable = true;
              check-shebang-scripts-are-executable.enable = true;
              check-case-conflicts.enable = true;
              check-symlinks.enable = true;
              check-merge-conflicts.enable = true;
              check-added-large-files.enable = true;
              commitizen.enable = true;
              renovate-config-validator = {
                enable = true;
                name = "Renovate config validator";
                entry = "${pkgs.writeShellScript "validate-renovate" ''
                  ${pkgs.nodejs}/bin/npx --yes --package renovate -- renovate-config-validator "$@"
                ''}";
                files = "renovate\\.json$";
                language = "system";
                pass_filenames = true;
              };
            };
            tools = pkgs;
          };
        in
        {
          devShells.default = pkgs.mkShell {
            buildInputs = [
              pythonEnv
              pkgs.google-cloud-sdk
              pkgs.jq
            ];
            shellHook = ''
              ${pre-commit-check.shellHook}
            '';
          };
          apps.cleanup-docker-images = flake-utils.lib.mkApp {
            drv = pkgs.writeShellScriptBin "cleanup-docker-images" ''
              exec ${pythonEnv.interpreter} ./scripts/cleanup-docker-images.py "$@"
            '';
          };
          apps.cleanup-artifact-files = flake-utils.lib.mkApp {
            drv = pkgs.writeShellScriptBin "cleanup-artifact-files" ''
              exec ${pythonEnv.interpreter} ./scripts/cleanup-artifact-files.py "$@"
            '';
          };
          apps.cleanup-npm-packages = flake-utils.lib.mkApp {
            drv = pkgs.writeShellScriptBin "cleanup-npm-packages" ''
              exec ${pythonEnv.interpreter} ./scripts/cleanup-npm-packages.py "$@"
            '';
          };
        };
    };
}
