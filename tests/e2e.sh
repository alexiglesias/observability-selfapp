#!/usr/bin/env bash
# End-to-end test of the running stacks (app + monitoring). It checks that
# data really flows, not just that containers are up:
#   1. Prometheus scrapes all targets, and the app's request metrics arrive
#   2. Grafana's data sources work and both dashboards are loaded
#   3. Loki has received fresh logs (nginx's lines for the requests just sent)
#   4. Stopping selfapp makes InstanceDown reach Alertmanager (then restarts it)
# Used by `make e2e` and by CI. Takes about 2-3 minutes.
set -euo pipefail
cd "$(dirname "$0")/.."

PROM=http://localhost:9090
ALERTMANAGER=http://localhost:9093
LOKI=http://localhost:3100
GRAFANA=http://localhost:3000
GRAFANA_PASS="$(grep -E '^GRAFANA_ADMIN_PASSWORD=' .env | cut -d= -f2-)"
EXPECTED_TARGETS=5 # prometheus, node-exporter, cadvisor, selfapp, rabbitmq

pass() { echo "[PASS] $*"; }
fail() {
  echo "[FAIL] $*" >&2
  exit 1
}

# Retry a check every 5 seconds until it passes or $1 seconds have passed
wait_for() {
  local deadline=$((SECONDS + $1))
  shift
  until "$@"; do
    ((SECONDS < deadline)) || return 1
    sleep 5
  done
}

# First value returned by a PromQL query (empty if no result)
prom_value() {
  curl -fsS --max-time 10 "${PROM}/api/v1/query" --data-urlencode "query=$1" |
    python3 -c 'import json, sys; r = json.load(sys.stdin)["data"]["result"]; print(r[0]["value"][1] if r else "")'
}

# Succeeds if a JSON API answer ($1 = URL, rest = curl options) has results
has_results() {
  local url=$1
  shift
  curl -fsS --max-time 10 -G "$@" "${url}" |
    python3 -c 'import json, sys; d = json.load(sys.stdin); d = d["data"]["result"] if isinstance(d, dict) else d; sys.exit(0 if d else 1)'
}

all_targets_up() { [[ "$(prom_value 'count(up == 1)')" == "${EXPECTED_TARGETS}" ]]; }
app_requests_recorded() { [[ -n "$(prom_value 'sum(http_server_requests_seconds_count{job="selfapp"}) > 0')" ]]; }
# selfweb (nginx) logs every request, and part 1 just sent some: fresh lines must be there
loki_has_app_logs() { has_results "${LOKI}/loki/api/v1/query_range" --data-urlencode 'query={container="selfweb"}' --data-urlencode 'limit=1'; }
instance_down_in_alertmanager() { has_results "${ALERTMANAGER}/api/v2/alerts" --data-urlencode 'filter=alertname="InstanceDown"'; }

echo "== 1. Prometheus"
wait_for 120 all_targets_up ||
  fail "expected ${EXPECTED_TARGETS} targets UP, got $(prom_value 'count(up == 1)') - see ${PROM}/targets"
pass "all ${EXPECTED_TARGETS} targets are UP"
for _ in 1 2 3 4 5; do curl -s -o /dev/null http://localhost/; done # some traffic for the app's metrics
wait_for 60 app_requests_recorded || fail "no http_server_requests metrics from selfapp"
pass "selfapp's request metrics are recorded"

echo "== 2. Grafana"
for uid in Prometheus Loki; do
  curl -fsS -u "admin:${GRAFANA_PASS}" "${GRAFANA}/api/datasources/uid/${uid}/health" | grep -q '"status":"OK"' ||
    fail "Grafana data source ${uid} is not healthy"
done
pass "data sources Prometheus and Loki are healthy"
for uid in selfapp-app-overview selfapp-system-overview; do
  curl -fsS -o /dev/null -u "admin:${GRAFANA_PASS}" "${GRAFANA}/api/dashboards/uid/${uid}" ||
    fail "dashboard ${uid} is not loaded"
done
pass "both dashboards are loaded"

echo "== 3. Loki"
wait_for 60 loki_has_app_logs || fail "no recent logs from selfweb in Loki (Alloy -> Loki pipeline)"
pass "Loki has selfweb's logs from the requests just sent"

echo "== 4. Alert pipeline (stops selfapp for up to 3 minutes)"
trap 'docker start selfapp >/dev/null' EXIT
docker stop selfapp >/dev/null
wait_for 180 instance_down_in_alertmanager || fail "InstanceDown never reached Alertmanager"
pass "InstanceDown reached Alertmanager (selfapp is being restarted)"

echo "All end-to-end checks passed."
