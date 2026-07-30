#!/usr/bin/env bash
# Brings up the observability stack. Requires docker-buildlab-selfapp's
# own docker-compose.yml to already be running, since this stack attaches
# to its self-net network (see docker-compose.yml's networks section) and
# scrapes/tails its containers by name.
set -euo pipefail

cd "$(dirname "$0")/.."

if [ ! -f .env ]; then
  echo "[ERROR] .env not found. Copy .env.example to .env and fill in real values first:" >&2
  echo "  cp .env.example .env" >&2
  exit 1
fi

if ! docker network inspect self-net >/dev/null 2>&1; then
  echo "[ERROR] Docker network 'self-net' not found." >&2
  echo "[ERROR] Start docker-buildlab-selfapp's own docker-compose.yml FIRST -" >&2
  echo "[ERROR] that's what creates this network. This stack attaches to it," >&2
  echo "[ERROR] it doesn't create its own copy of selfapp." >&2
  exit 1
fi

echo "[INFO] self-net found, bringing up the observability stack..."
docker compose up -d

echo "[INFO] Waiting for Grafana to be ready..."
for _ in $(seq 1 30); do
  if curl -fs http://localhost:3000/api/health >/dev/null 2>&1; then
    echo "[DONE] Grafana is up: http://localhost:3000"
    echo "[DONE] Prometheus:    http://localhost:9090"
    echo "[DONE] Alertmanager:  http://localhost:9093"
    echo "[DONE] Check http://localhost:9090/targets - the 'selfapp' target"
    echo "[DONE] will show as DOWN until micrometer-registry-prometheus is"
    echo "[DONE] added to app/pom.xml (see README). Everything else should"
    echo "[DONE] show UP."
    exit 0
  fi
  sleep 2
done

echo "[WARN] Grafana didn't respond within 60s. Check: docker compose logs grafana" >&2
