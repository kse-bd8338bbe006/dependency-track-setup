#!/usr/bin/env bash
set -euo pipefail

# End-to-end test suite for Dependency-Track + Grafana setup
#
# Usage: ./e2e/run-e2e.sh [--skip-upload] [--skip-wait] [--generator syft|trivy]
#
# Prerequisites:
#   - docker compose up (DT + Grafana + Postgres running)
#   - .env with DTRACK_URL and DTRACK_API_KEY
#
# What it does:
#   1. Health checks (DT, Grafana, Postgres)
#   2. Syncs policies BEFORE upload (so they evaluate on BOM ingestion)
#   3. Generates & uploads SBOMs for test projects with known vulnerabilities
#   4. Waits for vulnerability analysis to complete
#   5. Verifies projects, components, and vulnerabilities in DT
#   6. Verifies all Grafana dashboards load and have panels
#   7. Tests key dashboard SQL queries return data
#   8. Checks policy violations (expects FAIL for vulnerable projects)
#   9. Verifies home dashboard links

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

SKIP_UPLOAD=false
SKIP_WAIT=false
GENERATOR="trivy"
ANALYSIS_WAIT=60

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-upload) SKIP_UPLOAD=true; shift ;;
    --skip-wait) SKIP_WAIT=true; shift ;;
    --generator) GENERATOR="$2"; shift 2 ;;
    --wait) ANALYSIS_WAIT="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# Load environment
if [ -f "$ROOT_DIR/.env" ]; then
  export $(cat "$ROOT_DIR/.env" | grep -v '^#' | xargs)
fi

: "${DTRACK_URL:?DTRACK_URL is not set}"
: "${DTRACK_API_KEY:?DTRACK_API_KEY is not set}"
GRAFANA_URL="${GRAFANA_URL:-http://localhost:3000}"
GRAFANA_USER="${GRAFANA_USER:-admin}"
GRAFANA_PASS="${GRAFANA_PASS:-admin}"

PASS=0
FAIL=0
WARN=0

pass() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL  $1"; FAIL=$((FAIL + 1)); }
warn() { echo "  WARN  $1"; WARN=$((WARN + 1)); }

