# Setup Nix

This action setup the runner to run in a Nix environment

## Usage

```bash
      - name: Setup Nix
        uses: hoprnet/hopr-workflows/actions/setup-nix@setup-nix-v1
        with:
          cachix_cache_name: my-cache-name
          cachix_auth_token: "${{ secrets.CACHIX_AUTH_TOKEN }}"
          nix_path: "nixpkgs=channel:nixos-24.05"
```

## Requirements

None

## Inputs

- `cachix_cache_name`: Cachix cache name. Default value. Github repository name
- `cachix_auth_token`: Cachix authentication token
- `nix_path`: Nix path to use. Default value: "nixpkgs=channel:nixos-24.05"

## Outputs

None
