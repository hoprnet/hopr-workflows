#!/usr/bin/env bash

# IPFS Deployment (Pinata and/or Filebase) with Environment Support
# Usage: ./deploy-to-ipfs.sh <environment> <build_dir> <project_name> <timestamp> <branch> <commit_hash>
#
# The build directory is packed once into a single-root CAR file (UnixFS,
# CIDv1), so the root CID is known before any provider is contacted and every
# provider serves the exact same CID.
#
# Provider selection (from environment variables):
# - PINATA_JWT set                              -> upload the CAR to Pinata
# - FILEBASE_ACCESS_KEY/SECRET_KEY/BUCKET set   -> upload the CAR to Filebase
# - both sets present                           -> upload the CAR to Filebase,
#                                                  then pin the CID on Pinata
#                                                  (pin-by-CID, no 2nd upload)
#
# Optional: SCRIPTS_DIR to override the uploader script location,
#           UPLOAD_TIMEOUT_MS for the provider HTTP timeout,
#           PIN_TIMEOUT_MS for how long to wait for the Pinata pin-by-CID.

set -euo pipefail

# Determine script directory and uploader script paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="${SCRIPTS_DIR:-$SCRIPT_DIR}"

# Cleanup trap for temp directory and CAR file
cleanup() {
  if [ -n "${TEMP_DIR:-}" ] && [ -d "${TEMP_DIR:-}" ]; then
    rm -rf "$TEMP_DIR"
  fi
  if [ -n "${CAR_FILE:-}" ] && [ -f "${CAR_FILE:-}" ]; then
    rm -f "$CAR_FILE"
  fi
}
trap cleanup EXIT ERR

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log_with_color() {
  local color="$1"
  shift
  printf '%b\n' "${color}$*${NC}"
}

log_info() {
  log_with_color "$BLUE" "$@"
}

log_warn() {
  log_with_color "$YELLOW" "$@"
}

log_error() {
  log_with_color "$RED" "$@" >&2
}

log_success() {
  log_with_color "$GREEN" "$@"
}

# Parse arguments
ENVIRONMENT=${1:-}
BUILD_DIR=${2:-}
PROJECT_NAME=${3:-}
TIMESTAMP=${4:-}
BRANCH=${5:-unknown}
COMMIT_HASH=${6:-unknown}

# Validate arguments
if [ -z "$ENVIRONMENT" ] || [ -z "$BUILD_DIR" ] || [ -z "$PROJECT_NAME" ] || [ -z "$TIMESTAMP" ]; then
  log_error "❌ Usage: $0 <environment> <build_dir> <project_name> <timestamp> [branch] [commit_hash]"
  log_warn "   environment: name slug (e.g. dev, prod, staging)"
  log_warn "   build_dir: path to build directory"
  log_warn "   project_name: name of the project"
  log_warn "   timestamp: deployment timestamp"
  exit 1
fi

# environment is used as a path segment, so keep it a safe slug
if ! echo "$ENVIRONMENT" | grep -qE '^[a-zA-Z0-9_-]+$'; then
  log_error "❌ Environment must match ^[a-zA-Z0-9_-]+\$ (got: $ENVIRONMENT)"
  exit 1
fi

# Check build directory exists
if [ ! -d "$BUILD_DIR" ]; then
  log_error "❌ Build directory '$BUILD_DIR' not found"
  exit 1
fi

# Provider detection — the workflow validates this too, but keep the checks
# here so the script fails safely when run outside the workflow.
PINATA_ENABLED=false
FILEBASE_ENABLED=false
if [ -n "${PINATA_JWT:-}" ]; then
  PINATA_ENABLED=true
fi
if [ -n "${FILEBASE_ACCESS_KEY:-}" ] || [ -n "${FILEBASE_SECRET_KEY:-}" ] || [ -n "${FILEBASE_BUCKET:-}" ]; then
  if [ -z "${FILEBASE_ACCESS_KEY:-}" ] || [ -z "${FILEBASE_SECRET_KEY:-}" ] || [ -z "${FILEBASE_BUCKET:-}" ]; then
    log_error "❌ Partial Filebase configuration: FILEBASE_ACCESS_KEY, FILEBASE_SECRET_KEY and FILEBASE_BUCKET must all be set"
    exit 1
  fi
  FILEBASE_ENABLED=true
fi
if ! $PINATA_ENABLED && ! $FILEBASE_ENABLED; then
  log_error "❌ No IPFS provider configured: set PINATA_JWT and/or FILEBASE_ACCESS_KEY+FILEBASE_SECRET_KEY+FILEBASE_BUCKET"
  exit 1
fi

