# Configuring OSS Index Vulnerability Analyzer

Dependency-Track uses vulnerability analyzers to match components from uploaded SBOMs against known vulnerabilities. By default, the **OSS Index** analyzer is enabled but requires credentials to function.

Without OSS Index configured, Dependency-Track relies only on NVD (CPE-based matching), which does not work well for npm, PyPI, Maven, and other ecosystem-specific packages. This results in **0 vulnerabilities reported** even when components have known CVEs.

## What is OSS Index?

OSS Index is a free vulnerability database provided by Sonatype. It covers packages from npm, Maven, PyPI, NuGet, Go, and other ecosystems. It is the primary analyzer in Dependency-Track for identifying vulnerabilities in application-level dependencies.

## Setup Steps

### 1. Create a free OSS Index account

Register at https://ossindex.sonatype.org with your email address.

### 2. Get your API token

After registration, go to your account settings at https://ossindex.sonatype.org/user/settings to find your API token.

### 3. Configure via Dependency-Track API

Set the username and token using the Dependency-Track config API:

```bash
# Get an admin JWT token
TOKEN=$(curl -s -X POST http://localhost:8081/api/v1/user/login \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d 'username=admin&password=YOUR_PASSWORD')

# Set OSS Index username
curl -s -X POST http://localhost:8081/api/v1/configProperty \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "groupName": "scanner",
    "propertyName": "ossindex.api.username",
    "propertyValue": "your-email@example.com"
  }'

# Set OSS Index API token
curl -s -X POST http://localhost:8081/api/v1/configProperty \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "groupName": "scanner",
    "propertyName": "ossindex.api.token",
    "propertyValue": "your-api-token"
  }'
```

Alternatively, configure it via the UI: **Administration** → **Analyzers** → **OSS Index**.

### 4. Re-upload the SBOM

After configuring OSS Index, re-upload your SBOM to trigger a new vulnerability analysis:

```bash
source .env
./scripts/upload-sbom.sh /path/to/project my-app 1.0.0
```

### 5. Verify

Check the API server logs for confirmation that OSS Index analysis ran:

```bash
docker compose logs dtrack-apiserver | grep -i ossindex
```

You should see:

```
Starting Sonatype OSS Index analysis task
Analyzing 65 component(s)
Sonatype OSS Index analysis complete
```

If credentials are missing or invalid, the logs will show:

```
An API username or token has not been specified for use with OSS Index; Skipping
```

## Dashboard Metrics Update

After a successful analysis, the dashboard metrics may take a few minutes to refresh. The "Last Measurement" timestamp on the Portfolio Vulnerabilities chart indicates when metrics were last recalculated. You can force a refresh by navigating to the project page and back to the dashboard.
