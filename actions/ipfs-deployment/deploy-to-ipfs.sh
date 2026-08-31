#!/usr/bin/env bash

# IPFS Deployment (Pinata and/or Filebase) with Environment Support
# Usage: ./deploy-to-ipfs.sh <environment> <build_dir> <project_name> <timestamp> <branch> <commit_hash>
#
# Provider selection (from environment variables):
# - PINATA_JWT set                              -> deploy to Pinata
# - FILEBASE_ACCESS_KEY/SECRET_KEY/BUCKET set   -> deploy to Filebase (CAR upload)
# - both sets present                           -> deploy to Pinata, then pin the
#                                                  resulting CID on Filebase
#
# Optional: SCRIPTS_DIR to override the uploader script location,
#           UPLOAD_TIMEOUT_MS for the provider HTTP timeout.

set -euo pipefail

# Determine script directory and uploader script paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="${SCRIPTS_DIR:-$SCRIPT_DIR}"

# Cleanup trap for temp directory
cleanup() {
  if [ -n "${TEMP_DIR:-}" ] && [ -d "${TEMP_DIR:-}" ]; then
    rm -rf "$TEMP_DIR"
  fi
}
trap cleanup EXIT ERR

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Parse arguments
ENVIRONMENT=${1:-}
BUILD_DIR=${2:-}
PROJECT_NAME=${3:-}
TIMESTAMP=${4:-}
BRANCH=${5:-unknown}
COMMIT_HASH=${6:-unknown}

# Validate arguments
if [ -z "$ENVIRONMENT" ] || [ -z "$BUILD_DIR" ] || [ -z "$PROJECT_NAME" ] || [ -z "$TIMESTAMP" ]; then
  echo -e "${RED}❌ Usage: $0 <environment> <build_dir> <project_name> <timestamp> [branch] [commit_hash]${NC}"
  echo -e "${YELLOW}   environment: name slug (e.g. dev, prod, staging)${NC}"
  echo -e "${YELLOW}   build_dir: path to build directory${NC}"
  echo -e "${YELLOW}   project_name: name of the project${NC}"
  echo -e "${YELLOW}   timestamp: deployment timestamp${NC}"
  exit 1
fi

# environment is used as a path segment, so keep it a safe slug
if ! echo "$ENVIRONMENT" | grep -qE '^[a-zA-Z0-9_-]+$'; then
  echo -e "${RED}❌ Environment must match ^[a-zA-Z0-9_-]+\$ (got: $ENVIRONMENT)${NC}"
  exit 1
fi

# Check build directory exists
if [ ! -d "$BUILD_DIR" ]; then
  echo -e "${RED}❌ Build directory '$BUILD_DIR' not found${NC}"
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
    echo -e "${RED}❌ Partial Filebase configuration: FILEBASE_ACCESS_KEY, FILEBASE_SECRET_KEY and FILEBASE_BUCKET must all be set${NC}"
    exit 1
  fi
  FILEBASE_ENABLED=true
fi
if ! $PINATA_ENABLED && ! $FILEBASE_ENABLED; then
  echo -e "${RED}❌ No IPFS provider configured: set PINATA_JWT and/or FILEBASE_ACCESS_KEY+FILEBASE_SECRET_KEY+FILEBASE_BUCKET${NC}"
  exit 1
fi

# Configuration
DEPLOYMENTS_DIR="deployments"
DEPLOYMENT_FILE="${DEPLOYMENTS_DIR}/${ENVIRONMENT}/deployment-${TIMESTAMP}.json"
LOG_FILE="${DEPLOYMENTS_DIR}/logs/${ENVIRONMENT}-deployments.log"

# IPFS gateway bases — single source of truth for this deployment.
# The first entry is the primary gateway (the active provider's dedicated
# gateway) used for verification and as the canonical ipfs_url. Full URLs and
# metadata are derived from this list, and the workflow reads them back out of
# the deployment JSON (no duplication).
PINATA_GATEWAY="https://gnosis.mypinata.cloud/ipfs"
FILEBASE_GATEWAY="https://ipfs.filebase.io/ipfs"
IPFS_GATEWAYS=()
if $PINATA_ENABLED; then
  IPFS_GATEWAYS+=("$PINATA_GATEWAY")
fi
if $FILEBASE_ENABLED; then
  IPFS_GATEWAYS+=("$FILEBASE_GATEWAY")
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
$PINATA_ENABLED && PROVIDERS+=("pinata")
$FILEBASE_ENABLED && PROVIDERS+=("filebase")
PROVIDERS_LABEL=$(
  IFS=,
  echo "${PROVIDERS[*]}"
)

