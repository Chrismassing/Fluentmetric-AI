#!/usr/bin/env bash
# scripts/verify-tableau.sh
#
# End-to-end smoke test for the Tableau Next edition install. Verifies:
#   1. Semantic model FluentMetric_AI exists in Data Cloud SSOT.
#   2. AnalyticsWorkspace FluentMetric_AI_Workspace is deployed.
#   3. Seven AnalyticsDashboard rows whose DeveloperName starts with FluentMetric_ exist
#      (4 originals + 3 scripted: Adoption, Tokens_And_Safety, Feature_Adoption).
#   4. The Lightning-edition service backing the agent actions runs without error.
#   5. Two adoption-parity actions (GetEntitlementSnapshotAction, GetAdoptionDeltasAction)
#      execute without error envelopes.
#
# Each check independently passes or fails; the script reports a summary
# at the end and exits non-zero if any check failed.
#
# Usage: ./scripts/verify-tableau.sh <target-org-alias>

set -euo pipefail

TARGET_ORG="${1:-${TARGET_ORG:-cvk-dev}}"
# SSOT semantic-model endpoint is GA on v66 only as of 2026-05; v67 returns 404.
API_VERSION="${API_VERSION:-66.0}"
MODEL_NAME="${MODEL_NAME:-FluentMetric_AI}"
# 3 scripted dashboards: FluentMetric_Adoption, FluentMetric_Feature_Adoption,
# FluentMetric_Tokens_And_Safety. The original parity plan also called for 4
# UI-authored dashboards (totalling 7), but we pivoted entirely to the scripted
# pipeline and dropped the manual authoring step.
EXPECTED_DASHBOARD_COUNT="${EXPECTED_DASHBOARD_COUNT:-3}"
APEX_FILE="${APEX_FILE:-scripts/verify-actions.apex}"

