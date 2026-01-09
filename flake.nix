{
  description = "Hopr Workflows flake";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
  inputs.flake-utils.url = "github:numtide/flake-utils";

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        pythonEnv = pkgs.python312.withPackages (ps: with ps; [
          google-cloud-artifact-registry
          google-auth
        ]);
      in {
        devShell = pkgs.mkShell {
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
      }
    );
}