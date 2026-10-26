#!/usr/bin/env bash
# Causes a real incident on purpose, to watch the whole alert pipeline work:
# Prometheus rule -> Alertmanager -> Slack (FIRING, then RESOLVED after the
# script puts everything back).
#
# Usage: ./scripts/simulate-incident.sh <cpu|app|db> [seconds]
#   cpu  keeps every CPU of Docker's VM busy  -> HighCPUUsage (warning)
#   app  stops selfapp                        -> InstanceDown (critical)
#   db   stops selfdb (MySQL)                 -> ContainerDown (critical)
#
# Default duration: 240 seconds. An alert reaches Slack after its "for:"
# time (1-2 minutes) plus up to ~1 minute of scrape, evaluation and
# Alertmanager's group_wait. Whatever happens (even Ctrl+C), the script
# restores what it stopped.
set -euo pipefail

MODE="${1:-}"
DURATION="${2:-240}"

usage() {
  echo "Usage: $0 <cpu|app|db> [seconds, default 240]" >&2
  exit 1
}

case "${MODE}" in
  cpu | app | db) ;;
  *) usage ;;
esac
[[ "${DURATION}" =~ ^[0-9]+$ ]] || usage

restore() {
  case "${MODE}" in
    cpu) docker rm -f incident-cpu >/dev/null 2>&1 || true ;;
    app) docker start selfapp >/dev/null ;;
    db) docker start selfdb >/dev/null ;;
  esac
  echo "[DONE] Restored. Slack gets RESOLVED within ~5 minutes (Alertmanager's group_interval)."
}
# Run restore() when the script ends for any reason, including Ctrl+C
trap restore EXIT

case "${MODE}" in
  cpu)
    CPUS="$(docker info --format '{{.NCPU}}')"
    echo "[INFO] Keeping all ${CPUS} CPUs of Docker's VM busy for ${DURATION}s -> HighCPUUsage"
    # One endless loop per CPU, in a throwaway Alpine container (works on
    # Apple Silicon and Intel, nothing to install)
    docker run -d --rm --name incident-cpu alpine:3.23 \
      sh -c "for i in \$(seq ${CPUS}); do (while :; do :; done) & done; wait" >/dev/null
    ;;
  app)
    echo "[INFO] Stopping selfapp for ${DURATION}s -> InstanceDown"
    echo "[INFO] (RabbitMQNoConsumers follows: the app is also RabbitMQ's consumer)"
    docker stop selfapp >/dev/null
    ;;
  db)
    echo "[INFO] Stopping selfdb (MySQL) for ${DURATION}s -> ContainerDown"
    docker stop selfdb >/dev/null
    ;;
esac

echo "[INFO] Watch: http://localhost:9090/alerts (inactive -> pending -> firing)"
echo "[INFO]        http://localhost:9093 (Alertmanager) and Slack #alerts"

for ((elapsed = 0; elapsed < DURATION; elapsed += 30)); do
  echo "[INFO] ${elapsed}s / ${DURATION}s"
  sleep "$((DURATION - elapsed < 30 ? DURATION - elapsed : 30))"
done
