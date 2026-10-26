# Front door for the repo: `make` (or `make help`) lists everything.
#
# The checks run each tool from the same pinned image the stack uses (read
# from docker-compose.yml, so versions never drift), so only Docker is
# needed, and they behave the same on a Mac and in CI.

SHELL := /bin/bash
.DEFAULT_GOAL := help
.PHONY: help up down status logs check test e2e ci incident clean

# Image of a service, read from docker-compose.yml
image = $(shell awk '/image: $(1)/ {print $$2; exit}' docker-compose.yml)
PROMETHEUS   := $(call image,prom\/prometheus:)
ALERTMANAGER := $(call image,prom\/alertmanager:)
ALLOY        := $(call image,grafana\/alloy:)
SHELLCHECK   := koalaman/shellcheck:v0.11.0

# Run a tool in a throwaway container, with the repo mounted at /work
RUN := docker run --rm -v "$(CURDIR)":/work -w /work

help: ## Show this help
	@echo "Usage: make <target>"
	@echo
	@grep -E '^[a-z0-9-]+:.*## ' $(MAKEFILE_LIST) \
	  | awk 'BEGIN {FS = ":.*## "}; {printf "  \033[36m%-9s\033[0m %s\n", $$1, $$2}'

up: ## Start the stack and wait until it's healthy (start the app first)
	@scripts/up.sh

down: ## Stop the stack, keep its data
	@scripts/down.sh

status: ## Containers and their health
	@docker compose ps

logs: ## Follow the stack's logs (Ctrl+C to stop)
	@docker compose logs -f --tail 20

check: ## Validate configs, dashboards and scripts (no running stack needed)
	@echo "== docker-compose.yml"
	@docker compose --env-file .env.example config --quiet
	@echo "== prometheus"
	@$(RUN) -v "$(CURDIR)/prometheus":/etc/prometheus:ro --entrypoint promtool $(PROMETHEUS) \
	  check config /etc/prometheus/prometheus.yml
	@echo "== alertmanager"
	@$(RUN) --entrypoint amtool $(ALERTMANAGER) check-config alertmanager/alertmanager.yml
	@echo "== alloy"
	@$(RUN) $(ALLOY) validate alloy/config.alloy
	@echo "== grafana dashboards"
	@for f in grafana/dashboards/*.json; do python3 -m json.tool "$$f" >/dev/null || exit 1; done
	@echo "== shellcheck"
	@$(RUN) $(SHELLCHECK) scripts/*.sh tests/*.sh
	@echo "All checks passed."

test: ## Unit tests: alert rules, and Alertmanager routing
	@echo "== alert rules (promtool test rules)"
	@$(RUN) --entrypoint promtool $(PROMETHEUS) test rules tests/alert.rules.test.yml
	@echo "== alertmanager routing"
	@$(RUN) --entrypoint amtool $(ALERTMANAGER) config routes test \
	  --config.file=alertmanager/alertmanager.yml --verify.receivers=slack-critical severity=critical
	@$(RUN) --entrypoint amtool $(ALERTMANAGER) config routes test \
	  --config.file=alertmanager/alertmanager.yml --verify.receivers=slack-default severity=warning
	@echo "All tests passed."

e2e: ## End-to-end test of the running stacks (stops selfapp for a while)
	@tests/e2e.sh

ci: check test ## Static checks and unit tests (CI also runs e2e on real stacks)

incident: ## Cause a real incident: make incident MODE=cpu|app|db
	@scripts/simulate-incident.sh $(MODE)

clean: ## Stop the stack AND delete all its data (asks first)
	@read -r -p "Delete all Prometheus, Grafana, Loki and Alertmanager data? [y/N] " answer; \
	  if [ "$$answer" = "y" ]; then docker compose down -v; else echo "Cancelled."; fi
