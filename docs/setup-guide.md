# Dependency-Track Setup Guide

This guide covers the full setup of OWASP Dependency-Track with PostgreSQL persistence, SBOM generation with Trivy, and automated uploads via a shell script and a reusable GitHub Actions workflow.

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Prerequisites](#prerequisites)
- [1. Running Dependency-Track](#1-running-dependency-track)
- [2. Initial Configuration](#2-initial-configuration)
- [3. Generating and Uploading SBOMs Locally](#3-generating-and-uploading-sboms-locally)
- [4. Reusable GitHub Actions Workflow](#4-reusable-github-actions-workflow)
- [Project Structure](#project-structure)

## Architecture Overview

The setup consists of three services:

| Service | Description | Port |
|---------|-------------|------|
| **dtrack-apiserver** | Dependency-Track API server (Java) | `8081` |
| **dtrack-frontend** | Dependency-Track web UI (Nginx) | `8080` |
| **postgres** | PostgreSQL 16 database for persistent storage | `5432` |

Data is persisted across restarts using Docker named volumes:
- `postgres-data` — PostgreSQL database files
- `dtrack-data` — Dependency-Track internal data (e.g. NVD mirror, keys)

## Prerequisites

- Docker and Docker Compose
- [Trivy](https://aquasecurity.github.io/trivy/) — for SBOM generation
- At least **12 GB of RAM** allocated to Docker (the API server requires a minimum of 4 GB heap)

## 1. Running Dependency-Track

The `docker-compose.yml` at the project root defines all three services.

Start the stack:

```bash
docker compose up -d
```

The API server takes 1–2 minutes to fully start on the first launch (it runs database migrations and downloads vulnerability databases). Monitor progress with:

```bash
docker compose logs -f dtrack-apiserver
```

Once ready:
- **Frontend (UI):** http://localhost:8080
- **API Server:** http://localhost:8081

### Key configuration in `docker-compose.yml`

- `ALPINE_DATABASE_MODE: external` — tells the API server to use an external database instead of the embedded H2
- `ALPINE_DATABASE_URL` — JDBC connection string pointing to the `postgres` service
- `JAVA_OPTIONS: "-Xmx8g"` — sets the JVM heap to 8 GB (minimum 4 GB required)
- PostgreSQL `healthcheck` — ensures the API server only starts after the database is ready

## 2. Initial Configuration

### Change the default password

1. Open http://localhost:8080
2. Log in with `admin` / `admin`
3. You will be prompted to change the password on first login

### Create an API key

1. Go to **Administration** → **Access Management** → **Teams**
2. Select the **Automation** team
3. Click **Generate API Key** and copy it
4. The Automation team needs the following permissions:
   - `BOM_UPLOAD`
   - `VIEW_PORTFOLIO`
   - `PROJECT_CREATION_UPLOAD`

### Store credentials locally

Create a `.env` file in the project root (this file is not committed to git):

```
DTRACK_URL=http://localhost:8081
DTRACK_API_KEY=<your-api-key>
```

## 3. Generating and Uploading SBOMs Locally

The script `scripts/upload-sbom.sh` automates SBOM generation with Trivy and upload to Dependency-Track.

### Usage

```bash
source .env
./scripts/upload-sbom.sh <project-path> <project-name> <project-version>
```

### Example

```bash
source .env
./scripts/upload-sbom.sh /path/to/my-app my-app 1.0.0
```

### What the script does

1. **Generates an SBOM** — runs `trivy fs --format cyclonedx` on the given project path to produce a CycloneDX JSON SBOM
2. **Base64 encodes** the SBOM — the Dependency-Track API expects the BOM payload as a base64-encoded string
3. **Uploads to Dependency-Track** — sends a `PUT` request to `/api/v1/bom` with the project name, version, and encoded SBOM
4. **Auto-creates the project** — if a project with the given name and version doesn't exist, it is created automatically (`autoCreate: true`)
5. **Cleans up** — the temporary SBOM file is deleted on exit

### Required environment variables

| Variable | Description |
|----------|-------------|
| `DTRACK_URL` | Dependency-Track API URL (e.g. `http://localhost:8081`) |
| `DTRACK_API_KEY` | API key from the Automation team |

## 4. Reusable GitHub Actions Workflow

The file `.github/workflows/upload-sbom.yml` is a **callable (reusable) workflow** that any repository can reference to generate and upload an SBOM as part of its CI/CD pipeline.

### Workflow steps

1. **Checkout** — clones the calling repository
2. **Install Trivy** — installs Trivy from the official APT repository
3. **Generate SBOM** — runs `trivy fs --format cyclonedx` on the specified scan path
4. **Upload SBOM** — sends the base64-encoded SBOM to the Dependency-Track API
5. **Save artifact** — uploads the SBOM JSON file as a GitHub Actions artifact for later reference

### How to call this workflow from another repository

Add a workflow file (e.g. `.github/workflows/sbom.yml`) in your repository:

```yaml
name: SBOM Upload

on:
  push:
    branches: [main]

jobs:
  sbom:
    uses: <org>/dependency-track-setup/.github/workflows/upload-sbom.yml@main
    with:
      project-name: "my-app"
      project-version: "1.0.0"
    secrets:
      dtrack-url: ${{ secrets.DTRACK_URL }}
      dtrack-api-key: ${{ secrets.DTRACK_API_KEY }}
```

### Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `project-name` | Yes | — | Project name in Dependency-Track |
| `project-version` | Yes | — | Project version in Dependency-Track |
| `scan-path` | No | `.` | Path to scan for SBOM generation |

### Secrets

| Secret | Description |
|--------|-------------|
| `dtrack-url` | Dependency-Track API URL |
| `dtrack-api-key` | Dependency-Track API key |

These secrets must be configured in the calling repository's **Settings** → **Secrets and variables** → **Actions**.

## Project Structure

```
dependency-track-setup/
├── .env                              # Local credentials (not committed)
├── .github/
│   └── workflows/
│       └── upload-sbom.yml           # Reusable GitHub Actions workflow
├── docker-compose.yml                # Dependency-Track + PostgreSQL stack
├── docs/
│   ├── setup-guide.md                # This guide
│   └── uploading-sbom.md             # SBOM upload reference
└── scripts/
    └── upload-sbom.sh                # Local SBOM generation and upload script
```
