#!/usr/bin/env bash
set -euo pipefail

# Build a Docker image from a Dockerfile, generate SBOM with Trivy or Syft, and upload to Dependency-Track
# Usage: ./scan-image.sh <path-to-dockerfile-dir> <project-name> [project-version] [--generator syft|trivy]
#
# The script builds the image, scans the resulting image (not just the source), and uploads
# the SBOM. This captures OS-level packages, system libraries, and application dependencies
# installed during the Docker build — vulnerabilities that a source-only scan would miss.
#
# Required environment variables:
#   DTRACK_URL     - Dependency-Track API URL (e.g. http://localhost:8081)
#   DTRACK_API_KEY - Dependency-Track API key

DOCKERFILE_DIR="${1:?Usage: $0 <path-to-dockerfile-dir> <project-name> [project-version] [--generator syft|trivy]}"
PROJECT_NAME="${2:?Usage: $0 <path-to-dockerfile-dir> <project-name> [project-version] [--generator syft|trivy]}"
PROJECT_VERSION="${3:-latest}"
shift $(( $# < 3 ? $# : 3 ))

GENERATOR="trivy"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --generator) GENERATOR="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

: "${DTRACK_URL:?DTRACK_URL is not set}"
: "${DTRACK_API_KEY:?DTRACK_API_KEY is not set}"

WORK_DIR=$(mktemp -d /tmp/scan-image-XXXXXX)
SBOM_FILE="$WORK_DIR/sbom.json"
IMAGE_TAG="dtrack-scan/${PROJECT_NAME}:${PROJECT_VERSION}"

cleanup() {
  rm -rf "$WORK_DIR"
  docker rmi "$IMAGE_TAG" 2>/dev/null || true
}
trap cleanup EXIT

# Build the Docker image
echo "Building Docker image from $DOCKERFILE_DIR..."
docker build -t "$IMAGE_TAG" "$DOCKERFILE_DIR"

# Generate SBOM from the built image
echo "Generating SBOM for image $IMAGE_TAG using $GENERATOR..."
case "$GENERATOR" in
  trivy)
    trivy image --format cyclonedx --output "$SBOM_FILE" "$IMAGE_TAG"
    ;;
  syft)
    syft packages "$IMAGE_TAG" -o cyclonedx-json="$SBOM_FILE"
    ;;
  *)
    echo "Unknown generator: $GENERATOR (use trivy or syft)" >&2
    exit 1
    ;;
esac

# Build JSON payload using python to avoid argument length limits
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