# Configuration
DEPLOYMENTS_DIR="deployments"
DEPLOYMENT_FILE="${DEPLOYMENTS_DIR}/${ENVIRONMENT}/deployment-${TIMESTAMP}.json"
LOG_FILE="${DEPLOYMENTS_DIR}/logs/${ENVIRONMENT}-deployments.log"

# IPFS gateway bases — single source of truth for this deployment.
# The first entry is the primary gateway used for verification and as the
# canonical ipfs_url. Filebase comes first: it receives the full CAR and
# serves the CID immediately, while a Pinata pin-by-CID may still be
# propagating. Full URLs and metadata are derived from this list, and the
# workflow reads them back out of the deployment JSON (no duplication).
PINATA_GATEWAY="https://gnosis.mypinata.cloud/ipfs"
FILEBASE_GATEWAY="https://gnosis-vpn.myfilebase.com/ipfs"
IPFS_GATEWAYS=()
if $FILEBASE_ENABLED; then
  IPFS_GATEWAYS+=("$FILEBASE_GATEWAY")
fi
if $PINATA_ENABLED; then
  IPFS_GATEWAYS+=("$PINATA_GATEWAY")
fi
IPFS_GATEWAYS+=(
  "https://ipfs.io/ipfs"
  "https://dweb.link/ipfs"
)

# Build full "<base>/<hash>/" URL for a gateway base.
gateway_url() {
  printf '%s/%s/' "$1" "$2"
}

PROVIDERS=()
$FILEBASE_ENABLED && PROVIDERS+=("filebase")
$PINATA_ENABLED && PROVIDERS+=("pinata")
PROVIDERS_LABEL=$(
  IFS=,
  echo "${PROVIDERS[*]}"
)

log_info "🚀 Starting IPFS Deployment"
log_info "==========================="
log_info "Environment: ${YELLOW}${ENVIRONMENT}${BLUE}"
log_info "Project: ${YELLOW}${PROJECT_NAME}${BLUE}"
log_info "Providers: ${YELLOW}${PROVIDERS_LABEL}${BLUE}"
log_info "Build Directory: ${YELLOW}${BUILD_DIR}${BLUE}"
log_info "Branch: ${YELLOW}${BRANCH}${BLUE}"
log_info "Commit: ${YELLOW}${COMMIT_HASH}${BLUE}"
log_info "Timestamp: ${YELLOW}${TIMESTAMP}${BLUE}"
echo ""

# Run a Node uploader script, show its secret-filtered output, and leave the
# last stdout line (the machine-readable JSON) in RUN_JSON. Exits on failure.
RUN_JSON=""
run_node_json() {
  local script="$1"
  shift

  if [ ! -f "$script" ]; then
    log_error "❌ Uploader script not found at: $script"
    exit 1
  fi

  set +e
  local output_file
  output_file=$(mktemp)
  node "$script" "$@" >"$output_file" 2>&1
  local exit_code=$?
  set -euo pipefail

  # Always show the full output for debugging (filter sensitive info)
  echo ""
  echo "=== Output of $(basename "$script") ==="
  grep -v -i -E '(jwt|token|secret|password|auth|bearer|authorization)' "$output_file" || cat "$output_file"
  echo "=== End of output ==="
  echo ""

  if [ $exit_code -ne 0 ]; then
    log_error "❌ $(basename "$script") failed (exit code: $exit_code)"
    echo ""
    echo "=== Error details (last 30 lines) ==="
    grep -v -i -E '(jwt|token|secret|password|auth|bearer|authorization)' "$output_file" | tail -n 30 || tail -n 30 "$output_file"
    echo "=== End of error details ==="
    echo ""

    # Check for specific error types and provide helpful messages
    if grep -qi "org:files:write\|NO_SCOPES_FOUND\|scopes" "$output_file"; then
      log_warn "💡 Tip: Your PINATA_JWT token is missing required scopes."
      log_warn "   The v3 upload API needs a key with the 'org:files:write' scope"
      log_warn "   (pin-by-CID polling additionally needs 'org:files:read'),"
      log_warn "   and CAR uploads require a paid Pinata plan."
      log_warn "   Check your Pinata dashboard: https://app.pinata.cloud/developers/api-keys"
      echo ""
    elif grep -qi "terminal status" "$output_file"; then
      log_warn "💡 Tip: The Pinata pin-by-CID request failed permanently."
      log_warn "   'invalid_object' means the CID could not be retrieved as valid content,"
      log_warn "   'over_free_limit'/'over_max_size' point at Pinata plan limits, and"
      log_warn "   'expired'/'bad_host_node' mean the content was not retrievable in time."
      echo ""
    elif grep -qi "SignatureDoesNotMatch\|InvalidAccessKeyId" "$output_file"; then
      log_warn "💡 Tip: Filebase rejected the credentials. Check FILEBASE_ACCESS_KEY and FILEBASE_SECRET_KEY."
      echo ""
    elif grep -qi "no 'cid' metadata" "$output_file"; then
      log_warn "💡 Tip: The Filebase bucket must be on the IPFS storage network to import CAR files."
      echo ""
    elif grep -qi "401\|Unauthorized\|403\|Forbidden" "$output_file"; then
      log_warn "💡 Tip: Authentication failed. Please check the provider credentials."
      echo ""
    elif grep -qi "timeout\|ETIMEDOUT" "$output_file"; then
      log_warn "💡 Tip: Upload timed out. Try increasing the upload_timeout_ms input."
      echo ""
    fi

    rm -f "$output_file"
    exit 1
  fi

  RUN_JSON=$(tail -n 1 "$output_file")
  rm -f "$output_file"
}

