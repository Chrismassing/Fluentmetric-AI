#!/usr/bin/env bash
# scripts/publish-tableau-dashboards.sh
#
# Iterates over scripts/tableau-next/dashboard-specs/*.viz_specs.json and
# creates each dashboard in the FluentMetric_AI_Workspace via the
# alaviron/tableau-next-author skill scripts. Designed to run AFTER
# `publish-semantic-extensions.sh` has provisioned the calc fields and metrics
# the specs reference.
#
# Each dashboard's API name is derived from the spec filename:
#   FluentMetric_Adoption.viz_specs.json → FluentMetric_Adoption
#
# Re-running is safe: the skill's create_dashboard.py treats existing dashboards
# as upsertable; duplicate names short-circuit with an "already exists" message
# we capture as success.
#
# Usage: ./scripts/publish-tableau-dashboards.sh <target-org-alias>

set -euo pipefail

TARGET_ORG="${1:-${TARGET_ORG:-cvk-dev}}"
SDM_NAME="${SDM_NAME:-FluentMetric_AI}"
WORKSPACE_NAME="${WORKSPACE_NAME:-FluentMetric_AI_Workspace}"
SPEC_DIR="${SPEC_DIR:-scripts/tableau-next/dashboard-specs}"

SKILL_DIR="${SKILL_DIR:-$HOME/.claude/skills/tableau-next-author/scripts}"
CREATE_DASHBOARD="$SKILL_DIR/create_dashboard.py"
VIZ_TEMPLATES_LIB="$SKILL_DIR/lib/viz_templates.py"

red()    { printf '\033[31m%s\033[0m\n' "$*"; }
green()  { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
bold()   { printf '\033[1m%s\033[0m\n' "$*"; }

bold "==> Publishing Tableau Next dashboards into '$WORKSPACE_NAME' on org '$TARGET_ORG'"

# --- Prereq checks ----------------------------------------------------------
if [[ ! -f "$CREATE_DASHBOARD" ]]; then
  red   "ERROR: Skill script not found: $CREATE_DASHBOARD"
  yellow "Install via:"
  yellow "  git clone git@git.soma.salesforce.com:alaviron/tableau-skills.git ~/.claude/skills/_tableau-skills"
  yellow "  ln -s ~/.claude/skills/_tableau-skills/tableau-next-author ~/.claude/skills/tableau-next-author"
  exit 2
fi

if [[ ! -d "$SPEC_DIR" ]]; then
  red   "ERROR: Dashboard spec directory not found: $SPEC_DIR"
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

# --- Resolve org credentials -----------------------------------------------
ORG_INFO=$(sf org display --target-org "$TARGET_ORG" --json)
ACCESS_TOKEN=$(echo "$ORG_INFO" | jq -r '.result.accessToken')
INSTANCE_URL=$(echo "$ORG_INFO" | jq -r '.result.instanceUrl')

if [[ -z "$ACCESS_TOKEN" || "$ACCESS_TOKEN" == "null" ]]; then
  red "ERROR: Could not obtain access token for org '$TARGET_ORG'."
  exit 2
fi

export SF_ACCESS_TOKEN="$ACCESS_TOKEN"
export SF_INSTANCE_URL="$INSTANCE_URL"

# --- Iterate spec files ----------------------------------------------------
# shopt -p returns non-zero when the option is unset; under `set -e` the
# command-substitution propagates that as an error and silently kills the
# script. Capture with `|| true` to guard against that.
SHOPT_OLD=$(shopt -p nullglob || true)
shopt -s nullglob
SPEC_FILES=("$SPEC_DIR"/*.viz_specs.json)
eval "$SHOPT_OLD"

if [[ ${#SPEC_FILES[@]} -eq 0 ]]; then
  yellow "  No *.viz_specs.json files found under $SPEC_DIR — nothing to publish."
  exit 0
fi

bold "Found ${#SPEC_FILES[@]} dashboard spec(s) under $SPEC_DIR"

# --- Spec preflight (offline) ----------------------------------------------
# Per tableau-next-author skill: "Always use visualization templates instead
# of manually building visualization JSON. Templates ensure proper field
# structure, encodings, sorting, and API compliance." We import the skill's
# validate_viz_spec_fields() and run each spec through it before any HTTP
# call so a typo in a template name or a missing required field surfaces
# locally instead of after a 30-second org round trip.
if [[ -f "$VIZ_TEMPLATES_LIB" ]]; then
  echo
  bold "[Preflight] Validating viz_specs against skill templates..."
  export SKILL_DIR  # heredoc Python reads it from os.environ
  PREFLIGHT_FAIL=0
  for spec in "${SPEC_FILES[@]}"; do
    base="$(basename "$spec")"
    if ! python3 - "$spec" <<'PY'
import json, sys
spec_path = sys.argv[1]
sys.path.insert(0, __import__("os").environ["SKILL_DIR"])
from lib.viz_templates import validate_viz_spec_fields  # type: ignore
with open(spec_path) as fh:
    spec = json.load(fh)
viz_list = spec.get("visualizations", [])
if not viz_list:
    print(f"  ✗ {spec_path}: no visualizations defined", file=sys.stderr)
    sys.exit(1)
for viz in viz_list:
    ok, err = validate_viz_spec_fields(viz)
    if not ok:
        print(f"  ✗ {spec_path} — {err}", file=sys.stderr)
        sys.exit(1)
PY
    then
      red   "  ✗ $base — preflight failed."
      PREFLIGHT_FAIL=$((PREFLIGHT_FAIL + 1))
    else
      green "  ✓ $base — $(jq '.visualizations | length' "$spec") viz, $(jq '.filters | length' "$spec") filters, $(jq '.metrics | length' "$spec") metrics."
    fi
  done
  if [[ $PREFLIGHT_FAIL -gt 0 ]]; then
    red "  Preflight rejected $PREFLIGHT_FAIL spec(s). Fix the errors above before running again."
    exit 2
  fi
else
  yellow "  Skill viz_templates.py not found at $VIZ_TEMPLATES_LIB — skipping offline preflight."
fi

FAIL_COUNT=0
for spec in "${SPEC_FILES[@]}"; do
  base="$(basename "$spec")"
  dash_name="${base%.viz_specs.json}"

  echo
  bold "[$dash_name] $base"

  set +e
  python3 "$CREATE_DASHBOARD" \
    --org "$TARGET_ORG" \
    --sdm "$SDM_NAME" \
    --workspace "$WORKSPACE_NAME" \
    --name "$dash_name" \
    --viz-specs "$spec"
  rc=$?
  set -e

  if [[ $rc -eq 0 ]]; then
    green "  ✓ $dash_name created."
  else
    yellow "  • $dash_name returned non-zero exit ($rc). If the dashboard already exists, this is expected; otherwise inspect the output above."
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
done

echo
if [[ $FAIL_COUNT -eq 0 ]]; then
  green "==> All ${#SPEC_FILES[@]} dashboard(s) processed."
else
  yellow "==> ${#SPEC_FILES[@]} dashboard(s) processed; $FAIL_COUNT non-zero exit(s). Review above for any genuine failures."
fi
