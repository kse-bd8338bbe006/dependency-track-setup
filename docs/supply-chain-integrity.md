# Supply Chain Integrity: Hash Verification

## Overview

When an SBOM is uploaded to Dependency-Track, each component can include cryptographic hashes (MD5, SHA-1, SHA-256, SHA-512, BLAKE2B, BLAKE3). These hashes are computed from the actual package files on disk by the SBOM generator (Trivy, Syft, CycloneDX plugins).

Hash-based security operates in two modes: **reactive** (flag known-bad) and **proactive** (verify against source of truth). Understanding the difference is critical for building a complete supply chain security strategy.

## Reactive vs Proactive Verification

| Aspect | Reactive | Proactive |
|--------|----------|-----------|
| **What it does** | Flags components matching known-bad hashes | Verifies component hashes against the original registry |
| **When it triggers** | After a compromise is discovered | Before or during every build |
| **Data source** | Threat intelligence feeds, advisories | Package registry (Maven Central, npm, PyPI) |
| **Coverage** | Only known incidents | All components |
| **Speed** | Instant (hash lookup) | Slower (needs registry calls) |
| **Dependency-Track support** | Yes (policy engine) | No (handled by build tools) |

### Reactive: Flag Known-Bad Hashes

This is what Dependency-Track's policy engine does. You create a policy condition with `COMPONENT_HASH` subject and the SHA-256 of a compromised package. If any component in any project matches that hash, a policy violation is raised.

**Use case:** A backdoored package is discovered (e.g. `xz-utils` 5.6.0/5.6.1 backdoor in March 2024). Security teams publish the malicious file's hash. You add it to a Dependency-Track policy to instantly check if it exists anywhere in your portfolio.

**Limitation:** You can only flag what you already know about. Zero-day supply chain attacks are invisible until someone discovers and publishes the bad hash.

### Proactive: Verify Against Registry

This happens at build time, before anything reaches Dependency-Track. Build tools and package managers verify that downloaded packages match the hashes published by the registry.

| Tool | How it verifies |
|------|----------------|
| **Maven/Gradle** | Verifies checksums on download from Maven Central |
| **npm** | `npm audit signatures` verifies registry signatures |
| **pip** | Supports `--require-hashes` to enforce hash checking |
| **Docker/cosign** | Verifies image signatures and layer digests |
| **SLSA/in-toto** | Full supply chain attestation and provenance verification |

**Dependency-Track does not do proactive verification.** It stores the hashes from the SBOM but does not fetch the original hash from the registry to compare. This is by design — proactive verification belongs in the build pipeline, not in the analysis platform.

## Where Original Hashes Come From

Each package registry publishes hashes alongside artifacts:

### Maven Central

Every artifact has hash files alongside it:

```
https://repo1.maven.org/maven2/org/apache/commons/commons-lang3/3.14.0/
├── commons-lang3-3.14.0.jar
├── commons-lang3-3.14.0.jar.md5
├── commons-lang3-3.14.0.jar.sha1
├── commons-lang3-3.14.0.jar.sha256
└── commons-lang3-3.14.0.jar.sha512
```

```bash
# Get SHA-256 of a Maven artifact
curl -s https://repo1.maven.org/maven2/org/apache/commons/commons-lang3/3.14.0/commons-lang3-3.14.0.jar.sha256
```

### npm

```bash
# Get integrity hash (SHA-512 in SRI format)
npm view express dist.integrity

# Get SHA-1
npm view express dist.shasum

# Full metadata via registry API
curl -s https://registry.npmjs.org/express/latest | jq '.dist'
```

### PyPI

```bash
# JSON API includes SHA-256 and MD5 for every release file
curl -s https://pypi.org/pypi/requests/json | jq '.urls[0].digests'
```

### Docker/OCI

```bash
# Image manifest contains SHA-256 digests for every layer
docker manifest inspect alpine:latest | jq '.config.digest'
```