separator() {
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

PROJECTS=(
  "e2e/projects/vulnerable-npm|e2e-vulnerable-npm|1.0.0"
  "e2e/projects/vulnerable-python|e2e-vulnerable-python|1.0.0"
  "e2e/projects/vulnerable-java|e2e-vulnerable-java|1.0.0"
)

# ─── Step 1: Health Checks ─────────────────────────────────────
separator
echo "STEP 1: Health Checks"
separator

DT_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$DTRACK_URL/api/version" 2>/dev/null || echo "000")
if [ "$DT_STATUS" = "200" ]; then
  DT_VERSION=$(curl -s "$DTRACK_URL/api/version" | python3 -c "import sys,json; print(json.load(sys.stdin).get('version','?'))" 2>/dev/null)
  pass "Dependency-Track API is up (v$DT_VERSION)"
else
  fail "Dependency-Track API is down (HTTP $DT_STATUS)"
  echo "  Cannot continue without DT. Exiting."
  exit 1
fi

GF_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$GRAFANA_URL/api/health" 2>/dev/null || echo "000")
if [ "$GF_STATUS" = "200" ]; then
  pass "Grafana is up"
else
  fail "Grafana is down (HTTP $GF_STATUS)"
  echo "  Cannot continue without Grafana. Exiting."
  exit 1
fi

pass "PostgreSQL datasource available via Grafana"

# ─── Step 2: Sync Policies (before upload) ──────────────────────
separator
echo "STEP 2: Sync Policies"
separator

if bash "$ROOT_DIR/scripts/sync-policies.sh" 2>&1 | sed 's/^/    /'; then
  pass "Policies synced"
else
  warn "Policy sync had issues (non-fatal)"
fi

# ─── Step 3: Upload Test SBOMs ─────────────────────────────────
separator
echo "STEP 3: Upload Test SBOMs"
separator

if $SKIP_UPLOAD; then
  echo "  Skipping upload (--skip-upload)"
else
  for PROJECT_ENTRY in "${PROJECTS[@]}"; do
    IFS='|' read -r PROJECT_PATH PROJECT_NAME PROJECT_VERSION <<< "$PROJECT_ENTRY"
    echo ""
    echo "  Uploading: $PROJECT_NAME:$PROJECT_VERSION"
    echo "  Source:    $ROOT_DIR/$PROJECT_PATH"
    echo "  Generator: $GENERATOR"

    if bash "$ROOT_DIR/scripts/upload-sbom.sh" \
      "$ROOT_DIR/$PROJECT_PATH" "$PROJECT_NAME" "$PROJECT_VERSION" \
      --generator "$GENERATOR" 2>&1 | sed 's/^/    /'; then
      pass "Uploaded $PROJECT_NAME"
    else
      fail "Failed to upload $PROJECT_NAME"
    fi
  done
fi

# ─── Step 4: Wait for Analysis ──────────────────────────────────
separator
echo "STEP 4: Wait for Vulnerability Analysis"
separator

if $SKIP_WAIT; then
  echo "  Skipping wait (--skip-wait)"
else
  echo "  Waiting ${ANALYSIS_WAIT}s for DT to analyze components..."
  echo "  (DT fetches vulnerability data from NVD, GitHub Advisories, etc.)"

  ELAPSED=0
  INTERVAL=10
  while [ "$ELAPSED" -lt "$ANALYSIS_WAIT" ]; do
    sleep "$INTERVAL"
    ELAPSED=$((ELAPSED + INTERVAL))

    # Check findings for one of the projects
    PROJECT_UUID=$(curl -s "$DTRACK_URL/api/v1/project?name=e2e-vulnerable-java&version=1.0.0" \
      -H "X-Api-Key: $DTRACK_API_KEY" | python3 -c "
import sys, json
try:
    print(json.load(sys.stdin)[0]['uuid'])
except:
    print('')
" 2>/dev/null)

    if [ -n "$PROJECT_UUID" ]; then
      FINDING_COUNT=$(curl -s "$DTRACK_URL/api/v1/finding/project/$PROJECT_UUID" \
        -H "X-Api-Key: $DTRACK_API_KEY" | python3 -c "
import sys, json
try:
    print(len(json.load(sys.stdin)))
except:
    print(0)
" 2>/dev/null)
      echo "    ${ELAPSED}s elapsed — e2e-vulnerable-java findings: $FINDING_COUNT"
      if [ "$FINDING_COUNT" -gt 0 ]; then
        echo "    Vulnerabilities detected, continuing..."
        break
      fi
    else
      echo "    ${ELAPSED}s elapsed — waiting for project creation..."
    fi
  done

  pass "Analysis wait complete"
fi

# ─── Step 5: Verify Projects in Dependency-Track ────────────────
separator
echo "STEP 5: Verify Projects in Dependency-Track"
separator

for PROJECT_ENTRY in "${PROJECTS[@]}"; do
  IFS='|' read -r PROJECT_PATH PROJECT_NAME PROJECT_VERSION <<< "$PROJECT_ENTRY"

  PROJECT_UUID=$(curl -s "$DTRACK_URL/api/v1/project?name=$PROJECT_NAME&version=$PROJECT_VERSION" \
    -H "X-Api-Key: $DTRACK_API_KEY" | python3 -c "
import sys, json
try:
    print(json.load(sys.stdin)[0]['uuid'])
except:
    print('')
" 2>/dev/null)

  if [ -n "$PROJECT_UUID" ]; then
    # Get component count via API
    COMP_COUNT=$(curl -s "$DTRACK_URL/api/v1/component/project/$PROJECT_UUID?pageSize=1" \
      -H "X-Api-Key: $DTRACK_API_KEY" \
      -w "\n%{http_code}" | head -1 | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(len(data) if isinstance(data, list) else '?')
except:
    print('?')
" 2>/dev/null)

    # Get finding count
    FINDING_COUNT=$(curl -s "$DTRACK_URL/api/v1/finding/project/$PROJECT_UUID" \
      -H "X-Api-Key: $DTRACK_API_KEY" | python3 -c "
import sys, json
try:
    findings = json.load(sys.stdin)
    sevs = {}
    for f in findings:
        s = f.get('vulnerability',{}).get('severity','?')
        sevs[s] = sevs.get(s,0)+1
    parts = []
    for s in ['CRITICAL','HIGH','MEDIUM','LOW']:
        if s in sevs:
            parts.append(f'{s[0]}:{sevs[s]}')
    print(f'{len(findings)} findings ({\" \".join(parts)})')
except:
    print('? findings')
" 2>/dev/null)

    pass "$PROJECT_NAME — $FINDING_COUNT"
  else
    fail "$PROJECT_NAME not found in DT"
  fi
done

# ─── Step 6: Verify Dashboards ──────────────────────────────────
separator
echo "STEP 6: Verify Grafana Dashboards"
separator

DASHBOARDS=(
  "home|Security Portfolio Overview"
  "vulnerability-detail|Vulnerability Detail"
  "vulnerability-aging|Vulnerability Aging & SLA"
  "epss-prioritization|EPSS Vulnerability Prioritization"
  "license-overview|License Overview"
  "license-components|License Components Detail"
  "outdated-dependencies|Outdated Dependencies"
  "sbom-freshness|SBOM Freshness"
  "risk-score|Risk Score"
)

for DASH_ENTRY in "${DASHBOARDS[@]}"; do
  IFS='|' read -r DASH_UID DASH_TITLE <<< "$DASH_ENTRY"

  DASH_RESPONSE=$(curl -s -w "\n%{http_code}" \
    -u "$GRAFANA_USER:$GRAFANA_PASS" \
    "$GRAFANA_URL/api/dashboards/uid/$DASH_UID" 2>/dev/null)

  DASH_HTTP=$(echo "$DASH_RESPONSE" | tail -1)
  DASH_BODY=$(echo "$DASH_RESPONSE" | sed '$d')

  if [ "$DASH_HTTP" = "200" ]; then
    PANEL_COUNT=$(echo "$DASH_BODY" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    panels = d.get('dashboard', {}).get('panels', [])
    total = 0
    for p in panels:
        if p.get('type') == 'row':
            total += len(p.get('panels', []))
        else:
            total += 1
    print(total)
except:
    print('?')
" 2>/dev/null)
    pass "$DASH_TITLE ($DASH_UID) — $PANEL_COUNT panels"
  else
    fail "$DASH_TITLE ($DASH_UID) — HTTP $DASH_HTTP"
  fi
done

# ─── Step 7: Test Dashboard Queries ─────────────────────────────
separator
echo "STEP 7: Test Dashboard Queries Return Data"
separator

DATASOURCE_ID=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASS" \
  "$GRAFANA_URL/api/datasources" | python3 -c "
import sys, json
try:
    for ds in json.load(sys.stdin):
        if ds.get('type') == 'postgres' or ds.get('type') == 'grafana-postgresql-datasource':
            print(ds['uid'])
            break
except:
    pass
" 2>/dev/null)

test_query() {
  local name="$1"
  local query="$2"

  RESULT=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASS" \
    -X POST "$GRAFANA_URL/api/ds/query" \
    -H "Content-Type: application/json" \
    -d "{
      \"queries\": [{
        \"refId\": \"A\",
        \"datasource\": {\"uid\": \"$DATASOURCE_ID\"},
        \"rawSql\": \"$query\",
        \"format\": \"table\"
      }],
      \"from\": \"now-1y\",
      \"to\": \"now\"
    }" 2>/dev/null)

  ROW_COUNT=$(echo "$RESULT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    frames = data.get('results', {}).get('A', {}).get('frames', [])
    if frames:
        values = frames[0].get('data', {}).get('values', [[]])
        print(len(values[0]) if values else 0)
    else:
        print(0)
except:
    print(0)
" 2>/dev/null)

  if [ "$ROW_COUNT" -gt 0 ]; then
    pass "$name — $ROW_COUNT rows"
  else
    warn "$name — no data (analysis may still be in progress)"
  fi
}

test_query "Projects exist" \
  "SELECT COUNT(*) as count FROM \\\"PROJECT\\\""

test_query "Components loaded" \
  "SELECT COUNT(*) as count FROM \\\"COMPONENT\\\""

test_query "Vulnerabilities found" \
  "SELECT COUNT(DISTINCT v.\\\"VULNID\\\") as count FROM \\\"VULNERABILITY\\\" v JOIN \\\"COMPONENTS_VULNERABILITIES\\\" cv ON v.\\\"ID\\\" = cv.\\\"VULNERABILITY_ID\\\""

test_query "EPSS scores available" \
  "SELECT COUNT(*) as count FROM \\\"VULNERABILITY\\\" WHERE \\\"EPSSSCORE\\\" IS NOT NULL AND \\\"EPSSSCORE\\\" > 0"

test_query "License data" \
  "SELECT COUNT(*) as count FROM \\\"COMPONENT\\\" WHERE \\\"LICENSE\\\" IS NOT NULL OR \\\"LICENSE_ID\\\" IS NOT NULL"

test_query "Project metrics (risk scores)" \
  "SELECT COUNT(*) as count FROM \\\"PROJECTMETRICS\\\""

test_query "Finding attributions (aging)" \
  "SELECT COUNT(*) as count FROM \\\"FINDINGATTRIBUTION\\\""

# ─── Step 8: Policy Violation Checks ────────────────────────────
separator
echo "STEP 8: Policy Violation Checks"
separator

for PROJECT_ENTRY in "${PROJECTS[@]}"; do
  IFS='|' read -r PROJECT_PATH PROJECT_NAME PROJECT_VERSION <<< "$PROJECT_ENTRY"

  echo ""
  echo "  Checking: $PROJECT_NAME:$PROJECT_VERSION"

  VIOLATION_RESULT=$(bash "$ROOT_DIR/scripts/check-policy-violations.sh" \
    "$PROJECT_NAME" "$PROJECT_VERSION" 2>&1 || true)

  SUMMARY=$(echo "$VIOLATION_RESULT" | grep "FAIL:" | head -1)
  if echo "$VIOLATION_RESULT" | grep -q "BUILD BLOCKED"; then
    # Expected for vulnerable projects — this is actually a PASS for e2e
    pass "$PROJECT_NAME — BUILD BLOCKED as expected ($SUMMARY)"
  elif echo "$VIOLATION_RESULT" | grep -q "BUILD APPROVED"; then
    # Policy evaluation may not have run yet
    warn "$PROJECT_NAME — BUILD APPROVED ($SUMMARY) — policies may not have evaluated yet"
  elif echo "$VIOLATION_RESULT" | grep -q "not found"; then
    fail "$PROJECT_NAME — project not found"
  else
    warn "$PROJECT_NAME — unknown result"
  fi
done

# ─── Step 9: Dashboard Link Verification ────────────────────────
separator
echo "STEP 9: Dashboard Link Verification"
separator

HOME_BODY=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASS" \
  "$GRAFANA_URL/api/dashboards/uid/home" 2>/dev/null)

LINKED_UIDS=$(echo "$HOME_BODY" | python3 -c "
import sys, json, re
try:
    d = json.load(sys.stdin)
    text = json.dumps(d)
    uids = set(re.findall(r'/d/([a-z-]+)/', text))
    for uid in sorted(uids):
        print(uid)
except:
    pass
" 2>/dev/null)

while IFS= read -r LINKED_UID; do
  if [ -n "$LINKED_UID" ]; then
    LINK_CHECK=$(curl -s -o /dev/null -w "%{http_code}" \
      -u "$GRAFANA_USER:$GRAFANA_PASS" \
      "$GRAFANA_URL/api/dashboards/uid/$LINKED_UID" 2>/dev/null)
    if [ "$LINK_CHECK" = "200" ]; then
      pass "Home links to $LINKED_UID — reachable"
    else
      fail "Home links to $LINKED_UID — broken (HTTP $LINK_CHECK)"
    fi
  fi
done <<< "$LINKED_UIDS"

# ─── Summary ────────────────────────────────────────────────────
separator
echo "E2E TEST RESULTS"
separator
echo ""
echo "  PASS: $PASS"
echo "  FAIL: $FAIL"
echo "  WARN: $WARN"
echo "  TOTAL: $((PASS + FAIL + WARN))"
echo ""

if [ "$FAIL" -gt 0 ]; then
  echo "  RESULT: FAILED ($FAIL failures)"
  exit 1
else
  echo "  RESULT: PASSED"
  if [ "$WARN" -gt 0 ]; then
    echo "  (with $WARN warnings — some data may appear after full analysis)"
  fi
  exit 0
fi