# Step 1: Create temporary directory and prepare files
log_info "📦 Preparing files for upload..."
TEMP_DIR=$(mktemp -d)

# Copy files and count in single operation
if ! cp -r "$BUILD_DIR"/* "$TEMP_DIR/" 2>/dev/null; then
  log_error "❌ Failed to copy files from '$BUILD_DIR' to temporary directory"
  exit 1
fi

# Verify files were copied and count them
FILE_COUNT=$(find "$TEMP_DIR" -type f 2>/dev/null | wc -l)
if [ "$FILE_COUNT" -eq 0 ]; then
  log_error "❌ Build directory '$BUILD_DIR' is empty or no files copied"
  exit 1
fi

# Add deployment metadata file
jq -n \
  --arg project "$PROJECT_NAME" \
  --arg environment "$ENVIRONMENT" \
  --arg timestamp "$TIMESTAMP" \
  --arg branch "$BRANCH" \
  --arg commit "$COMMIT_HASH" \
  --arg deployed_at "$(date -Iseconds)" \
  '{
    project: $project,
    environment: $environment,
    timestamp: $timestamp,
    branch: $branch,
    commit: $commit,
    deployed_at: $deployed_at
  }' >"$TEMP_DIR/deployment-info.json"

log_success "✅ Files prepared in temporary directory (${FILE_COUNT} files)"

# Step 2: Pack the directory into a single-root CAR file. The root CID is
# computed locally, so it is known before any provider is contacted, and every
# provider that imports this CAR serves the same CID.
log_info "📦 Packing files into a CAR file..."
CAR_FILE=$(mktemp --suffix=.car)
run_node_json "$SCRIPTS_DIR/pack-car.mjs" "$TEMP_DIR" "$CAR_FILE"

IPFS_HASH=$(echo "$RUN_JSON" | jq -r '.root // empty' 2>/dev/null)
if [ -z "$IPFS_HASH" ] || [ "$IPFS_HASH" = "null" ]; then
  log_error "❌ Failed to parse root CID from CAR packing output"
  echo "Last line of packing output: $RUN_JSON"
  exit 1
fi
log_success "✅ CAR packed"
log_success "   IPFS Hash: ${YELLOW}${IPFS_HASH}${GREEN}"

# Step 3: Get the CAR to every configured provider. Filebase receives the
# full CAR first; when Pinata is configured alongside it, Pinata only pins the
# already-known CID (fetched from the IPFS network) instead of taking a second
# upload. With a single provider the CAR is uploaded to it directly. The
# uploader scripts verify that the provider imported exactly the local root CID.
DEPLOY_NAME="${PROJECT_NAME}-${ENVIRONMENT}-${TIMESTAMP}"
PINATA_URL=""
FILEBASE_URL=""
PINATA_RESPONSE_JSON=null
FILEBASE_RESPONSE_JSON=null

if $FILEBASE_ENABLED; then
  log_info "📤 Uploading CAR to Filebase..."
  run_node_json "$SCRIPTS_DIR/upload-filebase.mjs" "$CAR_FILE" "${DEPLOY_NAME}.car" "$IPFS_HASH"
  FILEBASE_RESPONSE_JSON=$(echo "$RUN_JSON" | jq . 2>/dev/null || echo "null")
  FILEBASE_URL="$(gateway_url "$FILEBASE_GATEWAY" "$IPFS_HASH")"
  log_success "✅ Successfully uploaded to Filebase"
fi

if $PINATA_ENABLED; then
  if $FILEBASE_ENABLED; then
    log_info "📌 Pinning CID on Pinata (content hosted by Filebase)..."
    run_node_json "$SCRIPTS_DIR/pin-pinata.mjs" "$IPFS_HASH" "$DEPLOY_NAME"
    if [ "$(echo "$RUN_JSON" | jq -r '.pinned // false' 2>/dev/null)" = "true" ]; then
      log_success "✅ Pinata pin confirmed"
    else
      log_warn "⚠️  Pinata pin still propagating — the request continues server-side"
    fi
  else
    log_info "📤 Uploading CAR to Pinata..."
    run_node_json "$SCRIPTS_DIR/upload-pinata.mjs" "$CAR_FILE" "$DEPLOY_NAME" "$IPFS_HASH"
    log_success "✅ Successfully uploaded to Pinata"
  fi
  PINATA_RESPONSE_JSON=$(echo "$RUN_JSON" | jq . 2>/dev/null || echo "null")
  PINATA_URL="$(gateway_url "$PINATA_GATEWAY" "$IPFS_HASH")"
fi

# Step 4: Verify via the primary gateway (best-effort). The primary is the
# Filebase gateway whenever Filebase is enabled — it holds the full upload,
# while a Pinata pin-by-CID may still be propagating.
IPFS_URL="$(gateway_url "${IPFS_GATEWAYS[0]}" "$IPFS_HASH")"
log_info "🔍 Verifying deployment (primary gateway)..."
if curl -s --head --max-time 10 "$IPFS_URL" >/dev/null; then
  log_success "✅ Content accessible via primary gateway"
else
  log_warn "⚠️  Content not yet accessible via primary gateway (may take a moment)"
fi

# Step 5: Save deployment metadata
log_info "💾 Saving deployment metadata..."
mkdir -p "$(dirname "$DEPLOYMENT_FILE")" "$(dirname "$LOG_FILE")"

# Sanitize project_name
SANITIZED_PROJECT_NAME=$(echo "$PROJECT_NAME" | tr -cd '[:alnum:]-_' | head -c 100)

# Derive the gateway URL list from IPFS_GATEWAYS (first entry = primary).
GATEWAY_URLS=()
for base in "${IPFS_GATEWAYS[@]}"; do
  GATEWAY_URLS+=("$(gateway_url "$base" "$IPFS_HASH")")
done
URLS_JSON=$(printf '%s\n' "${GATEWAY_URLS[@]}" | jq -R . | jq -s .)
PROVIDERS_JSON=$(printf '%s\n' "${PROVIDERS[@]}" | jq -R . | jq -s .)

jq -n \
  --arg project "$SANITIZED_PROJECT_NAME" \
  --arg environment "$ENVIRONMENT" \
  --arg ipfs_hash "$IPFS_HASH" \
  --arg timestamp "$TIMESTAMP" \
  --arg branch "$BRANCH" \
  --arg commit "$COMMIT_HASH" \
  --arg deployed_at "$(date -Iseconds)" \
  --argjson providers "$PROVIDERS_JSON" \
  --arg ipfs_url "$IPFS_URL" \
  --arg pinata_url "$PINATA_URL" \
  --arg filebase_url "$FILEBASE_URL" \
  --argjson pinata_response "$PINATA_RESPONSE_JSON" \
  --argjson filebase_response "$FILEBASE_RESPONSE_JSON" \
  --argjson urls "$URLS_JSON" \
  '{
    project: $project,
    environment: $environment,
    ipfs_hash: $ipfs_hash,
    timestamp: $timestamp,
    branch: $branch,
    commit: $commit,
    deployed_at: $deployed_at,
    providers: $providers,
    ipfs_url: $ipfs_url,
    pinata_url: (if $pinata_url == "" then null else $pinata_url end),
    filebase_url: (if $filebase_url == "" then null else $filebase_url end),
    pinata_response: $pinata_response,
    filebase_response: $filebase_response,
    urls: {
      ipfs: $urls
    }
  }' >"$DEPLOYMENT_FILE"

# Validate the created JSON file
if ! jq empty "$DEPLOYMENT_FILE" 2>/dev/null; then
  log_error "❌ Failed to create valid deployment metadata JSON"
  exit 1
fi

cd "$(dirname "$DEPLOYMENT_FILE")"
ln -sf "$(basename "$DEPLOYMENT_FILE")" latest.json
cd - >/dev/null

echo "$(date -Iseconds) | $ENVIRONMENT | $IPFS_HASH | $PROVIDERS_LABEL | $BRANCH | $COMMIT_HASH" >>"$LOG_FILE"

log_success "✅ Deployment metadata saved"

echo ""
log_success "🎉 Deployment Complete!"
log_success "📍 IPFS Hash: ${YELLOW}$IPFS_HASH${GREEN}"
log_success "🗂️ Providers: ${YELLOW}$PROVIDERS_LABEL${GREEN}"
log_success "🌿 Branch: ${YELLOW}$BRANCH${GREEN}"
log_success "📝 Commit: ${YELLOW}$COMMIT_HASH${GREEN}"