echo -e "${BLUE}🚀 Starting IPFS Deployment${NC}"
echo -e "${BLUE}===========================${NC}"
echo -e "Environment: ${YELLOW}${ENVIRONMENT}${NC}"
echo -e "Project: ${YELLOW}${PROJECT_NAME}${NC}"
echo -e "Providers: ${YELLOW}${PROVIDERS_LABEL}${NC}"
echo -e "Build Directory: ${YELLOW}${BUILD_DIR}${NC}"
echo -e "Branch: ${YELLOW}${BRANCH}${NC}"
echo -e "Commit: ${YELLOW}${COMMIT_HASH}${NC}"
echo -e "Timestamp: ${YELLOW}${TIMESTAMP}${NC}"
echo ""

# Run a Node uploader script, show its secret-filtered output, and leave the
# last stdout line (the machine-readable JSON) in RUN_JSON. Exits on failure.
RUN_JSON=""
run_node_json() {
  local script="$1"
  shift

  if [ ! -f "$script" ]; then
    echo -e "${RED}❌ Uploader script not found at: $script${NC}"
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
    echo -e "${RED}❌ $(basename "$script") failed (exit code: $exit_code)${NC}"
    echo ""
    echo "=== Error details (last 30 lines) ==="
    grep -v -i -E '(jwt|token|secret|password|auth|bearer|authorization)' "$output_file" | tail -n 30 || tail -n 30 "$output_file"
    echo "=== End of error details ==="
    echo ""

    # Check for specific error types and provide helpful messages
    if grep -qi "NO_SCOPES_FOUND\|scopes" "$output_file"; then
      echo -e "${YELLOW}💡 Tip: Your PINATA_JWT token is missing required scopes.${NC}"
      echo -e "${YELLOW}   Please ensure your Pinata API key has the 'pinFileToIPFS' scope enabled.${NC}"
      echo -e "${YELLOW}   Check your Pinata dashboard: https://app.pinata.cloud/developers/api-keys${NC}"
      echo ""
    elif grep -qi "SignatureDoesNotMatch\|InvalidAccessKeyId" "$output_file"; then
      echo -e "${YELLOW}💡 Tip: Filebase rejected the credentials. Check FILEBASE_ACCESS_KEY and FILEBASE_SECRET_KEY.${NC}"
      echo ""
    elif grep -qi "no 'cid' metadata" "$output_file"; then
      echo -e "${YELLOW}💡 Tip: The Filebase bucket must be on the IPFS storage network to import CAR files.${NC}"
      echo ""
    elif grep -qi "401\|Unauthorized\|403\|Forbidden" "$output_file"; then
      echo -e "${YELLOW}💡 Tip: Authentication failed. Please check the provider credentials.${NC}"
      echo ""
    elif grep -qi "timeout\|ETIMEDOUT" "$output_file"; then
      echo -e "${YELLOW}💡 Tip: Upload timed out. Try increasing the upload_timeout_ms input.${NC}"
      echo ""
    fi

    rm -f "$output_file"
    exit 1
  fi

  RUN_JSON=$(tail -n 1 "$output_file")
  rm -f "$output_file"
}

# Step 1: Create temporary directory and prepare files
echo -e "${YELLOW}📦 Preparing files for upload...${NC}"
TEMP_DIR=$(mktemp -d)

