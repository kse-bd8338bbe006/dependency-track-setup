#!/usr/bin/env bash
set -euo pipefail

# Upload SBOM to Dependency-Track
# Usage: ./upload-sbom.sh <project-path> <project-name> <project-version>
#
# Required environment variables:
#   DTRACK_URL     - Dependency-Track API URL (e.g. http://localhost:8081)
#   DTRACK_API_KEY - Dependency-Track API key

PROJECT_PATH="${1:?Usage: $0 <project-path> <project-name> <project-version>}"
PROJECT_NAME="${2:?Usage: $0 <project-path> <project-name> <project-version>}"
PROJECT_VERSION="${3:?Usage: $0 <project-path> <project-name> <project-version>}"

: "${DTRACK_URL:?DTRACK_URL is not set}"
: "${DTRACK_API_KEY:?DTRACK_API_KEY is not set}"

WORK_DIR=$(mktemp -d /tmp/sbom-XXXXXX)
SBOM_FILE="$WORK_DIR/sbom.json"
trap 'rm -rf "$WORK_DIR"' EXIT

echo "Generating SBOM for $PROJECT_PATH..."
trivy fs --format cyclonedx --output "$SBOM_FILE" "$PROJECT_PATH"

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
