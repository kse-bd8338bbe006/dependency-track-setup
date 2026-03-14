# EPSS Scoring in Dependency-Track

## What is EPSS?

EPSS (Exploit Prediction Scoring System) estimates the **probability that a vulnerability will be exploited in the wild within the next 30 days**. It is maintained by FIRST.org and updated daily.

Unlike CVSS, which measures the theoretical severity of a vulnerability, EPSS measures the **real-world likelihood of exploitation**. This makes it a better tool for prioritizing which vulnerabilities to fix first.

## EPSS vs CVSS

| Metric | Measures | Range | Use case |
|--------|----------|-------|----------|
| **CVSS** | Technical severity | 0.0–10.0 | Understanding impact |
| **EPSS Score** | Probability of exploitation | 0.0–1.0 (0%–100%) | Prioritizing remediation |
| **EPSS Percentile** | Relative rank among all CVEs | 0.0–1.0 (0%–100%) | Comparing vulnerabilities |

A CRITICAL CVSS vulnerability with a 0.01% EPSS score is far less urgent than a HIGH CVSS one with a 30% EPSS score.

## Where to See EPSS in Dependency-Track

### In the UI

1. Go to **Projects** → select a project → **Vulnerabilities** tab
2. Click on a specific vulnerability (e.g. CVE-2024-10491)
3. The detail view shows EPSS Score and EPSS Percentile alongside CVSS scores

### Via the API

```bash
curl -s "$DTRACK_URL/api/v1/vulnerability/project/PROJECT_UUID" \
  -H "X-Api-Key: $DTRACK_API_KEY"
```

Each vulnerability in the response includes `epssScore` and `epssPercentile` fields:

```json
{
  "vulnId": "CVE-2024-10491",
  "severity": "MEDIUM",
  "epssScore": 0.0033,
  "epssPercentile": 0.55614,
  "cvssV3BaseScore": 5.3
}
```

- `epssScore: 0.0033` — 0.33% probability of exploitation in the next 30 days
- `epssPercentile: 0.55614` — more likely to be exploited than ~56% of all known CVEs

## Using EPSS for Prioritization

| EPSS Score | Likelihood | Recommended Action |
|-----------|------------|-------------------|
| > 10% | High | Fix immediately |
| 1%–10% | Moderate | Plan fix within current sprint |
| 0.1%–1% | Low | Schedule for next cycle |
| < 0.1% | Very low | Monitor, fix when convenient |

### Combining CVSS and EPSS

The most effective approach combines both metrics:

| CVSS | EPSS | Priority |
|------|------|----------|
| Critical/High | > 1% | Highest — severe and likely to be exploited |
| Critical/High | < 0.1% | Medium — severe but unlikely to be exploited |
| Medium/Low | > 10% | Medium — low impact but actively exploited |
| Medium/Low | < 0.1% | Low — low impact and unlikely to be exploited |

## EPSS Data Updates

Dependency-Track mirrors the EPSS data automatically. On first startup, you can see the mirror task in the logs:

```bash
docker compose logs dtrack-apiserver | grep -i epss
```

```
INFO [EpssMirrorTask] Starting EPSS mirroring task
INFO [EpssMirrorTask] Downloading...
INFO [EpssMirrorTask] EPSS mirroring complete
```

EPSS data is refreshed alongside the vulnerability database updates (every 24 hours by default).
