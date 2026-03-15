# Risk Scoring in Dependency-Track

## Overview

Dependency-Track calculates an **Inherited Risk Score (IRS)** for every component and project. It is a weighted sum of vulnerability counts by severity — not a single CVSS score.

## Formula

```
Risk Score = (critical × 10) + (high × 5) + (medium × 3) + (low × 1) + (unassigned × 5)
```

Each value is the **count** of open (non-suppressed) vulnerabilities at that severity level.

### Example

A project with 1 critical, 3 high, 5 medium, and 2 low vulnerabilities:

```
Risk Score = (1 × 10) + (3 × 5) + (5 × 3) + (2 × 1) = 10 + 15 + 15 + 2 = 42
```

### Severity Weights

| Severity | Weight | Rationale |
|----------|--------|-----------|
| CRITICAL | 10 | Highest impact, most urgent |
| HIGH | 5 | Significant risk |
| MEDIUM | 3 | Moderate risk |
| LOW | 1 | Minimal immediate risk |
| UNASSIGNED | 5 | Treated as HIGH to avoid ignoring unclassified vulnerabilities |

## What the Risk Score Is Used For

### 1. Project Prioritization

When you have 50+ projects, the risk score tells you which ones need attention first. A project with score 351 is worse off than one with score 3. Sort by risk score and work top-down.

### 2. Trend Tracking

Is a project getting better or worse over time? If the score was 100 last month and 200 now, you're accumulating unresolved vulnerabilities. If it dropped from 200 to 50, your remediation efforts are working. The Portfolio Risk Score Grafana dashboard shows this as a time-series chart.

### 3. Executive Reporting

Management asks "how's our security posture?" The portfolio risk score gives a single number they can track quarter over quarter. It's not perfect, but it's concrete and easy to explain.

### 4. Build Gating

You can use the API to check a project's risk score in CI/CD and fail the build if it exceeds a threshold:

```bash
source .env

RISK_SCORE=$(curl -s "$DTRACK_URL/api/v1/metrics/project/$PROJECT_UUID/current" \
  -H "X-Api-Key: $DTRACK_API_KEY" | jq '.inheritedRiskScore')

if [ "$RISK_SCORE" -gt 100 ]; then
  echo "Risk score $RISK_SCORE exceeds threshold of 100"
  exit 1
fi
```

### 5. Comparative Analysis

Compare the same application across versions (v1.0 vs v2.0), or compare different teams' projects. Who's keeping their dependencies clean? The stacked bar chart in the Risk Score dashboard makes this immediately visible.

### 6. Compliance Targets

Some compliance frameworks require "risk must not exceed X." The score gives you a measurable target to define and enforce through policies or CI/CD gates.

### Honest Assessment

The risk score is a rough heuristic, not a precise risk measurement. Its main value is as a **relative comparison tool** and a **trend indicator** — not as an absolute measure of security. A project with score 200 is not necessarily twice as risky as one with score 100. That's why the EPSS Prioritization dashboard exists alongside it — the risk score tells you *where* to look, EPSS tells you *what to fix first*.

## Where Risk Scores Are Stored

| Table | Column | Scope |
|-------|--------|-------|
| `PROJECT` | `LAST_RISKSCORE` | Total risk score for the project (sum of all component risk) |
| `COMPONENT` | `LAST_RISKSCORE` | Risk score for a single component |
| `PROJECTMETRICS` | `RISKSCORE` | Historical risk score snapshots (time-series) |
| `DEPENDENCYMETRICS` | `RISKSCORE` | Per-component metric snapshots |

## When Risk Scores Update

Risk scores are recalculated when Dependency-Track runs its periodic metrics update task. You can also trigger a manual refresh:

```bash
source .env

# Get project UUID
PROJECT_UUID=$(curl -s "$DTRACK_URL/api/v1/project?name=my-app&version=1.0.0" \
  -H "X-Api-Key: $DTRACK_API_KEY" | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['uuid'])")

# Force metrics refresh
curl -s "$DTRACK_URL/api/v1/metrics/project/$PROJECT_UUID/refresh" \
  -H "X-Api-Key: $DTRACK_API_KEY"
```

## What Affects the Risk Score

| Action | Effect on Risk Score |
|--------|---------------------|
| New SBOM uploaded (new vulnerabilities found) | Increases |
| Vulnerability triaged as `RESOLVED` | Decreases |
| Vulnerability triaged as `FALSE_POSITIVE` | Decreases |
| Vulnerability triaged as `NOT_AFFECTED` | Decreases |
| Finding suppressed | Decreases |
| New CVE published affecting a component | Increases (on next analysis) |
| Component updated to patched version | Decreases (after re-scan) |

## Limitations

The Inherited Risk Score has several known limitations:

### 1. No EPSS Integration

All CRITICALs are treated equally. A CRITICAL vulnerability with 90% EPSS (actively exploited) and a CRITICAL with 0.01% EPSS (theoretical risk) both contribute 10 points to the score.

**Workaround:** Use the EPSS Prioritization Grafana dashboard to see which vulnerabilities actually matter.

### 2. Linear Accumulation

Risk scores grow linearly with vulnerability count. A project with 100 LOWs (score = 100) appears riskier than a project with 1 CRITICAL (score = 10), even though the CRITICAL is almost certainly more dangerous.

**Workaround:** Look at severity breakdown, not just the total score. The Portfolio Risk dashboard shows both.

### 3. No Context Awareness

The score doesn't consider:
- Whether the vulnerable code path is actually reachable
- Whether the component is in a production or development dependency
- Network exposure or deployment context
- Existing mitigating controls

**Workaround:** Use the ANALYSIS table to triage findings and mark them as `NOT_AFFECTED` with justification `CODE_NOT_REACHABLE` when applicable.

### 4. Unassigned = HIGH

Vulnerabilities without a severity assignment get weight 5 (same as HIGH). This is conservative by design but can inflate scores when vulnerability sources haven't assigned severity yet.

## Risk Score vs EPSS: When to Use Each

| Question | Use |
|----------|-----|
| "Which project has the most risk?" | Risk Score — aggregates all vulnerabilities |
| "Which vulnerability should I fix first?" | EPSS — predicts actual exploitation likelihood |
| "Are we meeting our SLA?" | Vulnerability Aging dashboard — tracks time since discovery |
| "Is our risk trending up or down?" | Portfolio Risk dashboard — risk score over time |
| "What's our overall security posture?" | Both — risk score for breadth, EPSS for depth |
