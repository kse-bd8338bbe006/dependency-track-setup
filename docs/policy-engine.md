# Policy Engine

## Overview

Policies in Dependency-Track are automated rules that flag components violating your organization's standards. They run every time an SBOM is uploaded or a vulnerability analysis completes. When a component matches a policy condition, a **policy violation** is recorded — and depending on the violation state (FAIL, WARN, INFO), it can block CI/CD builds.

## Policy Structure

A policy consists of:

- **Name** — descriptive label (e.g. "Block Critical Vulnerabilities")
- **Operator** — `ANY` (at least one condition matches) or `ALL` (every condition must match)
- **Violation State** — what happens when triggered:
  - `FAIL` — hard block, should stop builds
  - `WARN` — advisory, creates visibility but doesn't block
  - `INFO` — informational only
- **Conditions** — one or more rules to evaluate
- **Scope** — global (all projects) or scoped to specific projects/tags

## Violation Types

| Type | What it checks | Triggered by |
|------|---------------|-------------|
| SECURITY | Vulnerability properties | Severity, CVSS score, CWE |
| LICENSE | License compliance | License name, license group |
| OPERATIONAL | Package/component rules | Package URL, component hash, version, age, coordinates |

## Policy Condition Subjects

| Subject | Description | Example |
|---------|-------------|---------|
| `SEVERITY` | Vulnerability severity level | `IS CRITICAL` |
| `LICENSE` | Specific license name | `IS GPL-3.0` |
| `LICENSE_GROUP` | License category | `IS Copyleft` |
| `PACKAGE_URL` | Package URL pattern | `MATCHES pkg:npm/event-stream` |
| `CWE` | Common Weakness Enumeration | `IS 89` (SQL Injection) |
| `COMPONENT_HASH` | SHA-256 or other hash | `IS sha256:abc123...` |
| `COMPONENT_NAME` | Package name | `MATCHES lodash` |
| `COMPONENT_VERSION` | Version string | `MATCHES 1.0.0` |
| `COORDINATES` | Group/name/version | `MATCHES org.apache.logging` |
| `VULNERABILITY_ID` | Specific CVE | `IS CVE-2024-3094` |
| `SWID_TAGID` | Software identification tag | `IS ...` |
| `CPE` | Common Platform Enumeration | `MATCHES cpe:/a:apache:log4j` |

## Typical Real-World Policies

### 1. Block Critical Vulnerabilities

The most common policy. Prevents deploying with critical CVEs.

```
Name:            Block Critical Vulnerabilities
Operator:        ANY
Violation State: FAIL
Condition:       SEVERITY IS CRITICAL
```

### 2. Warn on High Vulnerabilities

Doesn't block but creates visibility for triage.

```
Name:            Flag High Vulnerabilities
Operator:        ANY
Violation State: WARN
Condition:       SEVERITY IS HIGH
```

### 3. Ban Copyleft Licenses

Legal requirement for many companies — GPL-licensed code cannot be included in proprietary/commercial products without open-sourcing the entire product.

```
Name:            No Copyleft in Commercial Products
Operator:        ANY
Violation State: FAIL
Condition:       LICENSE_GROUP IS Copyleft
```

### 4. Ban Compromised Packages

Block packages known to have been involved in supply chain attacks. See the "Notable Supply Chain Attacks" section below for why each package is listed.

```
Name:            Blocked Packages
Operator:        ANY
Violation State: FAIL
Conditions:
  - PACKAGE_URL MATCHES pkg:npm/event-stream@3.3.6
  - PACKAGE_URL MATCHES pkg:npm/ua-parser-js@0.7.29
  - PACKAGE_URL MATCHES pkg:npm/@ledgerhq/connect-kit@1.1.8
```

### 5. Flag Specific Weakness Types

Block components associated with dangerous vulnerability classes.

```
Name:            No SQL Injection
Operator:        ANY
Violation State: FAIL
Condition:       CWE IS 89
```

### 6. Block Known Bad CVE

When a specific high-profile CVE is announced, immediately check your portfolio.

```
Name:            Block Log4Shell
Operator:        ANY
Violation State: FAIL
Condition:       VULNERABILITY_ID IS CVE-2021-44228
```

## Notable Supply Chain Attacks

These incidents demonstrate why operational policies exist. Each of these could have been caught (reactively) by adding the compromised package to a Dependency-Track policy.

### event-stream (2018)

A popular npm package (2M+ weekly downloads) maintained by a single developer. He handed over ownership to a new contributor who seemed helpful. The new maintainer added a dependency `flatmap-stream` containing hidden malicious code that targeted the Copay Bitcoin wallet. The encrypted payload stole cryptocurrency private keys from Copay users. It went undetected for ~2 months because the malicious code only activated inside the Copay build environment.

**Impact:** Cryptocurrency theft from Copay wallet users.
**Package:** `pkg:npm/event-stream@3.3.6`

### ua-parser-js (2021)

The npm account of the `ua-parser-js` maintainer (7M+ weekly downloads) was compromised. The attacker published versions 0.7.29, 0.8.0, and 1.0.0 containing a cryptominer and a password-stealing trojan for both Linux and Windows.

**Impact:** Cryptomining and credential theft on developer machines and CI servers.
**Package:** `pkg:npm/ua-parser-js@0.7.29`

### colors / faker (2022)

The maintainer of `colors` (20M+ weekly downloads) and `faker` (2.5M+ weekly downloads) deliberately sabotaged his own packages. He pushed updates that added an infinite loop printing "LIBERTY LIBERTY LIBERTY" to the console, breaking thousands of projects. His stated motivation was that Fortune 500 companies used his free work without contributing back.

