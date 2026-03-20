# Project Ownership & Team Responsibility

## The Problem

When Dependency-Track detects a vulnerability or a policy violation blocks a CI build, you need to know:
- **Which team** is responsible for this project?
- **Where to create a ticket** (Jira project, Linear team)?
- **Who to notify** (Slack channel, email)?

DT doesn't have built-in ownership tracking — it's a vulnerability inventory, not a task manager. You need an external mapping.

## Approaches

### 1. DT Tags (Simplest)

Tag each project in DT with team and Jira project info.

```bash
# Set tags via API
curl -X PATCH "$DTRACK_URL/api/v1/project/$PROJECT_UUID" \
  -H "X-Api-Key: $DTRACK_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"tags": [{"name": "team:platform"}, {"name": "jira:PLAT"}]}'
```

**Pros:** Simple, visible in DT UI, filterable in Grafana.
**Cons:** Manual, no single source of truth, can drift.

Query tags in Grafana dashboards:

```sql
SELECT p."NAME", t."NAME" AS tag
FROM "PROJECT" p
JOIN "PROJECTS_TAGS" pt ON p."ID" = pt."PROJECT_ID"
JOIN "TAG" t ON pt."TAG_ID" = t."ID"
WHERE t."NAME" LIKE 'team:%'
```

### 2. GitOps Ownership File (Recommended)

Maintain a YAML mapping in your repo — single source of truth, versioned, reviewable.

```yaml
# projects/ownership.yaml
projects:
  - name: my-app
    version: "1.0.0"
    team: Platform
    jira_project: PLAT
    slack: "#platform-alerts"
    contacts:
      - alice@company.com

  - name: sso-service
    version: "1.0.0"
    team: Identity
    jira_project: IDN
    slack: "#identity-alerts"
    contacts:
      - bob@company.com

  - name: payment-gateway
    version: "2.0.0"
    team: Payments
    jira_project: PAY
    slack: "#payments-oncall"
    contacts:
      - carol@company.com

defaults:
  jira_project: SEC
  slack: "#security-alerts"
  contacts:
    - security-team@company.com
```

When a policy violation blocks a build, the CI script looks up the project in this file and routes the alert to the right team.

### 3. Naming Convention (Zero Config)

If project names follow a convention, extract ownership from the name:

```
platform-my-app       → team: platform,  Jira: PLAT
identity-sso-service  → team: identity,  Jira: IDN
payments-gateway      → team: payments,  Jira: PAY
```

```bash
# Extract team prefix from project name
TEAM=$(echo "$PROJECT_NAME" | cut -d'-' -f1)
JIRA_PROJECT=$(echo "$TEAM" | tr '[:lower:]' '[:upper:]')
```

**Pros:** No config file needed.
**Cons:** Fragile, requires strict naming discipline.

### 4. External CMDB / Service Catalog

If your organization uses a service catalog (Backstage, OpsLevel, Cortex, etc.), query it:

```bash
# Example: look up owner from Backstage catalog
OWNER=$(curl -s "https://backstage.internal/api/catalog/entities/by-name/component/$PROJECT_NAME" \
  | jq -r '.spec.owner')
```

**Pros:** Single source of truth for the entire org.
**Cons:** Requires existing infrastructure.

## CI Integration

### Build Gate with Team Notification

Example flow when `check-policy-violations.sh` detects a FAIL:

```bash
#!/usr/bin/env bash
# ci/security-gate.sh

PROJECT_NAME="$1"
PROJECT_VERSION="$2"

# 1. Check policy violations
RESULT=$(./scripts/check-policy-violations.sh "$PROJECT_NAME" "$PROJECT_VERSION" --wait 30 2>&1)
EXIT_CODE=$?

if [ "$EXIT_CODE" -eq 0 ]; then
  echo "Security gate passed"
  exit 0
fi

# 2. Look up ownership
OWNER=$(python3 -c "
import yaml
with open('projects/ownership.yaml') as f:
    config = yaml.safe_load(f)

defaults = config.get('defaults', {})
for p in config.get('projects', []):
    if p['name'] == '$PROJECT_NAME':
        print(f\"{p.get('team','?')}|{p.get('jira_project', defaults.get('jira_project','SEC'))}|{p.get('slack', defaults.get('slack','#security-alerts'))}\")
        break
else:
    print(f\"unknown|{defaults.get('jira_project','SEC')}|{defaults.get('slack','#security-alerts')}\")
")

IFS='|' read -r TEAM JIRA_PROJECT SLACK_CHANNEL <<< "$OWNER"

# 3. Notify via Slack
curl -s -X POST "$SLACK_WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  -d "{
    \"channel\": \"$SLACK_CHANNEL\",
    \"text\": \"Security policy violation in *$PROJECT_NAME:$PROJECT_VERSION* (team: $TEAM)\n\`\`\`$RESULT\`\`\`\"
  }"

# 4. Create Jira ticket
curl -s -X POST "https://jira.company.com/rest/api/2/issue" \
  -u "$JIRA_USER:$JIRA_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"fields\": {
      \"project\": {\"key\": \"$JIRA_PROJECT\"},
      \"summary\": \"Security: policy violation in $PROJECT_NAME:$PROJECT_VERSION\",
      \"description\": \"$(echo "$RESULT" | sed 's/"/\\"/g')\",
      \"issuetype\": {\"name\": \"Bug\"},
      \"priority\": {\"name\": \"High\"},
      \"labels\": [\"security\", \"policy-violation\"]
    }
  }"

echo "Build blocked. Notified $TEAM via $SLACK_CHANNEL, Jira ticket created in $JIRA_PROJECT."
exit 1
```

## Recommended Setup

1. Start with **DT tags** for quick wins — tag existing projects with `team:xxx`
2. Add **ownership.yaml** when you automate CI gates
3. Wire up Slack/Jira notifications in the CI security gate script
4. If you have a service catalog (Backstage), use it as the source of truth instead of ownership.yaml

## Grafana: Ownership in Dashboards

If you use DT tags, you can show team ownership in Grafana:

```sql
-- Projects by team with risk scores
SELECT
  REPLACE(t."NAME", 'team:', '') AS team,
  p."NAME" AS project,
  p."LAST_RISKSCORE" AS risk_score
FROM "PROJECT" p
JOIN "PROJECTS_TAGS" pt ON p."ID" = pt."PROJECT_ID"
JOIN "TAG" t ON pt."TAG_ID" = t."ID"
WHERE t."NAME" LIKE 'team:%'
ORDER BY p."LAST_RISKSCORE" DESC
```

This lets you build dashboards filtered by team — each team sees only their projects and vulnerabilities.
