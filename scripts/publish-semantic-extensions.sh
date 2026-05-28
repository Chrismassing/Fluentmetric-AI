#!/usr/bin/env bash
# scripts/publish-semantic-extensions.sh
#
# Idempotently provisions calculated fields (_clc) and semantic metrics (_mtc)
# on the FluentMetric_AI Tableau Next semantic model in the target org. Wraps
# the alaviron/tableau-semantic-authoring skill scripts under
# ~/.claude/skills/tableau-semantic-authoring/scripts/.
#
# IMPORTANT: Expressions reference SDM **apiNames**, not raw DMO field names.
# The apiNames are derived from the DMO labels by Tableau Next at projection
# time and may carry numeric suffixes when fields collide across data objects.
# Documents/SDM-FIELD-MAP.md captures the cvk-dev mapping; re-run the skill's
# discover_sdm.py against any other org before authoring against it.
#
# Calc fields created (cvk-dev):
#   - Distinct_Active_Users_clc      — COUNTD over GenAIGatewayRequest_dlm.User_Id
#   - Distinct_Entitled_Users_clc    — COUNTD of User_dlm.User_Id2 WHERE Is_Entitled = 'true'
#   - Adoption_Rate_clc              — Distinct_Active_Users_clc / Distinct_Entitled_Users_clc
#   - Total_Tokens_clc               — already-aggregated Total_Tokens (Sum)
#   - Avg_Tokens_Per_Request_clc     — Total_Tokens / request count
#   - Toxic_Rate_clc                 — toxicity rate over GenAIContentQuality_dlm
#
# Entitled denominator note: User_dlm.Is_Entitled is a denormalized text flag
# stamped nightly by FluentMetricEntitlementSyncSchedulable from
# PermissionSetAssignment of the FluentMetric_AI_Entitled_User permission set.
# The Apex EntitlementService still resolves entitlement live for the Lightning
# Edition; this projection exists so the Tableau Next semantic layer can
# compute adoption rate without joining PSA (which Data Cloud doesn't project
# as a User-keyed dimension). Field is Text-typed in the DLO, so the calc
# expression compares to the string literal 'true'.
#
# Metrics created:
#   - Active_Users_mtc, Entitled_Users_mtc, Adoption_Rate_mtc,
#     Total_Tokens_mtc, Avg_Tokens_Per_Request_mtc, Toxic_Rate_mtc
#
# This script must run AFTER the SDM exists with all 7 data objects projected
# (GenAI*_dlm + User_dlm). The first call to a duplicate field returns
# "already exists" from the SSOT REST API; we treat that as success.
#
# Usage: ./scripts/publish-semantic-extensions.sh <target-org-alias> [--dry-run]
#
# --dry-run: passes the skill's --dry-run flag to every create_* call.
# Calculated fields and metrics are NOT POSTed; the rendered JSON payload is
# echoed instead. Use this to sanity-check expressions and field references
# (qualified [Table].[Field] for table fields, unqualified [Field_clc] for
# calc fields) before mutating the target org.

set -euo pipefail

DRY_RUN=""
ARGS=()
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN="--dry-run" ;;
    *) ARGS+=("$arg") ;;
  esac
done
set -- "${ARGS[@]:-}"

TARGET_ORG="${1:-${TARGET_ORG:-cvk-dev}}"
SDM_NAME="${SDM_NAME:-FluentMetric_AI}"

SKILL_DIR="${SKILL_DIR:-$HOME/.claude/skills/tableau-semantic-authoring/scripts}"
DISCOVER_SDM="$SKILL_DIR/discover_sdm.py"
CREATE_CALC="$SKILL_DIR/create_calc_field.py"
CREATE_METRIC="$SKILL_DIR/create_metric.py"