**Impact:** Denial of service for any application using these packages. A protest, not a traditional attack.
**Packages:** `pkg:npm/colors@1.4.1`, `pkg:npm/faker@6.6.6`

### xz-utils (2024)

A multi-year social engineering campaign against the xz compression library. An attacker ("Jia Tan") spent two years building trust with the maintainer, gradually took over maintenance, then inserted a sophisticated backdoor that compromised the SSH authentication process on Linux systems. Discovered by accident when a Microsoft engineer noticed SSH was slower than expected.

**Impact:** Remote code execution on any Linux system running the compromised version with systemd-based SSH.
**Package:** `pkg:generic/xz@5.6.0`, `pkg:generic/xz@5.6.1`
**CVE:** CVE-2024-3094

### @ledgerhq/connect-kit (2023)

An attacker compromised a former Ledger employee's npm account via a phishing attack. They published malicious versions of `@ledgerhq/connect-kit` that included a "crypto drainer" — code that tricked users into signing transactions that transferred their crypto assets to the attacker.

**Impact:** Cryptocurrency theft from users of applications that integrated the Ledger Connect Kit.
**Package:** `pkg:npm/@ledgerhq/connect-kit@1.1.8`

### Lessons

| Lesson | Policy response |
|--------|----------------|
| Single maintainer risk | Can't be solved by policy alone — but operational policies let you react fast |
| Account compromise | Block specific compromised versions via PACKAGE_URL |
| Intentional sabotage | Block specific versions via PACKAGE_URL |
| Social engineering | Block specific versions, monitor for hash mismatches |
| NPM token theft | Block specific compromised versions immediately |

The pattern is consistent: once a compromised package is identified, add its Package URL to a Dependency-Track policy to instantly check your entire portfolio and block it from future builds.

## Setting Up Policies via API

### Create a policy

```bash
source .env

curl -s -X PUT "$DTRACK_URL/api/v1/policy" \
  -H "X-Api-Key: $DTRACK_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Block Critical Vulnerabilities",
    "operator": "ANY",
    "violationState": "FAIL"
  }'
```

### Add a condition

```bash
# Replace POLICY_UUID with the UUID returned from the create call
curl -s -X PUT "$DTRACK_URL/api/v1/policy/POLICY_UUID/condition" \
  -H "X-Api-Key: $DTRACK_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "subject": "SEVERITY",
    "operator": "IS",
    "value": "CRITICAL"
  }'
```

### Check violations

```bash
# All violations across portfolio
curl -s "$DTRACK_URL/api/v1/violation" \
  -H "X-Api-Key: $DTRACK_API_KEY" | jq '.[] | {
    component: .component.name,
    version: .component.version,
    project: .component.project.name,
    policy: .policyCondition.policy.name,
    type: .type,
    state: .policyCondition.policy.violationState
  }'

# Violations for a specific project
curl -s "$DTRACK_URL/api/v1/violation/project/PROJECT_UUID" \
  -H "X-Api-Key: $DTRACK_API_KEY"
```

## CI/CD Build Gating

Use policy violations to gate builds. Check for FAIL-level violations after uploading an SBOM:

```bash
source .env

# Upload SBOM (returns processing token)
TOKEN=$(./scripts/upload-sbom.sh ./my-project my-app 1.0.0 | grep -oP 'token.*?"(.*?)"' | cut -d'"' -f2)

# Wait for processing to complete (poll token)
sleep 10

# Get project UUID
PROJECT_UUID=$(curl -s "$DTRACK_URL/api/v1/project?name=my-app&version=1.0.0" \
  -H "X-Api-Key: $DTRACK_API_KEY" | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['uuid'])")

# Check for FAIL violations
VIOLATIONS=$(curl -s "$DTRACK_URL/api/v1/violation/project/$PROJECT_UUID" \
  -H "X-Api-Key: $DTRACK_API_KEY")

FAIL_COUNT=$(echo "$VIOLATIONS" | python3 -c "
import sys, json
violations = json.load(sys.stdin)
fails = [v for v in violations if v['policyCondition']['policy']['violationState'] == 'FAIL']
print(len(fails))
")

if [ "$FAIL_COUNT" -gt 0 ]; then
  echo "Build blocked: $FAIL_COUNT FAIL-level policy violations"
  echo "$VIOLATIONS" | python3 -c "
import sys, json
for v in json.load(sys.stdin):
    if v['policyCondition']['policy']['violationState'] == 'FAIL':
        print(f\"  - {v['component']['name']}@{v['component']['version']}: {v['policyCondition']['policy']['name']}\")
"
  exit 1
fi

echo "No policy violations. Build approved."
```

## Scoping Policies

By default, policies apply to all projects (global). You can scope them to specific projects or tags:

```bash
# Scope policy to specific projects
curl -s -X POST "$DTRACK_URL/api/v1/policy/POLICY_UUID/project/PROJECT_UUID" \
  -H "X-Api-Key: $DTRACK_API_KEY"

# Scope policy to projects with a specific tag
curl -s -X POST "$DTRACK_URL/api/v1/policy/POLICY_UUID/tag/TAG_NAME" \
  -H "X-Api-Key: $DTRACK_API_KEY"
```

Use cases for scoping:
- Apply "No Copyleft" only to commercial products, not internal tools
- Apply stricter severity policies to production services, relaxed ones to development tools
- Apply package blocklists only to frontend projects (npm-specific threats)
