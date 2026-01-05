# Sign File

This action creates a GPG signature and SHA for the given file.
Creates file `${input.file}.asc` and `${input.file}.sha256`.

## Usage

```bash
      - name: Sign binary
        uses: hoprnet/hopr-workflows/actions/sign-file@sign-file-v1
        with:
          file: ./binary-file
          gpg_private_key: ${{ secrets.MY_GPG_PRIVATE_KEY }}

```

## Requirements

None

## Inputs

- `file`: The filepath to sign
- `gpg_private_key`: GPG private key for signing

## Outputs

None
