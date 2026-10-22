#!/usr/bin/env bash
# Tears down the observability stack. Does NOT touch docker-buildlab-selfapp's
# own stack or the self-net network (self-net is external, owned by that
# other compose project, and Docker Compose never deletes networks it
# didn't create).
set -euo pipefail
cd "$(dirname "$0")/.."

echo "[INFO] Stopping the observability stack..."
docker compose down

echo "[DONE] Stopped. Data volumes (Prometheus/Grafana/Loki history) were"
echo "[DONE] left in place - run 'docker compose down -v' instead if you"
echo "[DONE] want a completely clean slate next time."
