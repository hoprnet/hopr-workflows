# Setup Nix

This action sets up the runner to run in a Nix environment

## Usage

```bash
      - name: Setup Nix
        uses: ./actions/setup-nix
        with:
          cachix_cache_name: my-cache-name
          cachix_auth_token: "${{ secrets.CACHIX_AUTH_TOKEN }}"
          nix_path: "nixpkgs=channel:nixos-26.05"
```

## Requirements

None

## Inputs

- `cachix_cache_name`: Cachix cache name. Default value. GitHub repository name
- `cachix_auth_token`: Cachix authentication token
- `nix_path`: Nix path to use. Default value: "nixpkgs=channel:nixos-26.05"

## Outputs

None
