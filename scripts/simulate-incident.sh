#!/usr/bin/env bash
# Simulates the two incidents the alert rules in prometheus/alert.rules.yml
# are meant to catch, so you can confirm the whole pipeline actually
# works end-to-end: Prometheus rule fires -> Alertmanager -> Slack.
#
# Usage:
#   ./scripts/simulate-incident.sh cpu       # load the host CPU for 90s
#   ./scripts/simulate-incident.sh down      # stop selfapp for 90s
set -euo pipefail

MODE="${1:-}"

if [ "${MODE}" != "cpu" ] && [ "${MODE}" != "down" ]; then
  echo "Usage: $0 <cpu|down>" >&2
  exit 1
fi

if [ "${MODE}" = "cpu" ]; then
  CPUS="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)"
  echo "[INFO] Loading ${CPUS} CPU core(s) for 90s using a throwaway stress container."
  echo "[INFO] This loads the REAL host/VM CPU (containers share the host"
  echo "[INFO] kernel's CPU by default, no cgroup limit is set here), so"
  echo "[INFO] node-exporter should see it and HighCPUUsage should fire"
  echo "[INFO] within a couple of minutes (2m 'for' duration + scrape interval)."
  echo "[INFO] Watch it live at: http://localhost:9090/alerts"
  docker run --rm polinux/stress stress --cpu "${CPUS}" --timeout 90s
  echo "[DONE] Stress finished. The alert should auto-resolve within a few minutes."

elif [ "${MODE}" = "down" ]; then
  echo "[INFO] Stopping selfapp for 90s to trigger InstanceDown."
  echo "[INFO] Watch it live at: http://localhost:9090/alerts"
  docker stop selfapp
  echo "[INFO] selfapp stopped. Waiting 90s before restarting it..."
  sleep 90
  docker start selfapp
  echo "[DONE] selfapp restarted. The alert should auto-resolve within a few minutes."
fi

echo ""
echo "Check Slack (#alerts) for the notification, and Alertmanager's own"
echo "UI at http://localhost:9093 to confirm it registered the alert even"
echo "if the Slack webhook itself isn't configured correctly yet."
