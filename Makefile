# FluentMetric AI — Makefile
#
# Targets for the Lightning + Tableau Next editions. All targets accept a
# TARGET_ORG variable (defaults to cvk-dev). Example:
#
#   make install-tableau TARGET_ORG=fmt-test
#
# The Tableau Next pipeline is documented in Documents/TABLEAU-EDITION.md.

TARGET_ORG ?= cvk-dev
SHELL := /usr/bin/env bash

.DEFAULT_GOAL := help

.PHONY: help \
        deploy-lightning test-lightning smoke-lightning \
        publish-semantic-model publish-semantic-extensions publish-dashboards \
        deploy-tableau assign-permsets publish-agent share-workspace \
        package-dashboards deploy-dashboards \
        install-tableau verify-tableau check-prereqs \
        release release-lightning release-tableau

help: ## Show this help
	@awk 'BEGIN {FS = ":.*##"; printf "Available targets (TARGET_ORG=$(TARGET_ORG)):\n\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-26s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

# ---------------------------------------------------------------------------
# Lightning edition
# ---------------------------------------------------------------------------

deploy-lightning: ## Deploy force-app/ (Lightning edition) with RunLocalTests
	sf project deploy start \
	    --source-dir force-app \
	    --target-org $(TARGET_ORG) \
	    --test-level RunLocalTests

test-lightning: ## Run Lightning edition Apex tests
	sf apex run test \
	    --target-org $(TARGET_ORG) \
	    --test-level RunLocalTests \
	    --code-coverage \
	    --result-format human

smoke-lightning: ## Anonymous Apex smoke against the Lightning controller surface
	sf apex run \
	    --file scripts/verify-lightning.apex \
	    --target-org $(TARGET_ORG)

# ---------------------------------------------------------------------------
# Tableau Next edition — phases
# ---------------------------------------------------------------------------

check-prereqs: ## Verify Tableau Next provisioning in the target org
	./scripts/check-prereqs.sh $(TARGET_ORG)

publish-semantic-model: ## POST/PUT FluentMetric_AI to /ssot/semantic/models
	./scripts/publish-semantic-model.sh $(TARGET_ORG)

publish-semantic-extensions: ## POST adoption/safety calc fields + metrics via SSOT REST
	./scripts/publish-semantic-extensions.sh $(TARGET_ORG)

publish-dashboards: ## Author the 3 scripted dashboards via tableau-next-author skill
	./scripts/publish-tableau-dashboards.sh $(TARGET_ORG)

deploy-tableau: ## Deploy force-app-tableau/ (Tableau Next edition)
	sf project deploy start \
	    --source-dir force-app-tableau \
	    --target-org $(TARGET_ORG) \
	    --test-level RunSpecifiedTests \
	    --tests FmTableauNextTest

assign-permsets: ## Assign Tableau Next + FluentMetric permsets/PSLs
	-sf org assign permsetlicense --name TableauEinsteinIncludedAppPsl --target-org $(TARGET_ORG) || true
	sf org assign permset --name TableauEinsteinAdmin --target-org $(TARGET_ORG)
	sf org assign permset --name TableauEinsteinAnalyst --target-org $(TARGET_ORG)
	sf org assign permset --name FluentMetric_AI_Tableau_User --target-org $(TARGET_ORG)

publish-agent: ## Publish FluentMetric_Tableau_Analyst agent (idempotent)
	./scripts/publish-agent.sh $(TARGET_ORG)

share-workspace: ## Grant ALL_USERS Viewer on the FluentMetric AI Tableau workspace
	./scripts/share-workspace.sh $(TARGET_ORG)

# ---------------------------------------------------------------------------
# Tableau Next edition — cross-org dashboard portability
# ---------------------------------------------------------------------------
# These two targets pair up: package-dashboards captures a snapshot from a
# source org (typically cvk-dev) into committable JSON files; deploy-dashboards
# replays that snapshot into any target org that already has the workspace +
# semantic model scaffolded by `make install-tableau`.

package-dashboards: ## Snapshot FluentMetric_* dashboards from source org into dashboard-packages/
	./scripts/package-tableau-dashboards.sh $(TARGET_ORG)

deploy-dashboards: ## Deploy committed dashboard-packages/*.json into target org
	./scripts/deploy-tableau-dashboards.sh $(TARGET_ORG)

# ---------------------------------------------------------------------------
# Tableau Next edition — orchestration
# ---------------------------------------------------------------------------

install-tableau: ## End-to-end Tableau Next install (idempotent, one command)
	./scripts/install-tableau-next.sh $(TARGET_ORG)

verify-tableau: ## Smoke-test Tableau Next install
	./scripts/verify-tableau.sh $(TARGET_ORG)

# ---------------------------------------------------------------------------
# Releases — 2GP package versions for both editions
# ---------------------------------------------------------------------------
# `make release VERSION=X.Y.Z` cuts both edition packages from the cvk-dev
# DevHub and prints follow-up steps. Full runbook in
# Documents/Developer/release.md.

DEVHUB ?= cvk-dev

release: ## Cut a 2GP version of both editions (use VERSION=X.Y.Z)
	@if [ -z "$(VERSION)" ]; then \
	  echo "ERROR: VERSION not set. Usage: make release VERSION=X.Y.Z"; \
	  exit 1; \
	fi
	@echo "==> Cutting FluentMetric AI v$(VERSION) on $(DEVHUB)"
	@$(MAKE) release-lightning VERSION=$(VERSION)
	@$(MAKE) release-tableau VERSION=$(VERSION)
	@echo ""
	@echo "==> Both packages cut. Next steps:"
	@echo "    1. Capture the two 04t... IDs printed above."
	@echo "    2. Update CHANGELOG.md: rename [Unreleased] to [$(VERSION)] - $$(date +%Y-%m-%d)"
	@echo "       and add both install URLs (template at the bottom of CHANGELOG.md)."
	@echo "    3. Promote both versions to released:"
	@echo "       sf package version promote --package 'FluentMetric AI@$(VERSION)-1' --target-dev-hub $(DEVHUB)"
	@echo "       sf package version promote --package 'FluentMetric AI for Tableau@$(VERSION)-1' --target-dev-hub $(DEVHUB)"
	@echo "    4. git commit -am 'release: v$(VERSION)' && git tag -a v$(VERSION) -m 'Release $(VERSION)' && git push --tags"
	@echo "    5. Open https://github.com/<owner>/<repo>/releases/new?tag=v$(VERSION) and paste the CHANGELOG entry."

release-lightning: ## Cut Lightning edition 2GP version (internal — use 'make release')
	@if [ -z "$(VERSION)" ]; then echo "ERROR: VERSION not set"; exit 1; fi
	# v1.0.0 ships as beta (no --code-coverage flag). Promotion to a
	# non-beta version requires 75% on every class; AiInsightsService (25%)
	# and AiInsightsDAO (4%) are below threshold. v1.1 will rebuild
	# fixtures and ship as a promoted (non-beta) release. See
	# Documents/Developer/v1.1-test-debt.md.
	sf package version create \
	    --package "FluentMetric AI" \
	    --installation-key-bypass \
	    --wait 30 \
	    --target-dev-hub $(DEVHUB)

release-tableau: ## Cut Tableau Next edition 2GP version (internal — use 'make release')
	@if [ -z "$(VERSION)" ]; then echo "ERROR: VERSION not set"; exit 1; fi
	sf package version create \
	    --package "FluentMetric AI for Tableau" \
	    --installation-key-bypass \
	    --wait 20 \
	    --target-dev-hub $(DEVHUB)
