# Trivy vs Syft: SBOM Generator Comparison

## Overview

Both Trivy and Syft are free, open-source tools that generate SBOMs in CycloneDX format. They serve different strengths — Trivy is better for combined vulnerability scanning + SBOM generation, while Syft produces SBOMs with better hash coverage for supply chain integrity checks.

## Feature Comparison

| Feature | Trivy | Syft |
|---------|-------|------|
| License | Apache 2.0 (free) | Apache 2.0 (free) |
| Made by | Aqua Security | Anchore |
| SBOM formats | CycloneDX, SPDX | CycloneDX, SPDX, Syft JSON |
| Vulnerability scanning | Built-in | Separate tool (Grype) |
| Dev dependencies | `--include-dev-deps` flag | Not included by default |
| OS package hashes | SHA-1 (partial) | SHA-256 (comprehensive) |
| App dependency hashes | Rarely included | Included when available |
| Dependency tree depth | Deep (resolves transitive via lock files) | Catalogs what's on disk |
| Speed | Fast | Fast |

## Hash Coverage: Real-World Test

We scanned the same two projects with both tools and compared what ended up in Dependency-Track:

### my-app (small Node.js project)

| Metric | Trivy | Syft |
|--------|-------|------|
| Components found | 66 | 77 |
| SHA-256 hashes | 0 (0%) | 4 (5.2%) |
| SHA-1 hashes | 0 | 4 |

### sso-mfe-keycloak (large Node.js monorepo)

| Metric | Trivy | Syft |
|--------|-------|------|
| Components found | 1,453 | 62 |
| SHA-256 hashes | 0 (0%) | 18 (29%) |
| SHA-1 hashes | 0 | 18 |

### sso-mfe-keycloak-image (Docker image scan)

| Metric | Trivy | Syft |
|--------|-------|------|
| Components found | 476 | — |
| SHA-256 hashes | 0 (0%) | — |
| SHA-1 hashes | 432 (91%) | — |

## Key Differences

### Component Count

Trivy with `--include-dev-deps` resolves the full dependency tree from lock files (package-lock.json, go.sum, etc.), including all transitive dev dependencies. This is why Trivy found 1,453 components for sso-mfe-keycloak vs Syft's 62.

Syft catalogs packages that are physically present on disk (in node_modules, site-packages, etc.). It doesn't resolve transitive dependencies from lock files the same way — it discovers what's actually installed.

**Tradeoff:** Trivy gives broader vulnerability coverage (more components = more potential CVE matches). Syft gives a more accurate picture of what's actually deployed.

### Hash Coverage

Trivy generates zero SHA-256 hashes for npm packages. For Docker image scans, it includes SHA-1 for OS packages (RPM, dpkg) but not for application dependencies.

Syft includes SHA-256 hashes for packages where the hash can be computed from the installed files. For npm, this means packages that are physically in node_modules get hashed. Coverage isn't 100% because not all package types support file-level hashing.

**Tradeoff:** If hash-based integrity checking matters (supply chain security, hash mismatch detection, policy enforcement on COMPONENT_HASH), Syft is the better choice.

## When to Use Each

| Scenario | Recommended Tool |
|----------|-----------------|
| CI/CD vulnerability scanning | **Trivy** — built-in vuln scanner, single tool |
| Maximum dependency coverage | **Trivy** — `--include-dev-deps` resolves full tree |
| Docker image scanning | **Trivy** — better OS package detection |
| Supply chain integrity checks | **Syft** — SHA-256 hashes for policy enforcement |
| Hash mismatch detection | **Syft** — meaningful hashes to compare |
| Compliance audits requiring hashes | **Syft** — evidence of component integrity |
| Quick scan during development | **Trivy** — faster, more familiar |

## Using Both Together

The tools are complementary. A recommended approach:

1. **Trivy in CI/CD** — fast vulnerability feedback on every PR, broad dependency coverage
2. **Syft before release** — generate a hash-rich SBOM for the release artifact, upload to Dependency-Track for integrity tracking

```bash
source .env

# Daily CI: Trivy for vulnerability coverage
./scripts/scan-repo.sh https://github.com/org/app.git my-app main

# Release: Syft for integrity
./scripts/scan-repo.sh https://github.com/org/app.git my-app v1.2.0 --generator syft
```

## Installation

```bash
# Trivy
brew install trivy

# Syft
brew install syft

# Verify
trivy --version
syft --version
```

## Script Usage

All three scanning scripts support the `--generator` flag:

```bash
source .env

# Local directory scan
./scripts/upload-sbom.sh ./my-project my-app 1.0.0 --generator syft

# Git repo scan
./scripts/scan-repo.sh https://github.com/org/repo.git my-repo main --generator syft

# Docker image scan
./scripts/scan-image.sh ./docker my-image latest --generator syft
```

Default is `trivy` when `--generator` is not specified.
