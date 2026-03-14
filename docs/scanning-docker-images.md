# Scanning Docker Images

## Why Scan Docker Images?

A source code scan (`trivy fs`) only detects vulnerabilities in application dependencies declared in lock files (e.g. `package-lock.json`, `go.sum`). It misses:

- **OS-level packages** — `glibc`, `openssl`, `curl`, and other system libraries installed in the base image
- **Runtime dependencies** — packages installed via `RUN apt-get install`, `RUN yum install`, or `RUN apk add` during the Docker build
- **Embedded binaries** — tools and libraries bundled in the base image (e.g. Java runtime in Keycloak, Node.js runtime in `node:18-alpine`)

Scanning the **built Docker image** with `trivy image` captures all of these, providing a complete view of what runs in production.

## Source Scan vs Image Scan

| Aspect | Source scan (`trivy fs`) | Image scan (`trivy image`) |
|--------|------------------------|---------------------------|
| Application dependencies | Yes | Yes |
| OS packages (base image) | No | Yes |
| Packages from `RUN` commands | No | Yes |
| Requires Docker build | No | Yes |
| Speed | Fast | Slower (needs build + pull) |
| When to use | During development, PR checks | Before deploying to production |

Both scans are complementary. Use source scans for fast CI feedback, and image scans before releasing Docker images.

## Usage

The script `scripts/scan-image.sh` builds a Docker image from a Dockerfile, generates an SBOM with Trivy, and uploads it to Dependency-Track.

```bash
source .env
./scripts/scan-image.sh <path-to-dockerfile-dir> <project-name> [project-version]
```

### Parameters

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `path-to-dockerfile-dir` | Yes | — | Directory containing the Dockerfile |
| `project-name` | Yes | — | Project name in Dependency-Track |
| `project-version` | No | `latest` | Project version in Dependency-Track |

### Required Environment Variables

| Variable | Description |
|----------|-------------|
| `DTRACK_URL` | Dependency-Track API URL |
| `DTRACK_API_KEY` | Dependency-Track API key |

### Examples

```bash
# Scan a Keycloak image
./scripts/scan-image.sh ./keycloak sso-keycloak-image 26.1.4

# Scan from a cloned repo
./scripts/scan-image.sh /tmp/my-repo/app my-app-image 1.0.0

# Scan with default version (latest)
./scripts/scan-image.sh ./docker my-service
```

## What the Script Does

1. **Builds the Docker image** — runs `docker build` in the specified directory, tagging the image as `dtrack-scan/<project-name>:<version>`
2. **Generates an SBOM** — runs `trivy image --format cyclonedx` against the built image, detecting OS packages, system libraries, and application dependencies
3. **Uploads to Dependency-Track** — sends the base64-encoded SBOM via the `/api/v1/bom` API with auto-create enabled
4. **Cleans up** — removes the temporary image and working files on exit

## Real-World Example

Scanning the Keycloak Dockerfile from `sso-mfe-keycloak`:

```bash
source .env
./scripts/scan-image.sh /tmp/sso-scan/keycloak sso-mfe-keycloak-image 26.1.4
```

Trivy detected **Red Hat 9.5** as the OS (the Keycloak base image runs on UBI9) and found:

| Severity | Count |
|----------|-------|
| HIGH | 17 |
| MEDIUM | 28 |
| LOW | 11 |
| UNASSIGNED | 3 |
| **Total** | **59** |

These 59 vulnerabilities come from OS packages and Java dependencies inside the Keycloak image — none of them would appear in a source-only scan.

## Scripts Comparison

| Script | Scans | Best for |
|--------|-------|----------|
| `upload-sbom.sh` | Local project directory | Projects already checked out |
| `scan-repo.sh` | Git repository (clones + installs deps) | Scanning any repo by URL |
| `scan-image.sh` | Built Docker image | Pre-deployment image validation |
