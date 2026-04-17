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
          gpg_private_key_password: ${{ secrets.GPG_PRIVATE_KEY_PASSWORD }}
          apple_certificate: ${{ secrets.APPLE_CERTIFICATE_DEVELOPER_P12_BASE64 }}
          apple_certificate_password: ${{ secrets.APPLE_CERTIFICATE_DEVELOPER_PASSWORD }}
```

## Requirements

None

## Inputs

- `path`: The filepath to sign
- `architecture`: Architecture of the file to sign (e.g. x86_64-linux, aarch64-linux, x86_64-darwin, etc.)
- `gpg_private_key`: (Optional) GPG private key for signing
- `gpg_private_key_password`: (Optional) GPG private key password
- `apple_certificate`: (Optional) Apple developer certificate p12 for signing in base64
- `apple_certificate_password`: (Optional) Apple developer certificate password

## Outputs

None
