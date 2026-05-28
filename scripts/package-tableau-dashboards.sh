#!/usr/bin/env bash
# scripts/package-tableau-dashboards.sh
#
# Packages every FluentMetric_* dashboard from the source org into committable
# JSON artifacts under force-app-tableau/dashboard-packages/. Wraps the
# alaviron/tableau-next-package-deploy skill's package_dashboard.py:
#   ~/.claude/skills/tableau-next-package-deploy/scripts/package_dashboard.py
#
# Why this exists: scripts/publish-tableau-dashboards.sh authors dashboards
# in a *source* org (typically cvk-dev) by POSTing viz_specs to the Tableau
# Next REST API. To redeploy the same dashboards into customer orgs without
# re-running the author flow, we need a transferable artifact. The Package &
# Deploy API serializes a dashboard (plus its referenced visualizations,
# metrics, and SDM dependencies) into a single JSON blob that
# scripts/deploy-tableau-dashboards.sh (sibling) can later POST into a
# different org.
#
# Output layout (one file per dashboard):
#   force-app-tableau/dashboard-packages/FluentMetric_Adoption_package.json
#   force-app-tableau/dashboard-packages/FluentMetric_Tokens_And_Safety_package.json
#   force-app-tableau/dashboard-packages/FluentMetric_Feature_Adoption_package.json
#
# Re-running overwrites existing files (intended — the source-of-truth is the
# live source org, not the committed JSON). Commit these files to capture a
# reproducible deploy snapshot before cutting a release.
#
# Usage: ./scripts/package-tableau-dashboards.sh <source-org-alias>
# Env override: PACKAGE_DIR (default: force-app-tableau/dashboard-packages)
# Env override: DASHBOARDS (space-separated list, default: derived from spec dir)

set -euo pipefail

SOURCE_ORG="${1:-${TARGET_ORG:-cvk-dev}}"
PACKAGE_DIR="${PACKAGE_DIR:-force-app-tableau/dashboard-packages}"
SPEC_DIR="${SPEC_DIR:-scripts/tableau-next/dashboard-specs}"

SKILL_DIR="${SKILL_DIR:-$HOME/.claude/skills/tableau-next-package-deploy/scripts}"
PACKAGE_DASHBOARD="$SKILL_DIR/package_dashboard.py"

red()    { printf '\033[31m%s\033[0m\n' "$*"; }
green()  { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
bold()   { printf '\033[1m%s\033[0m\n' "$*"; }

bold "==> Packaging Tableau Next dashboards from '$SOURCE_ORG' into '$PACKAGE_DIR'"

# --- Prereq checks ----------------------------------------------------------
if [[ ! -f "$PACKAGE_DASHBOARD" ]]; then
  red   "ERROR: Skill script not found: $PACKAGE_DASHBOARD"
  yellow "Install via:"
  yellow "  git clone git@git.soma.salesforce.com:alaviron/tableau-skills.git ~/.claude/skills/_tableau-skills"
  yellow "  ln -s ~/.claude/skills/_tableau-skills/tableau-next-package-deploy ~/.claude/skills/tableau-next-package-deploy"
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

mkdir -p "$PACKAGE_DIR"

# --- Determine dashboard list ----------------------------------------------
# Default: derive from the viz_specs filenames in $SPEC_DIR — the convention
# we set up in publish-tableau-dashboards.sh is that the spec basename minus
# the .viz_specs.json suffix matches the dashboard's API name.
if [[ -n "${DASHBOARDS:-}" ]]; then
  IFS=' ' read -r -a DASH_ARRAY <<< "$DASHBOARDS"
elif [[ -d "$SPEC_DIR" ]]; then
  # shopt -p returns non-zero when the option is unset; capture with `|| true`
  # so the command-substitution doesn't kill the script under `set -e`.
  SHOPT_OLD=$(shopt -p nullglob || true)
  shopt -s nullglob
  SPEC_FILES=("$SPEC_DIR"/*.viz_specs.json)
  eval "$SHOPT_OLD"
  DASH_ARRAY=()
  for spec in "${SPEC_FILES[@]}"; do
    base="$(basename "$spec")"
    DASH_ARRAY+=("${base%.viz_specs.json}")
  done
else
  red "ERROR: Set DASHBOARDS env or ensure $SPEC_DIR exists."
  exit 2
fi

if [[ ${#DASH_ARRAY[@]} -eq 0 ]]; then
  yellow "  No dashboards to package — nothing to do."
  exit 0
fi

bold "Packaging ${#DASH_ARRAY[@]} dashboard(s): ${DASH_ARRAY[*]}"

# --- Iterate ---------------------------------------------------------------
FAIL_COUNT=0
for dash in "${DASH_ARRAY[@]}"; do
  echo
  bold "[$dash]"
  out_file="$PACKAGE_DIR/${dash}_package.json"

  set +e
  python3 "$PACKAGE_DASHBOARD" \
    --org "$SOURCE_ORG" \
    --dashboard "$dash" \
    --output "$out_file"
  rc=$?
  set -e

  if [[ $rc -eq 0 && -s "$out_file" ]]; then
    size=$(wc -c < "$out_file" | tr -d ' ')
    green "  ✓ $dash → $out_file (${size} bytes)"
  else
    yellow "  • $dash failed (exit $rc). Common causes: dashboard not yet authored,"
    yellow "    wrong API name, or Package & Deploy API not enabled in this org."
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
done

echo
if [[ $FAIL_COUNT -eq 0 ]]; then
  green "==> All ${#DASH_ARRAY[@]} dashboard(s) packaged. Commit '$PACKAGE_DIR/' to capture the snapshot."
else
  red   "==> $FAIL_COUNT/${#DASH_ARRAY[@]} dashboard(s) failed to package."
  exit 1
fi