red()    { printf '\033[31m%s\033[0m\n' "$*"; }
green()  { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
bold()   { printf '\033[1m%s\033[0m\n' "$*"; }

bold "==> Publishing semantic extensions to '$SDM_NAME' on org '$TARGET_ORG'"

# --- Prereq checks ----------------------------------------------------------
if [[ ! -f "$CREATE_CALC" ]]; then
  red   "ERROR: Skill script not found: $CREATE_CALC"
  yellow "Install via:"
  yellow "  git clone git@git.soma.salesforce.com:alaviron/tableau-skills.git ~/.claude/skills/_tableau-skills"
  yellow "  ln -s ~/.claude/skills/_tableau-skills/tableau-semantic-authoring ~/.claude/skills/tableau-semantic-authoring"
  exit 2
fi

if ! command -v python3 >/dev/null 2>&1; then
  red "ERROR: python3 is required."
  exit 2
fi

# Skill scripts depend on the 'requests' module. Install on first run if missing.
if ! python3 -c 'import requests' 2>/dev/null; then
  yellow "  python3 'requests' module missing — installing into user site-packages..."
  python3 -m pip install --user --quiet requests || {
    red "ERROR: pip install requests failed. Install manually: 'python3 -m pip install requests'"
    exit 2
  }
fi

# --- Resolve org credentials -----------------------------------------------
ORG_INFO=$(sf org display --target-org "$TARGET_ORG" --json)
ACCESS_TOKEN=$(echo "$ORG_INFO" | jq -r '.result.accessToken')
INSTANCE_URL=$(echo "$ORG_INFO" | jq -r '.result.instanceUrl')

if [[ -z "$ACCESS_TOKEN" || "$ACCESS_TOKEN" == "null" ]]; then
  red "ERROR: Could not obtain access token for org '$TARGET_ORG'."
  yellow "Run 'sf org login web --alias $TARGET_ORG' first."
  exit 2
fi

# Skill scripts read SF_TOKEN + SF_INSTANCE from env. Names are confirmed in the
# skill README/SKILL.md — NOT SF_ACCESS_TOKEN/SF_INSTANCE_URL like the publish-
# tableau-* scripts use. Export both pairs so a future skill update that
# switches conventions doesn't break us silently.
export SF_TOKEN="$ACCESS_TOKEN"
export SF_INSTANCE="$INSTANCE_URL"
export SF_ACCESS_TOKEN="$ACCESS_TOKEN"
export SF_INSTANCE_URL="$INSTANCE_URL"

# --- Helper: invoke skill script, tolerate "already exists" -----------------
# Skill scripts exit non-zero on duplicate. We capture stderr and treat any
# message containing 'already exists' or HTTP 409 as success. When DRY_RUN
# is set, the skill prints the rendered JSON payload instead of POSTing —
# we report that as a "preview" and never claim creation.
run_idempotent() {
  local label="$1"; shift
  local cmd=("$@")
  if [[ -n "$DRY_RUN" ]]; then
    cmd+=("$DRY_RUN")
  fi
  local out
  set +e
  out="$("${cmd[@]}" 2>&1)"
  local rc=$?
  set -e
  if [[ -n "$DRY_RUN" ]]; then
    if [[ $rc -eq 0 ]]; then
      green "  ✓ $label — payload validated (dry-run)."
      echo "$out" | sed 's/^/      /'
      return 0
    fi
    red "  ✗ $label — dry-run failed:"
    echo "$out" | sed 's/^/      /'
    return 1
  fi
  if [[ $rc -eq 0 ]]; then
    green "  ✓ $label — created."
    return 0
  fi
  # "already exist" / "exist in base models" / 409 → idempotent skip.
  # Tableau Next phrasing varies between "already exists" (singular) and "already
  # exist in base models" (plural, for calc fields), so anchor on a relaxed match.
  if echo "$out" | grep -qiE 'already exist|duplicate|409|HTTP 409|API names must be unique'; then
    yellow "  • $label — already exists (idempotent skip)."
    return 0
  fi
  # "Missing reference" / "doesn't exist" / "does not exist" → the SDM doesn't
  # yet project a field this calc depends on, OR the metric depends on a calc
  # field that was itself skipped earlier in the run. Common during install
  # before the User DMO has been re-mapped to include FluentMetric_IsEntitled__c.
  # We log a clear hint and continue so the rest of the calcs/metrics still
  # publish.
  # NOTE: the SSOT REST error envelope HTML-encodes apostrophes as &#39; — we
  # match on the encoded form too because grep doesn't decode entities.
  if echo "$out" | grep -qiE "Missing reference|Formula referenced a field that does not exist|doesn'?t exist|doesn&#39;t exist|does not exist"; then
    yellow "  • $label — skipped (referenced field/calc not yet projected in the SDM)."
    yellow "    Add the field to the upstream Data Stream + DMO mapping and re-run this script."
    yellow "    See Documents/Admin/05-configure.md §Tableau Next: nightly entitlement sync."
    return 0
  fi
  red "  ✗ $label — failed:"
  echo "$out" | sed 's/^/      /'
  return 1
}

# --- 0. Discovery preflight -------------------------------------------------
# Per tableau-semantic-authoring skill: "Always verify field names exist in
# the SDM before referencing them in expressions." We hit /ssot/semantic/models
# directly (skill's discover_sdm.py uses the same endpoint) and assert that
# the 7 required tables are projected. If the SDM is missing any of them, fail
# fast with an actionable hint.
if [[ -f "$DISCOVER_SDM" ]]; then
  echo
  bold "[0/2] SDM preflight — '$SDM_NAME'"
  set +e
  SDM_JSON=$(python3 "$DISCOVER_SDM" --sdm "$SDM_NAME" --json 2>&1)
  rc=$?
  set -e
  if [[ $rc -ne 0 ]]; then
    red "  ✗ Could not discover SDM '$SDM_NAME'. Output:"
    echo "$SDM_JSON" | sed 's/^/      /'
    yellow "  Author the SDM in $TARGET_ORG first (see Documents/SDM-FIELD-MAP.md)."
    exit 1
  fi

  REQUIRED_OBJECTS=(
    "GenAIGatewayRequest_dlm"
    "GenAIFeedback_dlm"
    "GenAIContentQuality_dlm"
    "User_dlm"
  )
  # discover_sdm.py emits {"objects": [{"objectName": "..."}, ...]}.
  MISSING=()
  for obj in "${REQUIRED_OBJECTS[@]}"; do
    if ! echo "$SDM_JSON" | grep -q "\"objectName\":\\s*\"$obj\""; then
      MISSING+=("$obj")
    fi
  done

  if [[ ${#MISSING[@]} -gt 0 ]]; then
    red "  ✗ SDM '$SDM_NAME' is missing required data objects: ${MISSING[*]}"
    yellow "  Add them via Data Manager → FluentMetric_AI before re-running."
    yellow "  See Documents/SDM-FIELD-MAP.md for the expected projection."
    exit 1
  fi
  green "  ✓ SDM has all 4 required data objects."
else
  yellow "  Skill discover_sdm.py not found — skipping preflight (install alaviron/tableau-skills)."
fi

# --- 1. Calculated measurements --------------------------------------------
# All expressions reference SDM apiNames (see Documents/SDM-FIELD-MAP.md).
# Table-qualified for raw fields, unqualified for calc-field references.
echo
bold "[1/2] Calculated measurements"

run_idempotent "Distinct_Active_Users_clc" \
  python3 "$CREATE_CALC" \
    --sdm "$SDM_NAME" \
    --type measurement \
    --name Distinct_Active_Users_clc \
    --label "Distinct Active Users" \
    --expression "COUNTD([GenAIGatewayRequest_dlm].[User_Id])" \
    --aggregation UserAgg

# Entitled denominator: distinct users flagged Is_Entitled='true' on User_dlm.
# Stamped nightly from PermissionSetAssignment of FluentMetric_AI_Entitled_User
# (see FluentMetricEntitlementSyncSchedulable). The Text comparison is a
# Tableau Next semantic-layer constraint — Boolean-typed checkboxes still
# project into the DLO as text strings.
run_idempotent "Distinct_Entitled_Users_clc" \
  python3 "$CREATE_CALC" \
    --sdm "$SDM_NAME" \
    --type measurement \
    --name Distinct_Entitled_Users_clc \
    --label "Distinct Entitled Users" \
    --expression "COUNTD(IF [User_dlm].[Is_Entitled] = 'true' THEN [User_dlm].[User_Id2] END)" \
    --aggregation UserAgg

# Adoption rate: of users who *could* use AI, how many did. Numerator is the
# count of distinct active users in the window; denominator is the count of
# users assigned to the entitlement permset. Tableau Next renders this as a
# rate when bound to a metric — WoW deltas come from the metric layer, not
# from a separate calc field.
run_idempotent "Adoption_Rate_clc" \
  python3 "$CREATE_CALC" \
    --sdm "$SDM_NAME" \
    --type measurement \
    --name Adoption_Rate_clc \
    --label "Adoption Rate" \
    --expression "[Distinct_Active_Users_clc] / [Distinct_Entitled_Users_clc]" \
    --aggregation UserAgg

# Total_Tokens is already aggregated upstream in the DMO (sum-of-tokens per
# request). The calc-field wrapper exposes it under a stable apiName so the
# metric layer can bind to it (Total_Tokens_mtc).
run_idempotent "Total_Tokens_clc" \
  python3 "$CREATE_CALC" \
    --sdm "$SDM_NAME" \
    --type measurement \
    --name Total_Tokens_clc \
    --label "Total Tokens" \
    --expression "SUM([GenAIGatewayRequest_dlm].[Total_Tokens])" \
    --aggregation UserAgg

# Ratio expression (SUM/COUNT) → UserAgg per skill rule.
run_idempotent "Avg_Tokens_Per_Request_clc" \
  python3 "$CREATE_CALC" \
    --sdm "$SDM_NAME" \
    --type measurement \
    --name Avg_Tokens_Per_Request_clc \
    --label "Avg Tokens Per Request" \
    --expression "SUM([GenAIGatewayRequest_dlm].[Total_Tokens]) / COUNT([GenAIGatewayRequest_dlm].[User_Id])" \
    --aggregation UserAgg

# Toxicity sourced from GenAIContentQuality_dlm.Is_Toxicity_Detected — the only
# toxicity flag projected. GenAIFeedback_dlm has NO isToxic field.
# Field is `Text` not Boolean (string values "true"/"false"/null in cvk-dev), so
# compare to a string literal — Tableau Next semantic-layer expressions reject
# `IF [TextField]` with "Expected: [<column>], Found: StringLiteral".
run_idempotent "Toxic_Rate_clc" \
  python3 "$CREATE_CALC" \
    --sdm "$SDM_NAME" \
    --type measurement \
    --name Toxic_Rate_clc \
    --label "Toxic Rate" \
    --expression "SUM(IF [GenAIContentQuality_dlm].[Is_Toxicity_Detected] = 'true' THEN 1 ELSE 0 END) / COUNT([GenAIContentQuality_dlm].[Is_Toxicity_Detected])" \
    --aggregation UserAgg

# --- 2. Semantic metrics ---------------------------------------------------
# Time field is the SDM apiName Timestamp1 (suffixed because Timestamp collides
# across multiple GenAI DMOs). Time table is GenAIGatewayRequest_dlm.
echo
bold "[2/2] Semantic metrics"

run_idempotent "Active_Users_mtc" \
  python3 "$CREATE_METRIC" \
    --sdm "$SDM_NAME" \
    --name Active_Users_mtc \
    --label "Active Users" \
    --calculated-field Distinct_Active_Users_clc \
    --time-field Timestamp1 \
    --time-table GenAIGatewayRequest_dlm

run_idempotent "Entitled_Users_mtc" \
  python3 "$CREATE_METRIC" \
    --sdm "$SDM_NAME" \
    --name Entitled_Users_mtc \
    --label "Entitled Users" \
    --calculated-field Distinct_Entitled_Users_clc \
    --time-field Timestamp1 \
    --time-table GenAIGatewayRequest_dlm

run_idempotent "Adoption_Rate_mtc" \
  python3 "$CREATE_METRIC" \
    --sdm "$SDM_NAME" \
    --name Adoption_Rate_mtc \
    --label "Adoption Rate" \
    --calculated-field Adoption_Rate_clc \
    --time-field Timestamp1 \
    --time-table GenAIGatewayRequest_dlm

run_idempotent "Total_Tokens_mtc" \
  python3 "$CREATE_METRIC" \
    --sdm "$SDM_NAME" \
    --name Total_Tokens_mtc \
    --label "Total Tokens" \
    --calculated-field Total_Tokens_clc \
    --time-field Timestamp1 \
    --time-table GenAIGatewayRequest_dlm

run_idempotent "Avg_Tokens_Per_Request_mtc" \
  python3 "$CREATE_METRIC" \
    --sdm "$SDM_NAME" \
    --name Avg_Tokens_Per_Request_mtc \
    --label "Avg Tokens Per Request" \
    --calculated-field Avg_Tokens_Per_Request_clc \
    --time-field Timestamp1 \
    --time-table GenAIGatewayRequest_dlm

run_idempotent "Toxic_Rate_mtc" \
  python3 "$CREATE_METRIC" \
    --sdm "$SDM_NAME" \
    --name Toxic_Rate_mtc \
    --label "Toxic Rate" \
    --calculated-field Toxic_Rate_clc \
    --time-field Timestamp6 \
    --time-table GenAIContentQuality_dlm

echo
green "==> Semantic extensions published to '$SDM_NAME'."
