#!/usr/bin/env bash
set -euo pipefail

# Check Dependency-Track policy violations for a project.
# Exits with code 1 if FAIL-level violations exist (for CI/CD gating).
#
# Usage: ./scripts/check-policy-violations.sh <project-name> <project-version> [--wait <seconds>]
#
# Required environment variables:
#   DTRACK_URL     - Dependency-Track API URL (e.g. http://localhost:8081)
#   DTRACK_API_KEY - Dependency-Track API key
#
# Exit codes:
#   0 - No FAIL violations (build approved)
#   1 - FAIL violations found (build blocked)
#   2 - Project not found or API error

PROJECT_NAME="${1:?Usage: $0 <project-name> <project-version> [--wait <seconds>]}"
PROJECT_VERSION="${2:?Usage: $0 <project-name> <project-version> [--wait <seconds>]}"
shift 2

WAIT_SECONDS=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --wait) WAIT_SECONDS="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

: "${DTRACK_URL:?DTRACK_URL is not set}"
: "${DTRACK_API_KEY:?DTRACK_API_KEY is not set}"

api() {
  curl -s "$DTRACK_URL/api/v1/$1" \
    -H "X-Api-Key: $DTRACK_API_KEY" \
    -H "Content-Type: application/json"
}

echo "=== Policy Violation Check ==="
echo "Project: $PROJECT_NAME:$PROJECT_VERSION"
echo "Server:  $DTRACK_URL"
echo ""

# Wait for analysis to complete if requested
if [ "$WAIT_SECONDS" -gt 0 ]; then
  echo "Waiting ${WAIT_SECONDS}s for analysis to complete..."
  sleep "$WAIT_SECONDS"
fi

# Get project UUID
PROJECT_RESPONSE=$(api "project?name=$PROJECT_NAME&version=$PROJECT_VERSION")
PROJECT_UUID=$(echo "$PROJECT_RESPONSE" | python3 -c "
import sys, json
try:
    projects = json.load(sys.stdin)
    if isinstance(projects, list) and len(projects) > 0:
        print(projects[0]['uuid'])
    else:
        print('')
except:
    print('')
" 2>/dev/null)

if [ -z "$PROJECT_UUID" ]; then
  echo "ERROR: Project '$PROJECT_NAME:$PROJECT_VERSION' not found" >&2
  exit 2
fi

# Fetch violations
VIOLATIONS=$(api "violation/project/$PROJECT_UUID")

# Parse and categorize violations
RESULT=$(echo "$VIOLATIONS" | python3 -c "
import sys, json

try:
    violations = json.load(sys.stdin)
except:
    violations = []

if not isinstance(violations, list):
    violations = []

fails = []
warns = []
infos = []

for v in violations:
    state = v.get('policyCondition', {}).get('policy', {}).get('violationState', 'UNKNOWN')
    entry = {
        'component': v.get('component', {}).get('name', 'unknown'),
        'version': v.get('component', {}).get('version', '?'),
        'policy': v.get('policyCondition', {}).get('policy', {}).get('name', 'unknown'),
        'type': v.get('type', 'UNKNOWN'),
        'subject': v.get('policyCondition', {}).get('subject', ''),
        'value': v.get('policyCondition', {}).get('value', ''),
        'state': state
    }
    if state == 'FAIL':
        fails.append(entry)
    elif state == 'WARN':
        warns.append(entry)
    else:
        infos.append(entry)

print(json.dumps({'fails': fails, 'warns': warns, 'infos': infos}))
")

FAIL_COUNT=$(echo "$RESULT" | python3 -c "import sys,json; print(len(json.load(sys.stdin)['fails']))")
WARN_COUNT=$(echo "$RESULT" | python3 -c "import sys,json; print(len(json.load(sys.stdin)['warns']))")
INFO_COUNT=$(echo "$RESULT" | python3 -c "import sys,json; print(len(json.load(sys.stdin)['infos']))")

# Print results
if [ "$FAIL_COUNT" -gt 0 ]; then
  echo "FAIL violations ($FAIL_COUNT):"
  echo "$RESULT" | python3 -c "
import sys, json
for v in json.load(sys.stdin)['fails']:
    print(f\"  BLOCKED  {v['component']}@{v['version']}\")
    print(f\"           Policy: {v['policy']}\")
    print(f\"           Reason: {v['subject']} {v['value']}\")
    print()
"
fi

if [ "$WARN_COUNT" -gt 0 ]; then
  echo "WARN violations ($WARN_COUNT):"
  echo "$RESULT" | python3 -c "
import sys, json
for v in json.load(sys.stdin)['warns']:
    print(f\"  WARNING  {v['component']}@{v['version']}\")
    print(f\"           Policy: {v['policy']}\")
    print(f\"           Reason: {v['subject']} {v['value']}\")
    print()
"
fi

if [ "$INFO_COUNT" -gt 0 ]; then
  echo "INFO violations ($INFO_COUNT):"
  echo "$RESULT" | python3 -c "
import sys, json
for v in json.load(sys.stdin)['infos']:
    print(f\"  INFO     {v['component']}@{v['version']} — {v['policy']}\")
"
  echo ""
fi

# Summary
echo "=== Summary ==="
echo "FAIL: $FAIL_COUNT | WARN: $WARN_COUNT | INFO: $INFO_COUNT"
echo ""

if [ "$FAIL_COUNT" -gt 0 ]; then
  echo "BUILD BLOCKED: $FAIL_COUNT policy violation(s) with FAIL state."
  echo ""
  echo "To review violations:"
  echo "  $DTRACK_URL/projects/$PROJECT_UUID"
  exit 1
else
  echo "BUILD APPROVED: No FAIL-level policy violations."
  exit 0
fi
