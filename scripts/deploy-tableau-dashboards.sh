#!/usr/bin/env bash
# scripts/deploy-tableau-dashboards.sh
#
# Deploys every package JSON under force-app-tableau/dashboard-packages/ into
# the target org via the Tableau Next Package & Deploy API. Wraps the
# alaviron/tableau-next-package-deploy skill's deploy_package.py:
#   ~/.claude/skills/tableau-next-package-deploy/scripts/deploy_package.py
#
# Pairs with scripts/package-tableau-dashboards.sh — that script captures a
# snapshot from the source org; this one reproduces it on any target. The
# distinction matters because publish-tableau-dashboards.sh only works when
# the operator has author access to the source org's SDM; package+deploy is
# the supported path for delivering pre-built dashboards into customer orgs.
#
# By default we use:
#   --workspace-choice existing --workspace-api-name FluentMetric_AI_Workspace
#   --sdm-choice       existing --sdm-api-name       FluentMetric_AI
# This assumes `make install-tableau` has already deployed the workspace
# metadata + published the semantic model; we're only adding dashboards into
# the existing scaffold. Pass --create-workspace / --create-sdm to override
# (rare; mostly useful for sandbox spin-up demos).
#
# Usage:
#   ./scripts/deploy-tableau-dashboards.sh <target-org-alias> [--dry-run]
#   ./scripts/deploy-tableau-dashboards.sh <target-org> --create-workspace
#
# Exit code is non-zero if ANY package fails to deploy.

set -euo pipefail

DRY_RUN=""
WORKSPACE_CHOICE="existing"
SDM_CHOICE="existing"
ARGS=()

for arg in "$@"; do
  case "$arg" in
    --dry-run)            DRY_RUN="--dry-run" ;;
    --create-workspace)   WORKSPACE_CHOICE="create" ;;
    --create-sdm)         SDM_CHOICE="create" ;;
    *)                    ARGS+=("$arg") ;;
  esac
done
set -- "${ARGS[@]:-}"

TARGET_ORG="${1:-${TARGET_ORG:-cvk-dev}}"
PACKAGE_DIR="${PACKAGE_DIR:-force-app-tableau/dashboard-packages}"
WORKSPACE_NAME="${WORKSPACE_NAME:-FluentMetric_AI_Workspace}"
WORKSPACE_LABEL="${WORKSPACE_LABEL:-FluentMetric AI}"
SDM_NAME="${SDM_NAME:-FluentMetric_AI}"

SKILL_DIR="${SKILL_DIR:-$HOME/.claude/skills/tableau-next-package-deploy/scripts}"
DEPLOY_PACKAGE="$SKILL_DIR/deploy_package.py"

red()    { printf '\033[31m%s\033[0m\n' "$*"; }
green()  { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
bold()   { printf '\033[1m%s\033[0m\n' "$*"; }

bold "==> Deploying Tableau Next dashboard packages from '$PACKAGE_DIR' into '$TARGET_ORG'"
bold "    workspace: $WORKSPACE_CHOICE / $WORKSPACE_NAME"
bold "    sdm:       $SDM_CHOICE / $SDM_NAME"
[[ -n "$DRY_RUN" ]] && yellow "    mode:      DRY RUN (validation only)"

# --- Prereqs ---------------------------------------------------------------
if [[ ! -f "$DEPLOY_PACKAGE" ]]; then
  red   "ERROR: Skill script not found: $DEPLOY_PACKAGE"
  exit 2
fi

if ! command -v python3 >/dev/null 2>&1; then
  red "ERROR: python3 is required."
  exit 2
fi

if ! python3 -c 'import requests' 2>/dev/null; then
  yellow "  python3 'requests' module missing — installing into user site-packages..."
  python3 -m pip install --user --quiet requests || {
    red "ERROR: pip install requests failed."
    exit 2
  }
fi

if [[ ! -d "$PACKAGE_DIR" ]]; then
  red "ERROR: Package directory not found: $PACKAGE_DIR"
  yellow "Run scripts/package-tableau-dashboards.sh against the source org first."
  exit 2
fi

# --- Iterate ---------------------------------------------------------------
# shopt -p returns non-zero when the option is unset; capture with `|| true`
# so the command-substitution doesn't kill the script under `set -e`.
SHOPT_OLD=$(shopt -p nullglob || true)
shopt -s nullglob
PKG_FILES=("$PACKAGE_DIR"/*_package.json)
eval "$SHOPT_OLD"

if [[ ${#PKG_FILES[@]} -eq 0 ]]; then
  yellow "  No *_package.json files found under $PACKAGE_DIR — nothing to deploy."
  exit 0
fi

bold "Found ${#PKG_FILES[@]} package(s)."

FAIL_COUNT=0
for pkg in "${PKG_FILES[@]}"; do
  name="$(basename "$pkg")"
  echo
  bold "[$name]"

  COMMON_ARGS=(
    --org "$TARGET_ORG"
    --package "$pkg"
    --workspace-choice "$WORKSPACE_CHOICE"
    --sdm-choice "$SDM_CHOICE"
    --sdm-api-name "$SDM_NAME"
  )

  if [[ "$WORKSPACE_CHOICE" == "existing" ]]; then
    COMMON_ARGS+=(--workspace-api-name "$WORKSPACE_NAME")
  else
    COMMON_ARGS+=(--workspace-label "$WORKSPACE_LABEL")
  fi

  if [[ -n "$DRY_RUN" ]]; then
    COMMON_ARGS+=("$DRY_RUN")
  fi

  set +e
  python3 "$DEPLOY_PACKAGE" "${COMMON_ARGS[@]}"
  rc=$?
  set -e

  if [[ $rc -eq 0 ]]; then
    green "  ✓ $name deployed."
  else
    red   "  ✗ $name failed (exit $rc)."
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
done

echo
if [[ $FAIL_COUNT -eq 0 ]]; then
  green "==> All ${#PKG_FILES[@]} package(s) deployed."
else
  red   "==> $FAIL_COUNT/${#PKG_FILES[@]} package(s) failed."
  exit 1
fi
