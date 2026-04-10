# Sign File

This action creates a GPG signature and SHA for the given file.
Creates file `${input.file}.asc` and `${input.file}.sha256`.

## Usage

```bash
      - name: Sign binary
        uses: hoprnet/hopr-workflows/actions/sign-file@sign-file-v2
        with:
          path: ./binary-file
          gpg_private_key: ${{ secrets.MY_GPG_PRIVATE_KEY }}

```

## Requirements

None

## Inputs

- `path`: The filepath to sign
- `architecture`: Architecture of the file to sign (e.g. x86_64-linux, aarch64-linux, x86_64-darwin, etc.)
- `gpg_private_key`: GPG private key for signing
- `apple_certificate`: Apple developer certificate p12 for signing in base64
- `apple_certificate_password`: Apple developer certificate password

## Outputs

None
