# observability-selfapp

Capstone observability stack over selfapp-lite: Prometheus for metrics, Grafana for dashboards, Loki for logs, Alertmanager routing to Slack. Runs entirely in Docker Compose, on top of the already-running `docker-buildlab-selfapp` stack, no cloud cost.

This is the observability project from the roadmap, adapted to monitor **selfapp-lite** instead of VProfile — attaching to its real `self-net` Docker network and scraping/tailing its real containers (`selfapp`, `selfweb`, `selfdb`) rather than building a parallel demo app.

## What this deploys

| Component | Role |
|---|---|
| Prometheus | Scrapes metrics, evaluates alert rules |
| Alertmanager | Routes firing alerts to Slack |
| Grafana | Dashboards, pre-provisioned on startup |
| Loki + Grafana Alloy | Centralizes container logs: Alloy finds the app's and this stack's containers through the Docker API and ships their logs to Loki |
| Node Exporter | Host-level CPU/memory/disk metrics |
| cAdvisor | Per-container CPU/memory metrics for `selfapp`/`selfweb`/`selfdb`, no app changes required |

## Architecture

```
docker-buildlab-selfapp (separate compose project, started first)
  selfapp, selfweb, selfdb  --------- self-net (external network) --------\
                                                                            |
observability-selfapp (this project)                                      |
  prometheus  <---- scrapes ---- node-exporter, cadvisor, selfapp:8080 ----/
  prometheus  ----> alertmanager ----> Slack (#alerts)
  alloy    ----> reads Docker container logs ----> loki
  grafana     <---- queries ---- prometheus, loki
```

This stack is deliberately a **separate** Compose project rather than merged into `docker-buildlab-selfapp`'s own `docker-compose.yml` — matching how you'd actually bolt monitoring onto an existing app in practice, not something baked into the app's own deployment.

## Prerequisites

- Docker Desktop or Docker Engine with Docker Compose v2 (check with `docker compose version`)
- `docker-buildlab-selfapp`'s own `docker-compose.yml` already running (creates the `self-net` network this stack attaches to)
- A free Slack workspace + an Incoming Webhook (see below)

## Slack setup

1. Create a channel called `#alerts` in a Slack workspace you own (a free workspace is enough).
2. Go to https://api.slack.com/apps → **Create New App** → **From scratch**, name it `observability-selfapp` and pick your workspace.
3. **Incoming Webhooks** → turn **Activate Incoming Webhooks** on → **Add New Webhook** → choose `#alerts` → **Allow**.
4. Copy the webhook URL (`https://hooks.slack.com/services/...`) into `.env` as `SLACK_WEBHOOK_URL`. Never put it in a tracked file: anyone with the URL can post to your channel.

## Setup

```bash
cp .env.example .env
# edit .env: GRAFANA_ADMIN_PASSWORD and SLACK_WEBHOOK_URL

./scripts/up.sh
```

`up.sh` checks that `self-net` already exists (i.e. selfapp is already running) before starting anything, and fails with a clear message instead of starting Prometheus against nothing.

Grafana: http://localhost:3000 (login: `admin` / whatever you set as `GRAFANA_ADMIN_PASSWORD`)
Prometheus: http://localhost:9090
Alertmanager: http://localhost:9093
Alloy (log pipeline): http://localhost:12345

Two dashboards are pre-provisioned under the "selfapp" folder: **System Overview** and **Application Overview** — no manual import needed, Grafana loads them from `grafana/dashboards/*.json` on startup via the provisioning config in `grafana/provisioning/`.

## Testing the alert pipeline end-to-end

```bash
./scripts/simulate-incident.sh cpu    # loads the host CPU for 90s -> HighCPUUsage
./scripts/simulate-incident.sh down   # stops selfapp for 90s -> InstanceDown
```

Watch http://localhost:9090/alerts for the rule to go from inactive -> pending -> firing, and check the `#alerts` Slack channel for the notification. `InstanceDown` also fires for real if `selfapp` crashes on its own, not just during this deliberate test.

## How the Slack webhook stays out of Git

Alertmanager can't read environment variables in its config file, but it can read the webhook from a file (`slack_api_url_file`). Docker Compose creates that file from `SLACK_WEBHOOK_URL` in `.env` (the `secrets:` section of `docker-compose.yml`) and mounts it at `/run/secrets/slack_webhook` in the Alertmanager container only. So `alertmanager/alertmanager.yml` is a normal tracked file with no secrets in it, and the URL exists only in the git-ignored `.env` and in that mounted file.

## Exporting dashboards (the roadmap's actual deliverable)

The two dashboard JSON files in `grafana/dashboards/` are already the exportable artifact the roadmap asks for — written directly as JSON here rather than exported from a running Grafana UI, since I don't have a live instance in this environment to export from. If you tweak either dashboard in Grafana's UI, re-export it (Dashboard settings -> JSON Model -> copy) and overwrite the matching file here, so the repo stays the source of truth rather than drifting from what's actually configured.

## What I could verify vs. what's unverified

Grounded in real files: image/service names match `docker-compose.yml` exactly (`selfapp:8080`, `selfdb`, `selfweb`), and the flagged Micrometer gap is a fact checked directly against your `pom.xml`, not a guess.

Not tested against a running stack — no Docker, Prometheus, Grafana, or Loki available in the environment I built this in:
- Prometheus/Alertmanager/Loki/Promtail YAML validated with a YAML parser and reviewed against each project's current documented config schema, but never loaded by the real binaries.
- Both Grafana dashboard JSON files validated as syntactically correct JSON and reviewed against Grafana's dashboard schema by hand, but never rendered in an actual Grafana instance — panel layout or a subtly wrong field name wouldn't show up until you load them for real.
- The PromQL queries (CPU/memory/disk formulas, the cAdvisor container-name matching, the Micrometer HTTP metric names) are standard, widely-documented patterns for these exact exporters, not queries tested against live data.

Run `docker compose config` first to catch any interpolation issues, then `./scripts/up.sh`, and treat the first real look at both dashboards as the actual test of everything above.

## Known gaps

- `LowDiskSpace` and `HighCPUUsage` thresholds (10% / 80%) are reasonable lab defaults, not tuned against any real workload.
- No mysqld_exporter for `selfdb`-specific metrics (connection counts, query rates) — node-exporter and cAdvisor only see it as "a container using CPU/RAM," not "a database with N active connections." A natural stretch addition, not implemented here to stay within the roadmap's original scope.
- Loki retention is set to 7 days, a lab-appropriate default with no consideration of disk usage at scale.
- No dashboard for Alertmanager's own health/silences — you'd check its UI directly (http://localhost:9093) rather than through Grafana.
