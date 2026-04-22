#!/usr/bin/env bash
#
# Sign file
#

set -o errexit -o nounset -o pipefail

CERT_ID=""

sign() {
  local input_file="${1:-}"
  echo "Signing file: ${input_file} with certificate ID ${CERT_ID}"

  codesign --sign "${CERT_ID}" --options runtime --timestamp "$input_file"

  echo "Verifying signature for file $input_file"
  codesign --verify --deep --strict --verbose=4 "$input_file"

  shasum -a 256 "$input_file" >"${input_file}.sha256"
  echo "Hash written to $input_file.sha256"

}

checks() {
  local input_path="${1:-}"

  if [[ -z ${APPLE_CERTIFICATE:-} ]]; then
    echo "Error: APPLE_CERTIFICATE environment variable is not set."
    exit 1
  fi

  if [[ -z ${APPLE_CERTIFICATE_PASSWORD:-} ]]; then
    echo "Error: APPLE_CERTIFICATE_PASSWORD environment variable is not set."
    exit 1
  fi

  if [[ -z ${input_path} ]]; then
    echo "Usage: $0 <file-or-directory-to-sign>"
    exit 1
  fi

  if [[ ! -f ${input_path} && ! -d ${input_path} ]]; then
    echo "Error: '${input_path}' does not exist or is not a file/directory."
    exit 1
  fi

}

cleanup() {
  echo "Cleaning up keychain and certificate..."
  security delete-keychain build.keychain 2>/dev/null || true
  rm -f gnosisvpn-developer.p12
}

setup() {
  trap cleanup EXIT
  echo "${APPLE_CERTIFICATE}" | base64 --decode >gnosisvpn-developer.p12
  KEYCHAIN_PASSWORD=$(openssl rand -base64 24)
  security create-keychain -p "${KEYCHAIN_PASSWORD}" build.keychain
  security default-keychain -s build.keychain
  security set-keychain-settings -lut 21600 build.keychain
  security unlock-keychain -p "${KEYCHAIN_PASSWORD}" build.keychain
  security list-keychains -d user -s build.keychain
  security import gnosisvpn-developer.p12 -k build.keychain -P "${APPLE_CERTIFICATE_PASSWORD}" -T /usr/bin/codesign
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "${KEYCHAIN_PASSWORD}" build.keychain
  security find-identity -v -p codesigning build.keychain
  CERT_ID=$(security find-identity -v -p codesigning build.keychain | awk '/[0-9A-F]{40}/ {print $2; exit}')
}

# Main function
main() {
  local input_path="${1:-}"

  checks "$@"
  setup

  if [[ -d ${input_path} ]]; then
    for file in "${input_path}"/*; do
      sign "$file"
    done
  else
    sign "$input_path"
  fi
}

# Run main function with all arguments
main "$@"
