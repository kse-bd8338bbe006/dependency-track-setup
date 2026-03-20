#!/usr/bin/env bash
set -euo pipefail

# Force vulnerability re-analysis for all projects (or a specific one)
# Usage: ./scripts/force-vuln-analysis.sh [project-name] [project-version]
#
# Required environment variables:
#   DTRACK_URL     - Dependency-Track API URL (e.g. http://localhost:8081)
#   DTRACK_API_KEY - Dependency-Track API key

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$SCRIPT_DIR/../.env" ]; then
  set -a
  source "$SCRIPT_DIR/../.env"
  set +a
fi

: "${DTRACK_URL:?DTRACK_URL is not set}"
: "${DTRACK_API_KEY:?DTRACK_API_KEY is not set}"

PROJECT_NAME="${1:-}"
PROJECT_VERSION="${2:-}"

api() {
  curl -s "$DTRACK_URL/api/v1/$1" \
    -H "X-Api-Key: $DTRACK_API_KEY" \
    -H "Content-Type: application/json" \
    "${@:2}"
}

echo "=== Force Vulnerability Analysis ==="
echo "Server: $DTRACK_URL"
echo ""

if [ -n "$PROJECT_NAME" ] && [ -n "$PROJECT_VERSION" ]; then
  # Analyze specific project
  UUID=$(api "project?name=$PROJECT_NAME&version=$PROJECT_VERSION" | \
    python3 -c "import sys,json; ps=json.load(sys.stdin); print(ps[0]['uuid'] if ps else '')" 2>/dev/null)

  if [ -z "$UUID" ]; then
    echo "ERROR: Project '$PROJECT_NAME:$PROJECT_VERSION' not found" >&2
    exit 1
  fi

  echo "Analyzing: $PROJECT_NAME:$PROJECT_VERSION ($UUID)"
  RESULT=$(api "finding/project/$UUID/analyze" -X POST -w "\n%{http_code}")
  HTTP_CODE=$(echo "$RESULT" | tail -1)
  echo "  → HTTP $HTTP_CODE"
else
  # Analyze all projects
  PROJECTS=$(api "project?limit=500&excludeInactive=true")
  COUNT=$(echo "$PROJECTS" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))")
  echo "Found $COUNT projects. Triggering analysis for each..."
  echo ""

  echo "$PROJECTS" | python3 -c "
import sys, json
for p in json.load(sys.stdin):
    print(f'{p[\"uuid\"]}|{p[\"name\"]}|{p.get(\"version\",\"?\")}')
" | while IFS='|' read -r UUID NAME VERSION; do
    echo -n "  $NAME:$VERSION ... "
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
      "$DTRACK_URL/api/v1/finding/project/$UUID/analyze" \
      -H "X-Api-Key: $DTRACK_API_KEY")
    echo "HTTP $HTTP_CODE"
    # Small delay to avoid overwhelming the server
    sleep 1
  done
fi

echo ""
echo "Done. Analysis runs asynchronously — check DT UI for results."