# Copy files and count in single operation
if ! cp -r "$BUILD_DIR"/* "$TEMP_DIR/" 2>/dev/null; then
  echo -e "${RED}❌ Failed to copy files from '$BUILD_DIR' to temporary directory${NC}"
  exit 1
fi

# Verify files were copied and count them
FILE_COUNT=$(find "$TEMP_DIR" -type f 2>/dev/null | wc -l)
if [ "$FILE_COUNT" -eq 0 ]; then
  echo -e "${RED}❌ Build directory '$BUILD_DIR' is empty or no files copied${NC}"
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

echo -e "${GREEN}✅ Files prepared in temporary directory (${FILE_COUNT} files)${NC}"

# Step 2: Upload to the primary provider
DEPLOY_NAME="${PROJECT_NAME}-${ENVIRONMENT}-${TIMESTAMP}"
IPFS_HASH=""
PINATA_URL=""
FILEBASE_URL=""
PINATA_RESPONSE_JSON=null
FILEBASE_RESPONSE_JSON=null

if $PINATA_ENABLED; then
  echo -e "${YELLOW}📤 Uploading directory to Pinata...${NC}"
  run_node_json "$SCRIPTS_DIR/upload-pinata.mjs" "$TEMP_DIR" "$DEPLOY_NAME"

  IPFS_HASH=$(echo "$RUN_JSON" | jq -r '.IpfsHash // empty' 2>/dev/null)
  if [ -z "$IPFS_HASH" ] || [ "$IPFS_HASH" = "null" ]; then
    echo -e "${RED}❌ Failed to parse IPFS hash from Pinata response${NC}"
    echo "Last line of upload output: $RUN_JSON"
    exit 1
  fi
  PINATA_RESPONSE_JSON=$(echo "$RUN_JSON" | jq . 2>/dev/null || echo "null")
  PINATA_URL="$(gateway_url "$PINATA_GATEWAY" "$IPFS_HASH")"
  echo -e "${GREEN}✅ Successfully uploaded to Pinata${NC}"
  echo -e "   IPFS Hash: ${YELLOW}${IPFS_HASH}${NC}"
else
  echo -e "${YELLOW}📤 Uploading directory to Filebase (CAR import)...${NC}"
  run_node_json "$SCRIPTS_DIR/upload-filebase.mjs" "$TEMP_DIR" "${DEPLOY_NAME}.car"

  IPFS_HASH=$(echo "$RUN_JSON" | jq -r '.cid // empty' 2>/dev/null)
  if [ -z "$IPFS_HASH" ] || [ "$IPFS_HASH" = "null" ]; then
    echo -e "${RED}❌ Failed to parse CID from Filebase response${NC}"
    echo "Last line of upload output: $RUN_JSON"
    exit 1
  fi
  FILEBASE_RESPONSE_JSON=$(echo "$RUN_JSON" | jq . 2>/dev/null || echo "null")
  echo -e "${GREEN}✅ Successfully uploaded to Filebase${NC}"
  echo -e "   IPFS Hash: ${YELLOW}${IPFS_HASH}${NC}"
fi

# Step 3: When both providers are configured, pin the Pinata CID on Filebase
# for redundancy. The pin is best-effort: pin-filebase.mjs fails the deploy
# only when Filebase rejects the request or reports the pin as failed.
if $PINATA_ENABLED && $FILEBASE_ENABLED; then
  echo -e "${YELLOW}📌 Pinning CID on Filebase for redundancy...${NC}"
  run_node_json "$SCRIPTS_DIR/pin-filebase.mjs" "$IPFS_HASH" "$DEPLOY_NAME"
  FILEBASE_RESPONSE_JSON=$(echo "$RUN_JSON" | jq . 2>/dev/null || echo "null")
fi
if $FILEBASE_ENABLED; then
  FILEBASE_URL="$(gateway_url "$FILEBASE_GATEWAY" "$IPFS_HASH")"
fi

# Step 4: Verify via the primary gateway (best-effort)
IPFS_URL="$(gateway_url "${IPFS_GATEWAYS[0]}" "$IPFS_HASH")"
echo -e "${YELLOW}🔍 Verifying deployment (primary gateway)...${NC}"
if curl -s --head --max-time 10 "$IPFS_URL" >/dev/null; then
  echo -e "${GREEN}✅ Content accessible via primary gateway${NC}"
else
  echo -e "${YELLOW}⚠️  Content not yet accessible via primary gateway (may take a moment)${NC}"
fi

# Step 5: Save deployment metadata
echo -e "${YELLOW}💾 Saving deployment metadata...${NC}"
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
  echo -e "${RED}❌ Failed to create valid deployment metadata JSON${NC}"
  exit 1
fi

cd "$(dirname "$DEPLOYMENT_FILE")"
ln -sf "$(basename "$DEPLOYMENT_FILE")" latest.json
cd - >/dev/null

echo "$(date -Iseconds) | $ENVIRONMENT | $IPFS_HASH | $PROVIDERS_LABEL | $BRANCH | $COMMIT_HASH" >>"$LOG_FILE"

echo -e "${GREEN}✅ Deployment metadata saved${NC}"

echo ""
echo -e "${GREEN}🎉 Deployment Complete!${NC}"
echo -e "📍 IPFS Hash: ${YELLOW}$IPFS_HASH${NC}"
echo -e "🗂️ Providers: ${YELLOW}$PROVIDERS_LABEL${NC}"
echo -e "🌿 Branch: ${YELLOW}$BRANCH${NC}"
echo -e "📝 Commit: ${YELLOW}$COMMIT_HASH${NC}"
