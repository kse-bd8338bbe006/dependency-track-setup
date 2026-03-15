#!/usr/bin/env bash
set -euo pipefail

# Sync policies from policies/policies.json to Dependency-Track
# Usage: ./scripts/sync-policies.sh [--dry-run]
#
# Required environment variables:
#   DTRACK_URL     - Dependency-Track API URL (e.g. http://localhost:8081)
#   DTRACK_API_KEY - Dependency-Track API key

: "${DTRACK_URL:?DTRACK_URL is not set}"
: "${DTRACK_API_KEY:?DTRACK_API_KEY is not set}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
POLICIES_FILE="${SCRIPT_DIR}/../policies/policies.json"
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [ ! -f "$POLICIES_FILE" ]; then
  echo "Policy file not found: $POLICIES_FILE" >&2
  exit 1
fi

api() {
  local method="$1" path="$2"
  shift 2
  curl -s -X "$method" "$DTRACK_URL/api/v1/$path" \
    -H "X-Api-Key: $DTRACK_API_KEY" \
    -H "Content-Type: application/json" \
    "$@"
}

echo "=== Dependency-Track Policy Sync ==="
echo "Source: $POLICIES_FILE"
echo "Target: $DTRACK_URL"
$DRY_RUN && echo "Mode: DRY RUN (no changes will be made)"
echo ""

# Fetch existing policies
EXISTING=$(api GET "policy")

# Process each desired policy
DESIRED_COUNT=$(python3 -c "import json; print(len(json.load(open('$POLICIES_FILE'))))")
CREATED=0
UPDATED=0
SKIPPED=0

for i in $(seq 0 $((DESIRED_COUNT - 1))); do
  POLICY_JSON=$(python3 -c "
import json
policies = json.load(open('$POLICIES_FILE'))
p = policies[$i]
print(json.dumps(p))
")

  POLICY_NAME=$(echo "$POLICY_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['name'])")
  POLICY_OPERATOR=$(echo "$POLICY_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['operator'])")
  POLICY_STATE=$(echo "$POLICY_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['violationState'])")

  # Check if policy already exists
  EXISTING_UUID=$(echo "$EXISTING" | python3 -c "
import sys, json
policies = json.load(sys.stdin)
for p in policies:
    if p['name'] == '$POLICY_NAME':
        print(p['uuid'])
        break
else:
    print('')
" 2>/dev/null || echo "")

  if [ -n "$EXISTING_UUID" ]; then
    # Policy exists — check if it needs updating
    EXISTING_POLICY=$(echo "$EXISTING" | python3 -c "
import sys, json
policies = json.load(sys.stdin)
for p in policies:
    if p['uuid'] == '$EXISTING_UUID':
        print(json.dumps(p))
        break
")
    NEEDS_UPDATE=$(echo "$EXISTING_POLICY" | python3 -c "
import sys, json
p = json.load(sys.stdin)
needs = False
if p['operator'] != '$POLICY_OPERATOR': needs = True
if p['violationState'] != '$POLICY_STATE': needs = True
print('true' if needs else 'false')
")

    if [ "$NEEDS_UPDATE" = "true" ]; then
      echo "[UPDATE] $POLICY_NAME (operator=$POLICY_OPERATOR, state=$POLICY_STATE)"
      if ! $DRY_RUN; then
        api POST "policy" -d "$(echo "$EXISTING_POLICY" | python3 -c "
import sys, json
p = json.load(sys.stdin)
p['operator'] = '$POLICY_OPERATOR'
p['violationState'] = '$POLICY_STATE'
print(json.dumps(p))
")"
      fi
      UPDATED=$((UPDATED + 1))
    else
      echo "[OK]     $POLICY_NAME (no changes)"
      SKIPPED=$((SKIPPED + 1))
    fi

    POLICY_UUID="$EXISTING_UUID"
  else
    # Create new policy
    echo "[CREATE] $POLICY_NAME (operator=$POLICY_OPERATOR, state=$POLICY_STATE)"
    if ! $DRY_RUN; then
      RESULT=$(api PUT "policy" -d "{
        \"name\": \"$POLICY_NAME\",
        \"operator\": \"$POLICY_OPERATOR\",
        \"violationState\": \"$POLICY_STATE\"
      }")
      POLICY_UUID=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin)['uuid'])")
    else
      POLICY_UUID="dry-run"
    fi
    CREATED=$((CREATED + 1))
  fi

  # Sync conditions
  if ! $DRY_RUN && [ "$POLICY_UUID" != "dry-run" ]; then
    # Get existing conditions for this policy
    EXISTING_CONDITIONS=$(api GET "policy" | python3 -c "
import sys, json
policies = json.load(sys.stdin)
for p in policies:
    if p['uuid'] == '$POLICY_UUID':
        print(json.dumps(p.get('policyConditions', [])))
        break
else:
    print('[]')
")

    # Get desired conditions
    DESIRED_CONDITIONS=$(echo "$POLICY_JSON" | python3 -c "
import sys, json
print(json.dumps(json.load(sys.stdin).get('conditions', [])))
")

    # Delete conditions not in desired state
    echo "$EXISTING_CONDITIONS" | python3 -c "
import sys, json
existing = json.load(sys.stdin)
desired = json.loads('$(echo "$DESIRED_CONDITIONS" | sed "s/'/\\\\'/g")')

for ec in existing:
    found = False
    for dc in desired:
        if ec['subject'] == dc['subject'] and ec['operator'] == dc['operator'] and ec['value'] == dc['value']:
            found = True
            break
    if not found:
        print(ec['uuid'])
" 2>/dev/null | while read -r COND_UUID; do
      if [ -n "$COND_UUID" ]; then
        echo "  [DELETE CONDITION] $COND_UUID"
        api DELETE "policy/condition/$COND_UUID" > /dev/null
      fi
    done

    # Add conditions not yet present
    echo "$DESIRED_CONDITIONS" | python3 -c "
import sys, json
desired = json.load(sys.stdin)
existing = json.loads('$(echo "$EXISTING_CONDITIONS" | sed "s/'/\\\\'/g")')

for dc in desired:
    found = False
    for ec in existing:
        if ec['subject'] == dc['subject'] and ec['operator'] == dc['operator'] and ec['value'] == dc['value']:
            found = True
            break
    if not found:
        print(json.dumps(dc))
" 2>/dev/null | while read -r COND_JSON; do
      if [ -n "$COND_JSON" ]; then
        SUBJ=$(echo "$COND_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['subject'])")
        VAL=$(echo "$COND_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['value'])")
        echo "  [ADD CONDITION] $SUBJ = $VAL"
        api PUT "policy/$POLICY_UUID/condition" -d "$COND_JSON" > /dev/null
      fi
    done
  elif $DRY_RUN; then
    COND_COUNT=$(echo "$POLICY_JSON" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('conditions',[])))")
    echo "  [DRY RUN] Would sync $COND_COUNT condition(s)"
  fi
done

echo ""
echo "=== Summary ==="
echo "Created: $CREATED"
echo "Updated: $UPDATED"
echo "Unchanged: $SKIPPED"
echo "Total: $DESIRED_COUNT"
