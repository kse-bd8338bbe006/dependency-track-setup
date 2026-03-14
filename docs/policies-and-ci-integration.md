# Policies and CI/CD Build Gating

Dependency-Track policies define rules that flag violations when components in a project match certain conditions. Policies can be used to **block builds** in CI/CD pipelines when critical vulnerabilities or unwanted licenses are detected.

## Table of Contents

- [Policy Concepts](#policy-concepts)
- [Creating Policies](#creating-policies)
- [Policy Conditions Reference](#policy-conditions-reference)
- [Checking Violations via API](#checking-violations-via-api)
- [Blocking Docker Image Builds in CI/CD](#blocking-docker-image-builds-in-cicd)
- [Reusable Workflow with Build Gating](#reusable-workflow-with-build-gating)

## Policy Concepts

Each policy has three key properties:

| Property | Description |
|----------|-------------|
| **Name** | Human-readable label |
| **Operator** | `ANY` (at least one condition matches) or `ALL` (every condition must match) |
| **Violation State** | `FAIL`, `WARN`, or `INFO` — determines severity of the violation |

Policies are **global** by default (apply to all projects) but can be scoped to specific projects or tags.

## Creating Policies

### Via UI

1. Go to **Policy Management** in the left sidebar
2. Click **Create Policy**
3. Set the name, operator, and violation state
4. Add one or more conditions
5. Optionally assign to specific projects or tags

### Via API

#### Create a policy

```bash
TOKEN=$(curl -s -X POST $DTRACK_URL/api/v1/user/login \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d 'username=admin&password=YOUR_PASSWORD')

curl -s -X PUT "$DTRACK_URL/api/v1/policy" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Block Critical and High Vulnerabilities",
    "operator": "ANY",
    "violationState": "FAIL"
  }'
```

The response includes the policy `uuid`, which is needed to add conditions.

#### Add conditions to a policy

```bash
# Block CRITICAL severity
curl -s -X PUT "$DTRACK_URL/api/v1/policy/POLICY_UUID/condition" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "subject": "SEVERITY",
    "operator": "IS",
    "value": "CRITICAL"
  }'

# Block HIGH severity
curl -s -X PUT "$DTRACK_URL/api/v1/policy/POLICY_UUID/condition" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "subject": "SEVERITY",
    "operator": "IS",
    "value": "HIGH"
  }'
```

#### Create a license policy

```bash
curl -s -X PUT "$DTRACK_URL/api/v1/policy" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Warn on Copyleft Licenses",
    "operator": "ANY",
    "violationState": "WARN"
  }'

curl -s -X PUT "$DTRACK_URL/api/v1/policy/POLICY_UUID/condition" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "subject": "LICENSE_GROUP",
    "operator": "IS",
    "value": "Copyleft"
  }'
```

## Policy Conditions Reference

| Subject | Description | Example values |
|---------|-------------|----------------|
| `SEVERITY` | Vulnerability severity | `CRITICAL`, `HIGH`, `MEDIUM`, `LOW`, `UNASSIGNED` |
| `LICENSE_GROUP` | License category | `Copyleft`, `Permissive`, `Public Domain` |
| `LICENSE` | Specific license | `MIT`, `Apache-2.0`, `GPL-3.0` |
| `PACKAGE_URL` | Match by package URL | `pkg:npm/lodash` |
| `CPE` | Match by CPE string | `cpe:/a:apache:log4j` |
| `COMPONENT_AGE` | Component age in days | `365` (older than 1 year) |
| `VULNERABILITY_ID` | Specific CVE | `CVE-2021-44228` |
| `CWE` | Weakness type | `79` (XSS), `89` (SQL injection) |
| `COORDINATES` | Match by group/name/version | `{"group":"org.apache","name":"log4j"}` |

Each condition supports operators: `IS`, `IS_NOT`, `MATCHES`, `NO_MATCH`.

## Checking Violations via API

After uploading an SBOM, query the violations endpoint to check if any policies were triggered:

```bash
# Get violations for a project
curl -s "$DTRACK_URL/api/v1/violation/project/PROJECT_UUID" \
  -H "X-Api-Key: $DTRACK_API_KEY"
```

The response is a JSON array. Each violation includes:
- `type` — `SECURITY`, `LICENSE`, or `OPERATIONAL`
- `policyCondition.policy.violationState` — `FAIL`, `WARN`, or `INFO`
- `component` — the component that triggered the violation

## Blocking Docker Image Builds in CI/CD

The general approach is:

1. Generate SBOM from the source code
2. Upload SBOM to Dependency-Track
3. Wait for analysis to complete
4. Query the violations API
5. If any `FAIL` violations exist, abort the pipeline before building the Docker image

### Wait for Analysis Completion

After uploading an SBOM, Dependency-Track returns a processing token. Poll the token endpoint to wait for analysis to finish:

```bash
# Upload SBOM and capture the token
UPLOAD_TOKEN=$(curl -s -X PUT "$DTRACK_URL/api/v1/bom" \
  -H "X-Api-Key: $DTRACK_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"projectName\": \"my-app\",
    \"projectVersion\": \"1.0.0\",
    \"autoCreate\": true,
    \"bom\": \"$(base64 -w0 sbom.json)\"
  }" | jq -r '.token')

# Poll until processing is complete (processing=false means done)
while true; do
  PROCESSING=$(curl -s "$DTRACK_URL/api/v1/bom/token/$UPLOAD_TOKEN" \
    -H "X-Api-Key: $DTRACK_API_KEY" | jq -r '.processing')
  if [ "$PROCESSING" = "false" ]; then
    echo "Analysis complete"
    break
  fi
  echo "Waiting for analysis..."
  sleep 5
done
```

### Check for FAIL Violations

```bash
# Get the project UUID
PROJECT_UUID=$(curl -s "$DTRACK_URL/api/v1/project/lookup?name=my-app&version=1.0.0" \
  -H "X-Api-Key: $DTRACK_API_KEY" | jq -r '.uuid')

# Count FAIL violations
FAIL_COUNT=$(curl -s "$DTRACK_URL/api/v1/violation/project/$PROJECT_UUID" \
  -H "X-Api-Key: $DTRACK_API_KEY" | \
  jq '[.[] | select(.policyCondition.policy.violationState == "FAIL")] | length')

if [ "$FAIL_COUNT" -gt 0 ]; then
  echo "BUILD BLOCKED: $FAIL_COUNT policy violation(s) with FAIL state"
  exit 1
fi

echo "No blocking violations. Proceeding with Docker build."
```

## Reusable Workflow with Build Gating

Below is an example GitHub Actions workflow that gates Docker image builds based on Dependency-Track policy violations. This can be added to any repository:

```yaml
name: Build with SBOM Gate

on:
  push:
    branches: [main]

jobs:
  sbom-gate:
    runs-on: ubuntu-latest
    outputs:
      project-uuid: ${{ steps.upload.outputs.project-uuid }}
    steps:
      - uses: actions/checkout@v4

      - name: Install tools
        run: |
          sudo apt-get install -y wget apt-transport-https gnupg
          wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | gpg --dearmor | sudo tee /usr/share/keyrings/trivy.gpg > /dev/null
          echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb generic main" | sudo tee /etc/apt/sources.list.d/trivy.list
          sudo apt-get update
          sudo apt-get install -y trivy jq

      - name: Generate SBOM
        run: trivy fs --format cyclonedx --output sbom.json .

      - name: Upload SBOM and wait for analysis
        id: upload
        run: |
          # Upload
          UPLOAD_TOKEN=$(curl -s -X PUT "${{ secrets.DTRACK_URL }}/api/v1/bom" \
            -H "X-Api-Key: ${{ secrets.DTRACK_API_KEY }}" \
            -H "Content-Type: application/json" \
            -d "{
              \"projectName\": \"${{ github.event.repository.name }}\",
              \"projectVersion\": \"${{ github.ref_name }}\",
              \"autoCreate\": true,
              \"bom\": \"$(base64 -w0 sbom.json)\"
            }" | jq -r '.token')

          # Wait for processing
          for i in $(seq 1 30); do
            PROCESSING=$(curl -s "${{ secrets.DTRACK_URL }}/api/v1/bom/token/$UPLOAD_TOKEN" \
              -H "X-Api-Key: ${{ secrets.DTRACK_API_KEY }}" | jq -r '.processing')
            if [ "$PROCESSING" = "false" ]; then
              echo "Analysis complete"
              break
            fi
            echo "Waiting for analysis... ($i/30)"
            sleep 10
          done

          # Get project UUID
          PROJECT_UUID=$(curl -s "${{ secrets.DTRACK_URL }}/api/v1/project/lookup?name=${{ github.event.repository.name }}&version=${{ github.ref_name }}" \
            -H "X-Api-Key: ${{ secrets.DTRACK_API_KEY }}" | jq -r '.uuid')
          echo "project-uuid=$PROJECT_UUID" >> "$GITHUB_OUTPUT"

      - name: Check policy violations
        run: |
          FAIL_COUNT=$(curl -s "${{ secrets.DTRACK_URL }}/api/v1/violation/project/${{ steps.upload.outputs.project-uuid }}" \
            -H "X-Api-Key: ${{ secrets.DTRACK_API_KEY }}" | \
            jq '[.[] | select(.policyCondition.policy.violationState == "FAIL")] | length')

          echo "FAIL violations: $FAIL_COUNT"

          if [ "$FAIL_COUNT" -gt 0 ]; then
            echo "::error::Build blocked by Dependency-Track: $FAIL_COUNT FAIL policy violation(s)"
            curl -s "${{ secrets.DTRACK_URL }}/api/v1/violation/project/${{ steps.upload.outputs.project-uuid }}" \
              -H "X-Api-Key: ${{ secrets.DTRACK_API_KEY }}" | \
              jq -r '.[] | select(.policyCondition.policy.violationState == "FAIL") | "  - \(.component.name):\(.component.version) [\(.policyCondition.policy.name)]"'
            exit 1
          fi

  build-image:
    needs: sbom-gate
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Build Docker image
        run: docker build -t my-app:${{ github.sha }} .

      - name: Push Docker image
        run: |
          # docker push commands here
          echo "Image built and ready to push"
```

### How it works

1. **sbom-gate** job runs first — generates SBOM, uploads to Dependency-Track, waits for analysis, and checks for FAIL violations
2. If any FAIL violations exist, the job fails with a list of violating components
3. **build-image** job depends on `sbom-gate` via `needs:` — it only runs if the gate passes
4. The Docker image is only built and pushed when no blocking policy violations are found

### Required GitHub Secrets

| Secret | Description |
|--------|-------------|
| `DTRACK_URL` | Dependency-Track API URL |
| `DTRACK_API_KEY` | API key with `BOM_UPLOAD`, `VIEW_PORTFOLIO`, `PROJECT_CREATION_UPLOAD` permissions |
