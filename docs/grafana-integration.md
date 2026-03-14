# Grafana Integration: When and Why

## Built-in vs Grafana

Dependency-Track includes a built-in **Exploit Predictions** tab that provides per-project EPSS vs CVSS scatter plots and sortable vulnerability tables. For most use cases, this is sufficient.

Grafana becomes valuable when you need capabilities beyond what the built-in UI offers.

## When You Don't Need Grafana

- You have a small number of projects
- You only need per-project vulnerability views
- The built-in Exploit Predictions scatter plot and Audit Vulnerabilities table meet your needs
- You don't use Grafana for other monitoring

## When Grafana Adds Value

### Cross-Project View

The Exploit Predictions tab is scoped to a single project. If you manage multiple projects, you have to check each one individually. Grafana can query the PostgreSQL database directly and show **all vulnerabilities across all projects** in a single dashboard, making it easier to identify the highest-risk findings portfolio-wide.

### Custom Metrics and Alerts

Grafana supports alert rules based on SQL queries. Examples:

- Alert when a new vulnerability with EPSS > 10% is detected in any project
- Alert when the total number of CRITICAL/HIGH vulnerabilities exceeds a threshold
- Notify a Slack channel or email when a specific component (e.g. `log4j`) appears in any project

These alerts are not available in Dependency-Track's built-in notification system, which focuses on event-based notifications (new vulnerability found, BOM uploaded) rather than threshold-based metrics.

### Historical Trends

Dependency-Track's dashboard shows a portfolio vulnerabilities chart over time, but it is limited in customization. Grafana can track and visualize:

- How the number of vulnerabilities changes over weeks/months
- Whether remediation efforts are reducing risk
- Which projects are improving vs accumulating debt
- EPSS score trends for specific CVEs over time

### Integration with Other Dashboards

If your team already uses Grafana for infrastructure monitoring (Prometheus, CloudWatch, etc.), adding a security panel alongside existing dashboards provides a single pane of glass. Teams can correlate deployment events with vulnerability introductions without switching tools.

## Setup

Grafana is included as an optional service in `docker-compose.yml`. It connects directly to the same PostgreSQL database used by Dependency-Track.

- **Grafana UI:** http://localhost:3000 (default credentials: `admin` / `admin`)
- **Provisioned dashboard:** EPSS Vulnerability Prioritization (under the Dependency-Track folder)

The dashboard is defined in `grafana/dashboards/epss-prioritization.json` and can be customized or extended through the Grafana UI.

## Summary

| Capability | Dependency-Track UI | Grafana |
|-----------|-------------------|---------|
| Per-project EPSS scatter plot | Yes | Yes |
| Per-project vulnerability table | Yes | Yes |
| Cross-project vulnerability view | No | Yes |
| Custom threshold alerts | No | Yes |
| Historical trend analysis | Limited | Yes |
| Integration with infra monitoring | No | Yes |
