# Publish rust docs

This action generates and publishes the rust docs in github pages

## Usage

```bash
      - name: Publish docs
        uses: hoprnet/hopr-workflows/actions/publish-rust-docs@publish-rust-docs-v1
        with:
          source_repo: ${{ github.repository }}
          source_branch: ${{ github.event.pull_request.head.ref || github.ref }}
          publish: true
          cachix_cache_name: my_nix_cache_name
          cachix_auth_token: ${{ secrets.CACHIX_AUTH_TOKEN }}
          command: `nix build -L .#docs`
```

## Requirements

- Requires the repository to use Nix environment. Requires the action [Setup Nix](../setup-nix/README.md) to be invoked previously.

## Inputs

- `source_repo`: Name of the source code repository
- `source_branch`: Name of the branch to checkout
- `publish`: Determines if the action should finishing publishing the docs.
- `cachix_cache_name`: Cachix cache name. Default value. Github repository name
- `cachix_auth_token`: Cachix authentication token
- `command`: Nix command to run the docs. Default value `nix build -L .#docs`
- `github_token`: Github token used to deploy in Github Pages

## Outputs

None
