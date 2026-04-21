{
  description = "Hopr Workflows flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    flake-utils.url = "github:numtide/flake-utils";
    flake-parts.url = "github:hercules-ci/flake-parts";
    nix-lib.url = "github:hoprnet/nix-lib";
    nix-lib.inputs.nixpkgs.follows = "nixpkgs";
    nix-lib.inputs.flake-parts.follows = "flake-parts";
    nix-lib.inputs.flake-utils.follows = "flake-utils";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      flake-utils,
      flake-parts,
      nix-lib,
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
        in
        {
          devShells.default = pkgs.mkShell {
            buildInputs = [
              pythonEnv
              pkgs.gcloud
              pkgs.jq
            ];
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
        };
    };
}
