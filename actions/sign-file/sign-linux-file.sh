#!/usr/bin/env bash
#
# Sign file
#

set -o errexit -o nounset -o pipefail

sign() {
    local input_file="${1:-}"
    echo "Signing file: ${input_file}"

    # Create isolated GPG keyring
    gnupghome="$(mktemp -d)"
    export GNUPGHOME="$gnupghome"

    local gpg_passphrase_opts=()
    if [[ -n "${GPG_PRIVATE_KEY_PASSWORD:-}" ]]; then
        gpg_passphrase_opts=(--pinentry-mode loopback --passphrase "$GPG_PRIVATE_KEY_PASSWORD")
    fi

    echo "$GPG_PRIVATE_KEY" | gpg --batch "${gpg_passphrase_opts[@]}" --import

    # Generate hash and signature
    sha256sum "$input_file" > "$input_file.sha256"
    echo "Hash written to $input_file.sha256"
    gpg --batch --armor --output "$input_file.asc" --detach-sign "${gpg_passphrase_opts[@]}" "$input_file"
    echo "Signature written to $input_file.asc"

    # Clean up
    rm -rf "$gnupghome"

}

checks() {
    local input_path="${1:-}"

    if [[ -z "${GPG_PRIVATE_KEY:-}" ]]; then
        echo "Error: GPG_PRIVATE_KEY environment variable is not set."
        exit 1
    fi

    if [[ -z "${input_path}" ]]; then
        echo "Usage: $0 <file-or-directory-to-sign>"
        exit 1
    fi

    if [[ ! -f "${input_path}" && ! -d "${input_path}" ]]; then
        echo "Error: '${input_path}' does not exist or is not a file/directory."
        exit 1
    fi

}

packages() {
    if ! command -v gpg &> /dev/null; then
        echo "gpg could not be found, installing..."
        sudo apt-get update
        sudo apt-get install -y gpg
    else
        echo "gpg is already installed"
    fi
}


# Main function
main() {
    local input_path="${1:-}"

    checks "$@"
    packages

    if [[ -d "${input_path}" ]]; then
        for file in "${input_path}"/*; do
            sign "$file"
        done
    else
        sign "$input_path"
    fi
}

# Run main function with all arguments
main "$@"
