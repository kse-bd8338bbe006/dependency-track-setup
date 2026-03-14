# Database Schema

Dependency-Track uses PostgreSQL to store all data. When an SBOM is uploaded, it is parsed and decomposed into normalized relational tables — the raw SBOM file is not stored.

This document describes all 64 tables grouped by function.

## Table Overview

| Category | Tables | Purpose |
|----------|--------|---------|
| [Core Data](#core-data) | 8 | Projects, components, BOMs, services |
| [Vulnerability](#vulnerability-data) | 7 | CVEs, findings, analysis cache |
| [Metrics](#metrics) | 4 | Project, portfolio, dependency, vulnerability metrics |
| [Policy](#policy-engine) | 5 | Policies, conditions, violations |
| [Access Management](#access-management) | 14 | Users, teams, API keys, permissions |
| [Licensing](#licensing) | 3 | License catalog and groups |
| [Notifications](#notifications) | 4 | Alert rules and publishers |
| [Repository](#repository-metadata) | 2 | Package registry metadata |
| [Configuration](#configuration) | 3 | System settings and schema version |

## Core Data

These tables store the primary SBOM-derived data.

### PROJECT

The top-level entity. Each project represents an application or service being tracked.

| Column | Description |
|--------|-------------|
| NAME, VERSION | Project identifier (e.g. `my-app`, `1.0.0`) |
| ACTIVE | Whether the project is active |
| CLASSIFIER | Type: APPLICATION, LIBRARY, FRAMEWORK, CONTAINER, etc. |
| PURL | Package URL if applicable |
| CPE | Common Platform Enumeration identifier |
| PARENT_PROJECT_ID | FK to parent project (for hierarchical projects) |
| LAST_BOM_IMPORTED | Timestamp of the most recent SBOM upload |
| LAST_VULNERABILITY_ANALYSIS | Timestamp of the last vulnerability scan |
| LAST_RISKSCORE | Cached risk score |
| DIRECT_DEPENDENCIES | JSON array of direct dependency UUIDs |

**Row count:** 4

### COMPONENT

Each row is a package/library extracted from an uploaded SBOM. This is the largest actively-managed table.

| Column | Description |
|--------|-------------|
| NAME, VERSION, GROUP | Package coordinates (e.g. `express`, `4.18.2`) |
| PURL | Package URL (e.g. `pkg:npm/express@4.18.2`) |
| CPE | CPE identifier for NVD matching |
| CLASSIFIER | LIBRARY, FRAMEWORK, APPLICATION, CONTAINER, FILE, etc. |
| LICENSE, LICENSE_ID | Resolved license |
| PROJECT_ID | FK to the owning project |
| PARENT_COMPONENT_ID | FK to parent component (dependency tree) |
| MD5, SHA1, SHA_256, SHA_512, etc. | Hash digests for integrity verification |
| BLAKE2B_256, BLAKE3 | Additional hash algorithms |
| DIRECT_DEPENDENCIES | JSON array of direct dependency UUIDs |
| INTERNAL | Whether this is an internal (first-party) component |
| LAST_RISKSCORE | Cached risk score |

**Row count:** 2,061

### BOM

Metadata about each SBOM upload. The raw SBOM content is not stored — only its metadata.

| Column | Description |
|--------|-------------|
| BOM_FORMAT | `CycloneDX` or `SPDX` |
| SPEC_VERSION | SBOM spec version (e.g. `1.6`) |
| BOM_VERSION | Version number within the BOM |
| SERIAL_NUMBER | Unique identifier for the BOM |
| IMPORTED | Upload timestamp |
| PROJECT_ID | FK to the project |

**Row count:** 7

### COMPONENT_PROPERTY

Custom key-value properties attached to components.

### PROJECT_PROPERTY

Custom key-value properties attached to projects.

### PROJECT_METADATA

Additional metadata about projects (authors, tools used to generate the BOM).

### SERVICECOMPONENT

Services declared in the SBOM (API endpoints, external services). Most SBOMs don't include these.

**Row count:** 0

### SERVICECOMPONENTS_VULNERABILITIES

Join table linking service components to vulnerabilities.

## Vulnerability Data

### VULNERABILITY

All known vulnerabilities from mirrored sources (NVD, GitHub Advisories, OSS Index, etc.). This is the largest table by volume.

| Column | Description |
|--------|-------------|
| VULNID | CVE identifier (e.g. `CVE-2024-29415`) |
| SOURCE | Where it came from: `NVD`, `GITHUB`, `OSSINDEX`, etc. |
| SEVERITY | `CRITICAL`, `HIGH`, `MEDIUM`, `LOW`, `UNASSIGNED` |
| CVSSV2BASESCORE, CVSSV3BASESCORE | CVSS severity scores |
| CVSSV2VECTOR, CVSSV3VECTOR | CVSS vector strings |
| EPSSSCORE | EPSS exploitation probability (0.0–1.0) |
| EPSSPERCENTILE | EPSS percentile rank (0.0–1.0) |
| DESCRIPTION | Human-readable vulnerability description |
| PUBLISHED, UPDATED | Publication and update timestamps |
| CWES | Associated CWE weakness identifiers |
| PATCHEDVERSIONS | Versions that fix the vulnerability |
| RECOMMENDATION | Remediation guidance |

**Row count:** 337,712

### COMPONENTS_VULNERABILITIES

Join table linking components to their matched vulnerabilities. This is the core relationship table for vulnerability findings.

**Row count:** 158

### FINDINGATTRIBUTION

Records which analyzer identified each vulnerability match and when.

| Column | Description |
|--------|-------------|
| ANALYZERIDENTITY | `INTERNAL_ANALYZER`, `OSSINDEX_ANALYZER`, etc. |
| ATTRIBUTED_ON | When the finding was made |
| COMPONENT_ID | FK to the affected component |
| VULNERABILITY_ID | FK to the vulnerability |
| REFERENCE_URL | Link to the source advisory |

**Row count:** 158

### ANALYSIS

Audit trail for vulnerability triage. When a team member reviews a finding, their assessment is stored here.

| Column | Description |
|--------|-------------|
| STATE | `NOT_SET`, `EXPLOITABLE`, `IN_TRIAGE`, `FALSE_POSITIVE`, `NOT_AFFECTED`, `RESOLVED` |
| JUSTIFICATION | Why the state was set (e.g. `CODE_NOT_REACHABLE`) |
| RESPONSE | Planned response (e.g. `WILL_FIX`, `WORKAROUND_AVAILABLE`) |
| SUPPRESSED | Whether the finding is suppressed from metrics |
| DETAILS | Free-text notes |

**Row count:** 0

### ANALYSISCOMMENT

Comments added during vulnerability triage, linked to an analysis.

### COMPONENTANALYSISCACHE

Cache of recent analyzer results to avoid redundant API calls to OSS Index, Snyk, etc.

**Row count:** 3,315

### VULNERABLESOFTWARE

CPE-based entries from NVD describing which software versions are affected by which vulnerabilities.

**Row count:** 477,099

### VULNERABLESOFTWARE_VULNERABILITIES

Join table linking vulnerable software entries to vulnerabilities.

### VULNERABILITYALIAS

Maps vulnerability IDs across different sources (e.g. a GitHub Advisory ID to its corresponding CVE).

### VEX

Vulnerability Exploitability eXchange — records from VEX documents indicating whether a vulnerability is actually exploitable in a given context.

**Row count:** 0

### AFFECTEDVERSIONATTRIBUTION

Tracks which source provided the affected version information for a vulnerability.

## Metrics

Dependency-Track periodically calculates and stores metrics snapshots.

### PROJECTMETRICS

Per-project vulnerability and policy violation counts over time.

| Key columns | Description |
|-------------|-------------|
| CRITICAL, HIGH, MEDIUM, LOW | Vulnerability counts by severity |
| VULNERABILITIES | Total vulnerability count |
| VULNERABLECOMPONENTS | Number of components with vulnerabilities |
| COMPONENTS | Total component count |
| FINDINGS_TOTAL, FINDINGS_AUDITED | Audit progress |
| POLICYVIOLATIONS_FAIL/WARN/INFO | Policy violation counts |
| RISKSCORE | Calculated risk score |
| FIRST_OCCURRENCE, LAST_OCCURRENCE | Metric time window |

**Row count:** 6

### PORTFOLIOMETRICS

Organization-wide metrics across all projects. Same structure as PROJECTMETRICS but aggregated.

**Row count:** 4

### DEPENDENCYMETRICS

Per-component metrics snapshots (risk scores, vulnerability counts per component).

**Row count:** 2,062

### VULNERABILITYMETRICS

Aggregate statistics about the vulnerability database itself (total CVEs by year, source, etc.).

**Row count:** 459

## Policy Engine

### POLICY

Policy definitions with name, operator (ANY/ALL), and violation state (FAIL/WARN/INFO).

**Row count:** 2

### POLICYCONDITION

Conditions attached to policies (e.g. `SEVERITY IS CRITICAL`, `LICENSE_GROUP IS Copyleft`).

| Column | Description |
|--------|-------------|
| SUBJECT | What to match: `SEVERITY`, `LICENSE_GROUP`, `PACKAGE_URL`, `CWE`, etc. |
| OPERATOR | `IS`, `IS_NOT`, `MATCHES`, `NO_MATCH` |
| VALUE | The value to compare against |
| POLICY_ID | FK to the parent policy |

**Row count:** 3

### POLICYVIOLATION

Records of components that triggered a policy condition.

| Column | Description |
|--------|-------------|
| TYPE | `SECURITY`, `LICENSE`, `OPERATIONAL` |
| COMPONENT_ID | FK to the violating component |
| POLICYCONDITION_ID | FK to the matched condition |
| PROJECT_ID | FK to the project |

**Row count:** 0

### POLICY_PROJECTS

Join table scoping policies to specific projects (empty = global policy).

### POLICY_TAGS

Join table scoping policies to projects with specific tags.

### VIOLATIONANALYSIS

Audit trail for policy violation triage (similar to ANALYSIS for vulnerabilities).

### VIOLATIONANALYSISCOMMENT

Comments on policy violation triage decisions.

## Access Management

### TEAM

Groups of users and API keys with shared permissions. Default teams: Administrators, Automation, Badge Viewers, Portfolio Managers.

**Row count:** 4

### MANAGEDUSER

Locally managed user accounts (username, password hash, email).

**Row count:** 1

### LDAPUSER / OIDCUSER

Users authenticated via LDAP or OpenID Connect.

### APIKEY

API keys for programmatic access. Each key belongs to a team.

| Column | Description |
|--------|-------------|
| APIKEY | The key value (encrypted) |
| CREATED | Creation timestamp |
| COMMENT | Optional description |
| TEAM_ID | FK to the owning team |

**Row count:** 1

### PERMISSION

Available permission types (e.g. `BOM_UPLOAD`, `VIEW_PORTFOLIO`, `PROJECT_CREATION_UPLOAD`).

**Row count:** 14

### Join Tables

| Table | Links |
|-------|-------|
| APIKEYS_TEAMS | API keys to teams |
| TEAMS_PERMISSIONS | Teams to permissions |
| MANAGEDUSERS_TEAMS | Managed users to teams |
| MANAGEDUSERS_PERMISSIONS | Direct user permissions |
| LDAPUSERS_TEAMS / LDAPUSERS_PERMISSIONS | LDAP user associations |
| OIDCUSERS_TEAMS / OIDCUSERS_PERMISSIONS | OIDC user associations |
| PROJECT_ACCESS_TEAMS | Project-level team access |

### MAPPEDLDAPGROUP / MAPPEDOIDCGROUP

Maps external identity provider groups to Dependency-Track teams.

## Licensing

### LICENSE

Catalog of known software licenses (SPDX identifiers, full text, OSI approval status).

**Row count:** 778

### LICENSEGROUP

License categories: Copyleft, Permissive, Public Domain, etc.

**Row count:** 4

### LICENSEGROUP_LICENSE

Join table linking licenses to their groups.

## Notifications

### NOTIFICATIONPUBLISHER

Available notification channels (Slack, MS Teams, Email, Webhook, etc.).

**Row count:** 8

### NOTIFICATIONRULE

Alert rules defining which events trigger notifications and where to send them.

| Key columns | Description |
|-------------|-------------|
| SCOPE | `PORTFOLIO` or `SYSTEM` |
| NOTIFICATION_LEVEL | `INFORMATIONAL`, `WARNING`, `ERROR` |
| NOTIFY_ON | Event types to monitor |
| PUBLISHER_ID | FK to the notification channel |

**Row count:** 0

### NOTIFICATIONRULE_PROJECTS / NOTIFICATIONRULE_TAGS / NOTIFICATIONRULE_TEAMS

Join tables scoping notification rules to specific projects, tags, or teams.

## Repository Metadata

### REPOSITORY

Package repository configurations (npm registry, Maven Central, PyPI, etc.) used to check for latest versions.

**Row count:** 17

### REPOSITORY_META_COMPONENT

Cached metadata from package registries (latest version, published date) for components.

**Row count:** 1,368

## Configuration

### CONFIGPROPERTY

System configuration key-value pairs (database settings, analyzer credentials, CORS config, etc.).

**Row count:** 100

### SCHEMAVERSION

Tracks the database schema version for migrations.

### INSTALLEDUPGRADES

Records of applied upgrade scripts.

### EVENTSERVICELOG

Internal event processing log.

## Entity Relationship Overview

```
PROJECT ──< COMPONENT ──< COMPONENTS_VULNERABILITIES >── VULNERABILITY
   │              │                                           │
   │              ├──< FINDINGATTRIBUTION                     │
   │              │                                           │
   │              ├──< ANALYSIS                               │
   │              │                                           │
   │              └──< POLICYVIOLATION >── POLICYCONDITION >── POLICY
   │
   ├──< BOM (upload metadata)
   ├──< PROJECTMETRICS (time-series metrics)
   └──< PROJECT_METADATA
```

## Key Queries

### All vulnerabilities with components and projects

```sql
SELECT p."NAME", p."VERSION", c."NAME" AS component, c."VERSION" AS comp_version,
       v."VULNID", v."SEVERITY", v."EPSSSCORE"
FROM "VULNERABILITY" v
JOIN "COMPONENTS_VULNERABILITIES" cv ON cv."VULNERABILITY_ID" = v."ID"
JOIN "COMPONENT" c ON c."ID" = cv."COMPONENT_ID"
JOIN "PROJECT" p ON p."ID" = c."PROJECT_ID"
ORDER BY v."EPSSSCORE" DESC NULLS LAST;
```

### Components with no vulnerabilities

```sql
SELECT c."NAME", c."VERSION", p."NAME" AS project
FROM "COMPONENT" c
JOIN "PROJECT" p ON p."ID" = c."PROJECT_ID"
LEFT JOIN "COMPONENTS_VULNERABILITIES" cv ON cv."COMPONENT_ID" = c."ID"
WHERE cv."VULNERABILITY_ID" IS NULL;
```

### Vulnerability counts by source

```sql
SELECT "SOURCE", COUNT(*) FROM "VULNERABILITY" GROUP BY "SOURCE" ORDER BY COUNT(*) DESC;
```