### NuGet

```bash
# Package catalog includes content hash
curl -s https://api.nuget.org/v3/registration5-gz-semver2/newtonsoft.json/index.json | jq '.items[0]'
```

## Where to Get Known-Bad Hashes

There is no single, unified API that provides a feed of known-compromised package hashes. Bad hashes come from multiple sources:

### Public Sources

| Source | What it provides | URL |
|--------|-----------------|-----|
| **OSV (Open Source Vulnerabilities)** | Google's aggregated vulnerability database. Some entries include affected package hashes. API available. | https://osv.dev |
| **GitHub Advisory Database** | Security advisories with affected version ranges (not hashes directly, but can be cross-referenced). | https://github.com/advisories |
| **Snyk Vulnerability DB** | Commercial database with affected package details. | https://security.snyk.io |
| **Sonatype OSS Index** | Free API for querying component vulnerabilities by coordinates. | https://ossindex.sonatype.org |
| **NVD (National Vulnerability Database)** | CVEs with CPE references. Does not include package hashes directly. | https://nvd.nist.gov |
| **CISA KEV (Known Exploited Vulnerabilities)** | List of actively exploited vulnerabilities. No hashes, but useful for prioritization. | https://www.cisa.gov/known-exploited-vulnerabilities-catalog |

### Threat Intelligence Feeds

| Source | Type | Notes |
|--------|------|-------|
| **Phylum** | Commercial | Monitors package registries for malicious packages in real-time. Publishes hashes of malicious packages. |
| **Socket.dev** | Commercial | Detects supply chain attacks in npm, PyPI. Provides package analysis API. |
| **Checkmarx Supply Chain Security** | Commercial | Formerly Dustico. Monitors for malicious packages. |
| **OpenSSF Package Analysis** | Open source | Automated analysis of packages published to npm, PyPI. Results at https://github.com/ossf/package-analysis |
| **Backstabber's Knife Collection** | Research | Academic dataset of known malicious packages. https://dasfreak.github.io/Backstabbers-Knife-Collection/ |

### Incident-Specific Hashes

When a supply chain attack is discovered, hashes are typically published in:

- **CVE descriptions** and security advisories
- **Blog posts** from security researchers
- **GitHub issues** on the affected repository
- **YARA rules** and **Sigma rules** shared by threat intel teams

Example: The `xz-utils` backdoor (CVE-2024-3094) — the compromised tarball hashes were published within hours by multiple security teams.

### OSV API Example

The closest thing to a "bad hash API" is OSV, which you can query by package:

```bash
# Query OSV for vulnerabilities in a specific package
curl -s -X POST https://api.osv.dev/v1/query \
  -H 'Content-Type: application/json' \
  -d '{
    "package": {
      "name": "express",
      "ecosystem": "npm"
    },
    "version": "4.17.1"
  }' | jq '.vulns[].id'
```

This returns vulnerability IDs but not file hashes. You would need to cross-reference the affected versions with the registry to get the actual file hashes of compromised packages.

## Trivy vs Syft: Hash Coverage

Not all SBOM generators include the same level of hash detail. This directly impacts your ability to do hash-based integrity checks.

| Feature | Trivy | Syft |
|---------|-------|------|
| License | Apache 2.0 (free) | Apache 2.0 (free) |
| Made by | Aqua Security | Anchore |
| SBOM formats | CycloneDX, SPDX | CycloneDX, SPDX, Syft JSON |
| OS package hashes | SHA-1 (partial) | SHA-256 (comprehensive) |
| App dependency hashes | Rarely included | Included when available |
| Vulnerability scanning | Built-in (`trivy` does both) | Separate tool (Grype) |
| Speed | Fast | Fast |
| Best for | Combined SBOM + vuln scanning | Maximum hash coverage for integrity checks |

### Current hash coverage in our database

