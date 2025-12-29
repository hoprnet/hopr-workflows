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
    echo "$GPG_PRIVATE_KEY" | gpg --batch --import

    # Generate hash and signature
    sha256sum "$input_file" > "$input_file.sha256"
    echo "Hash written to $input_file.sha256"
    gpg --armor --output "$input_file.asc" --detach-sign "$input_file"
    echo "Signature written to $input_file.asc"

    # Clean up
    rm -rf "$gnupghome"

}

checks() {
    local input_file="${1:-}"

    if [[ -z "${GPG_PRIVATE_KEY:-}" ]]; then
        echo "Error: GPG_PRIVATE_KEY environment variable is not set."
        exit 1
    fi

    if [[ -z "${input_file}" ]]; then
        echo "Usage: $0 <file-to-sign>"
        exit 1
    fi

    if [[ ! -f "${input_file}" ]]; then
        echo "Error: File '${input_file}' does not exist."
        exit 1
    fi

    if ! command -v gpg >/dev/null 2>&1; then
        echo "Error: gpg is not installed. Please install gpg to use this script."
        exit 1
    fi

}

# Main function
main() {
    local input_file="${1:-}"

    checks "$@"
    sign "$input_file"
}

# Run main function with all arguments
main "$@"
