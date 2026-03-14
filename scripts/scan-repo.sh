#!/usr/bin/env bash
set -euo pipefail

# Clone a git repository, generate SBOM with Trivy, and upload to Dependency-Track
# Usage: ./scan-repo.sh <git-repo-url> [project-name] [project-version]
#
# Required environment variables:
#   DTRACK_URL     - Dependency-Track API URL (e.g. http://localhost:8081)
#   DTRACK_API_KEY - Dependency-Track API key

REPO_URL="${1:?Usage: $0 <git-repo-url> [project-name] [project-version]}"
REPO_NAME=$(basename "$REPO_URL" .git)
PROJECT_NAME="${2:-$REPO_NAME}"
PROJECT_VERSION="${3:-main}"

: "${DTRACK_URL:?DTRACK_URL is not set}"
: "${DTRACK_API_KEY:?DTRACK_API_KEY is not set}"

WORK_DIR=$(mktemp -d /tmp/scan-repo-XXXXXX)
SBOM_FILE="$WORK_DIR/sbom.json"
trap 'rm -rf "$WORK_DIR"' EXIT

echo "Cloning $REPO_URL..."
git clone --depth 1 "$REPO_URL" "$WORK_DIR/repo" 2>&1

# Install dependencies to resolve full dependency tree
echo "Installing dependencies..."
find "$WORK_DIR/repo" -name "package.json" -not -path "*/node_modules/*" -execdir npm install --ignore-scripts --legacy-peer-deps 2>&1 \;
find "$WORK_DIR/repo" -name "requirements.txt" -execdir pip install -r requirements.txt --target=.venv 2>/dev/null \;

echo "Generating SBOM for $PROJECT_NAME..."
trivy fs --format cyclonedx --include-dev-deps --output "$SBOM_FILE" "$WORK_DIR/repo"

echo "Uploading SBOM to $DTRACK_URL for project $PROJECT_NAME:$PROJECT_VERSION..."
PAYLOAD_FILE="$WORK_DIR/payload.json"
python3 -c "
import json, sys, base64
with open(sys.argv[1], 'rb') as f:
    bom_b64 = base64.b64encode(f.read()).decode()
payload = {
    'projectName': sys.argv[2],
    'projectVersion': sys.argv[3],
    'autoCreate': True,
    'bom': bom_b64
}
with open(sys.argv[4], 'w') as f:
    json.dump(payload, f)
" "$SBOM_FILE" "$PROJECT_NAME" "$PROJECT_VERSION" "$PAYLOAD_FILE"

RESPONSE=$(curl -s -w "\n%{http_code}" -X PUT "$DTRACK_URL/api/v1/bom" \
  -H "X-Api-Key: $DTRACK_API_KEY" \
  -H "Content-Type: application/json" \
  -d @"$PAYLOAD_FILE")

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | head -1)

if [ "$HTTP_CODE" -eq 200 ]; then
  echo "Upload successful. Processing token: $BODY"
else
  echo "Upload failed (HTTP $HTTP_CODE): $BODY" >&2
  exit 1
fi