With Trivy-generated SBOMs:
- 0 out of 2,061 components have SHA-256
- 432 have SHA-1 (mostly OS packages from Docker image scans)
- 43 have MD5

Switching to Syft significantly increases hash coverage, enabling hash mismatch detection and hash-based policy enforcement.

### Using Syft with our scripts

All three scripts (`upload-sbom.sh`, `scan-repo.sh`, `scan-image.sh`) support a `--generator` flag:

```bash
# Install Syft
brew install syft

# Use Syft instead of Trivy for better hash coverage
source .env
./scripts/upload-sbom.sh ./my-project my-app 1.0.0 --generator syft
./scripts/scan-repo.sh https://github.com/org/repo.git my-repo main --generator syft
./scripts/scan-image.sh ./docker my-image latest --generator syft
```

Default is still `trivy` for backward compatibility.

## Hash Mismatch Detection

If the same package `foo@1.0.0` appears in two projects with **different hashes**, something is wrong. One of them could be tampered, built from a different source, or downloaded from a different registry.

This SQL query detects hash mismatches across your portfolio:

```sql
SELECT c."NAME", c."VERSION", c."SHA_256", p."NAME" AS project
FROM "COMPONENT" c
JOIN "PROJECT" p ON p."ID" = c."PROJECT_ID"
WHERE c."SHA_256" IS NOT NULL
  AND EXISTS (
    SELECT 1 FROM "COMPONENT" c2
    WHERE c2."NAME" = c."NAME" AND c2."VERSION" = c."VERSION"
      AND c2."SHA_256" IS NOT NULL AND c2."SHA_256" != c."SHA_256"
  )
ORDER BY c."NAME", c."VERSION";
```

This only works when components have hashes — which is why Syft is recommended for integrity-focused scanning.

## Setting Up Hash-Based Policies in Dependency-Track

### Create a policy to flag a known-bad hash

```bash
source .env

# 1. Create the policy
curl -s -X PUT "$DTRACK_URL/api/v1/policy" \
  -H "X-Api-Key: $DTRACK_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Blocked Package Hashes",
    "operator": "ANY",
    "violationState": "FAIL"
  }'

# 2. Add a hash condition (replace POLICY_UUID and the hash)
curl -s -X PUT "$DTRACK_URL/api/v1/policy/POLICY_UUID/condition" \
  -H "X-Api-Key: $DTRACK_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "subject": "COMPONENT_HASH",
    "operator": "IS",
    "value": "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
  }'
```

### Check for violations

```bash
# List all policy violations
curl -s "$DTRACK_URL/api/v1/violation" \
  -H "X-Api-Key: $DTRACK_API_KEY" | jq '.[] | {component: .component.name, policy: .policyCondition.policy.name, type: .type}'
```

## Recommended Strategy

1. **Build pipeline (proactive):**
   - Enable checksum verification in Maven/Gradle/npm
   - Use `npm audit signatures` in CI
   - Sign and verify Docker images with cosign
   - Consider SLSA provenance for critical builds

2. **Dependency-Track (reactive):**
   - Create a "Blocked Hashes" policy
   - Subscribe to threat intel feeds (Phylum, Socket.dev, or OpenSSF Package Analysis)
   - When a supply chain incident is announced, add the compromised hash to the policy
   - Set up notifications to alert when a policy violation occurs

3. **Monitoring:**
   - Watch CISA KEV and OSV for new supply chain advisories
   - Follow @checkaborern, @_lostmt, @phaborernylum, @SocketSecurity on social media for early alerts
   - Join OpenSSF Slack for real-time supply chain security discussions

## Key Takeaway

No single API gives you a complete feed of "bad hashes." Supply chain integrity requires a layered approach:

- **Proactive** (build time): Package managers verify checksums → prevents tampered downloads
- **Reactive** (analysis time): Dependency-Track flags known-bad hashes → catches compromised packages already in use
- **Intelligence** (ongoing): Monitor threat feeds → keeps your reactive policies up to date
