# Uploading SBOM to Dependency-Track

## Prerequisites

- Dependency-Track is running (API server at `http://localhost:8081`, frontend at `http://localhost:8080`)
- You have an SBOM file in CycloneDX (recommended) or SPDX format

## Generating an SBOM

If you don't have an SBOM yet, use one of these tools:

| Tool | Command | Notes |
|------|---------|-------|
| Syft | `syft dir:. -o cyclonedx-json > sbom.json` | Works with any project |
| Trivy | `trivy fs --format cyclonedx -o sbom.json .` | Works with any project |
| CycloneDX (Node) | `npx @cyclonedx/cyclonedx-npm --output-file sbom.json` | Node.js projects |
| CycloneDX (Python) | `cyclonedx-py environment -o sbom.json` | Python projects |
| CycloneDX (Go) | `cyclonedx-gomod mod -json -output sbom.json` | Go projects |

## Upload via UI

1. Open http://localhost:8080 and log in (default credentials: `admin` / `admin`)
2. Navigate to **Projects** → **Create Project**
3. Fill in the project name and version, then click **Create**
4. Open the project → **Components** tab → click **Upload BOM**
5. Select your SBOM file and upload

## Upload via API

### Getting an API Key

1. Log in to the frontend at http://localhost:8080
2. Go to **Administration** → **Access Management** → **Teams**
3. Select a team (e.g. **Automation**)
4. Copy the existing API key or generate a new one

### Upload the SBOM

```bash
curl -X PUT http://localhost:8081/api/v1/bom \
  -H "X-Api-Key: YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"projectName\": \"my-app\",
    \"projectVersion\": \"1.0.0\",
    \"autoCreate\": true,
    \"bom\": \"$(base64 -i path/to/sbom.json)\"
  }"
```

Parameters:

- `projectName` — name of the project (will be created if `autoCreate` is `true`)
- `projectVersion` — version string for the project
- `autoCreate` — set to `true` to create the project automatically if it doesn't exist
- `bom` — base64-encoded SBOM content

### Upload to an Existing Project by UUID

If you already know the project UUID:

```bash
curl -X PUT http://localhost:8081/api/v1/bom \
  -H "X-Api-Key: YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"project\": \"PROJECT_UUID\",
    \"bom\": \"$(base64 -i path/to/sbom.json)\"
  }"
```

You can find the project UUID in the URL when viewing a project in the frontend, or by querying the API:

```bash
curl -H "X-Api-Key: YOUR_API_KEY" http://localhost:8081/api/v1/project
```

## Supported Formats

Dependency-Track supports the following SBOM formats:

- **CycloneDX** (recommended) — JSON and XML, versions 1.0 through 1.6
- **SPDX** — tag-value and RDF formats