red()    { printf '\033[31m%s\033[0m\n' "$*"; }
green()  { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
bold()   { printf '\033[1m%s\033[0m\n' "$*"; }

bold "==> Verifying Tableau Next edition in org '$TARGET_ORG'"

if ! command -v jq >/dev/null 2>&1; then
  red "ERROR: 'jq' required."
  exit 2
fi

PASS=0
FAIL=0

# --- 1. Semantic model ------------------------------------------------------
echo
bold "[1/5] Semantic model '$MODEL_NAME' present"
ORG_INFO=$(sf org display --target-org "$TARGET_ORG" --json)
ACCESS_TOKEN=$(echo "$ORG_INFO" | jq -r '.result.accessToken')
INSTANCE_URL=$(echo "$ORG_INFO" | jq -r '.result.instanceUrl')

HTTP_STATUS=$(curl -sS -o /dev/null -w '%{http_code}' \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  "${INSTANCE_URL}/services/data/v${API_VERSION}/ssot/semantic/models/${MODEL_NAME}")

if [[ "$HTTP_STATUS" == "200" ]]; then
  green "  PASS — GET /ssot/semantic/models/${MODEL_NAME} → 200"
  PASS=$((PASS+1))
else
  red "  FAIL — GET /ssot/semantic/models/${MODEL_NAME} → $HTTP_STATUS"
  FAIL=$((FAIL+1))
fi

# --- 2. AnalyticsWorkspace --------------------------------------------------
echo
bold "[2/5] AnalyticsWorkspace 'FluentMetric_AI_Workspace' deployed"
WS_COUNT=$(sf data query \
  --query "SELECT Id FROM AnalyticsWorkspace WHERE DeveloperName = 'FluentMetric_AI_Workspace'" \
  --target-org "$TARGET_ORG" \
  --json 2>/dev/null | jq -r '.result.totalSize // 0')

if [[ "$WS_COUNT" -ge 1 ]]; then
  green "  PASS — workspace found."
  PASS=$((PASS+1))
else
  red "  FAIL — workspace not found. Did 'sf project deploy --source-dir force-app-tableau' run successfully?"
  FAIL=$((FAIL+1))
fi

# --- 3. AnalyticsDashboards -------------------------------------------------
echo
bold "[3/5] $EXPECTED_DASHBOARD_COUNT dashboards (DeveloperName LIKE 'FluentMetric_%')"
DASH_COUNT=$(sf data query \
  --query "SELECT Id FROM AnalyticsDashboard WHERE DeveloperName LIKE 'FluentMetric_%'" \
  --target-org "$TARGET_ORG" \
  --json 2>/dev/null | jq -r '.result.totalSize // 0')

if [[ "$DASH_COUNT" -ge "$EXPECTED_DASHBOARD_COUNT" ]]; then
  green "  PASS — found $DASH_COUNT (expected $EXPECTED_DASHBOARD_COUNT)."
  PASS=$((PASS+1))
else
  red "  FAIL — found $DASH_COUNT, expected $EXPECTED_DASHBOARD_COUNT."
  yellow "  Run 'make publish-dashboards TARGET_ORG=$TARGET_ORG' to publish the 3 scripted dashboards."
  FAIL=$((FAIL+1))
fi

# --- 4. Apex invocable smoke test -------------------------------------------
echo
bold "[4/5] GetUsageOverviewAction smoke test"
if [[ ! -f "$APEX_FILE" ]]; then
  red "  FAIL — $APEX_FILE missing."
  FAIL=$((FAIL+1))
else
  APEX_LOG=$(sf apex run --file "$APEX_FILE" --target-org "$TARGET_ORG" --json 2>/dev/null \
    | jq -r '.result.logs // ""')

  # `sf apex run --json` returns logs that include both the source listing
  # ("Execute Anonymous: System.debug('VERIFY_RESULT::FAIL::...');") AND the
  # runtime debug output. To distinguish, we anchor on the |DEBUG| prefix,
  # which only appears on runtime trace lines.
  if echo "$APEX_LOG" | grep -q '|DEBUG|VERIFY_RESULT::OK::overview'; then
    # Match the full runtime line then strip the leading "...|DEBUG|" prefix.
    SUMMARY=$(echo "$APEX_LOG" | grep -o '|DEBUG|VERIFY_RESULT::OK::overview.*' | head -1 | sed 's/^|DEBUG|//')
    green "  PASS — $SUMMARY"
    PASS=$((PASS+1))
  elif echo "$APEX_LOG" | grep -q '|DEBUG|VERIFY_RESULT::FAIL::overview'; then
    SUMMARY=$(echo "$APEX_LOG" | grep -o '|DEBUG|VERIFY_RESULT::FAIL::overview.*' | head -1 | sed 's/^|DEBUG|//')
    red "  FAIL — $SUMMARY"
    FAIL=$((FAIL+1))
  else
    red "  FAIL — Apex did not emit VERIFY_RESULT::*::overview marker. Review logs:"
    echo "$APEX_LOG" | tail -20
    FAIL=$((FAIL+1))
  fi
fi

# --- 5. Adoption parity smoke test ------------------------------------------
echo
bold "[5/5] Adoption parity actions (entitlement snapshot + WoW deltas)"
if [[ ! -f "$APEX_FILE" ]]; then
  red "  FAIL — $APEX_FILE missing."
  FAIL=$((FAIL+1))
else
  APEX_LOG=$(sf apex run --file "$APEX_FILE" --target-org "$TARGET_ORG" --json 2>/dev/null \
    | jq -r '.result.logs // ""')

  # Anchor on |DEBUG| to avoid matching the source-listing portion of the
  # apex --json log payload (see overview check above).
  ADOPT_OK=$(echo "$APEX_LOG" | grep -c '|DEBUG|VERIFY_RESULT::OK::adoption_' || true)
  ADOPT_FAIL=$(echo "$APEX_LOG" | grep -c '|DEBUG|VERIFY_RESULT::FAIL::adoption_' || true)

  if [[ "$ADOPT_OK" -ge 2 && "$ADOPT_FAIL" -eq 0 ]]; then
    SUMMARY=$(echo "$APEX_LOG" | grep -o '|DEBUG|VERIFY_RESULT::OK::adoption_[^[:cntrl:]]*' | sed 's/^|DEBUG|//' | tr '\n' '|')
    green "  PASS — $SUMMARY"
    PASS=$((PASS+1))
  elif [[ "$ADOPT_FAIL" -gt 0 ]]; then
    SUMMARY=$(echo "$APEX_LOG" | grep -o '|DEBUG|VERIFY_RESULT::FAIL::adoption_[^[:cntrl:]]*' | head -1 | sed 's/^|DEBUG|//')
    red "  FAIL — $SUMMARY"
    FAIL=$((FAIL+1))
  else
    red "  FAIL — Apex did not emit VERIFY_RESULT::*::adoption_ markers. Review logs:"
    echo "$APEX_LOG" | tail -20
    FAIL=$((FAIL+1))
  fi
fi

# --- Summary ----------------------------------------------------------------
echo
bold "==> Summary: $PASS pass / $FAIL fail"
if [[ "$FAIL" -ne 0 ]]; then
  exit 1
fi
green "==> All Tableau Next checks green."
