#!/usr/bin/env bash
# Brings up the observability stack. docker-buildlab-selfapp must already be
# running: this stack joins its network (see the networks section of
# docker-compose.yml) and scrapes/tails its containers by name.
set -euo pipefail

cd "$(dirname "$0")/.."

if [ ! -f .env ]; then
  echo "[ERROR] .env not found. Copy .env.example to .env and fill in real values first:" >&2
  echo "  cp .env.example .env" >&2
  exit 1
fi

# Warn (don't stop) if the Slack webhook is still a placeholder: everything
# else works, alerts just can't reach Slack.
if ! grep -qE '^SLACK_WEBHOOK_URL=https://hooks\.slack\.com/' .env; then
  echo "[WARN] SLACK_WEBHOOK_URL in .env is not a Slack webhook yet - alerts won't reach Slack." >&2
fi

# Same variable and default as docker-compose.yml. Read with grep rather
# than sourcing .env, so nothing in .env gets executed as shell code.
NETWORK="$(grep -E '^SELFAPP_NETWORK=' .env | cut -d= -f2- || true)"
NETWORK="${NETWORK:-docker-buildlab-selfapp_self-net}"

if ! docker network inspect "${NETWORK}" >/dev/null 2>&1; then
  echo "[ERROR] Docker network '${NETWORK}' not found." >&2
  echo "[ERROR] Start docker-buildlab-selfapp first (docker compose up -d in that repo)." >&2
  echo "[ERROR] Its network is called <folder name>_self-net. If you cloned it into a" >&2
  echo "[ERROR] differently named folder, check 'docker network ls' and set" >&2
  echo "[ERROR] SELFAPP_NETWORK in .env." >&2
  exit 1
fi

echo "[INFO] Network '${NETWORK}' found, bringing up the observability stack..."
docker compose up -d

echo "[INFO] Waiting for Grafana to be ready..."
for _ in $(seq 1 30); do
  if curl -fs http://localhost:3000/api/health >/dev/null 2>&1; then
    echo "[DONE] Grafana is up: http://localhost:3000"
    echo "[DONE] Prometheus:    http://localhost:9090"
    echo "[DONE] Alertmanager:  http://localhost:9093"
    echo "[DONE] Targets:       http://localhost:9090/targets (all should be UP)"
    exit 0
  fi
  sleep 2
done

echo "[WARN] Grafana didn't respond within 60s. Check: docker compose logs grafana" >&2
