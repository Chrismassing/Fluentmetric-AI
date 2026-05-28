#!/usr/bin/env bash
# scripts/install-tableau-next.sh
#
# One-command install for the FluentMetric AI for Tableau Next edition.
# Orchestrates the ten steps documented in Documents/TABLEAU-EDITION.md
# and is safe to re-run end-to-end (each step is idempotent).
#
# Usage: ./scripts/install-tableau-next.sh <target-org-alias>

set -euo pipefail

TARGET_ORG="${1:-${TARGET_ORG:-cvk-dev}}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

red()    { printf '\033[31m%s\033[0m\n' "$*"; }
green()  { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
bold()   { printf '\033[1m%s\033[0m\n' "$*"; }

cd "$REPO_ROOT"

bold "=========================================================="
bold "  FluentMetric AI for Tableau Next — Installer"
bold "  Target org: $TARGET_ORG"
bold "=========================================================="

# --- 1. Prerequisites -------------------------------------------------------
echo
bold "[Step 1/10] Verify Tableau Next prerequisites"
"$SCRIPT_DIR/check-prereqs.sh" "$TARGET_ORG"

# --- 2. Lightning edition deploy --------------------------------------------
echo
bold "[Step 2/10] Deploy Lightning edition (force-app/)"
sf project deploy start \
  --source-dir force-app \
  --target-org "$TARGET_ORG" \
  --test-level RunLocalTests \
  --ignore-conflicts

# --- 3. Semantic model publish ----------------------------------------------
echo
bold "[Step 3/10] Publish FluentMetric_AI semantic model via SSOT REST"
"$SCRIPT_DIR/publish-semantic-model.sh" "$TARGET_ORG"

# --- 4. Semantic model extensions (adoption + safety) -----------------------
echo
bold "[Step 4/10] Publish adoption/safety calc fields + metrics"
"$SCRIPT_DIR/publish-semantic-extensions.sh" "$TARGET_ORG"

# --- 5. Tableau edition deploy ----------------------------------------------
echo
bold "[Step 5/10] Deploy Tableau Next edition (force-app-tableau/)"
sf project deploy start \
  --source-dir force-app-tableau \
  --target-org "$TARGET_ORG" \
  --test-level RunSpecifiedTests \
  --tests FmTableauNextTest \
  --ignore-conflicts

# --- 6. Scripted dashboards -------------------------------------------------
echo
bold "[Step 6/10] Author scripted dashboards in FluentMetric_AI_Workspace"
"$SCRIPT_DIR/publish-tableau-dashboards.sh" "$TARGET_ORG"

# --- 7. Permission set assignments ------------------------------------------
echo
bold "[Step 7/10] Assign Tableau Next + FluentMetric permsets"

assign_psl() {
  local psl="$1"
  if sf org assign permsetlicense --name "$psl" --target-org "$TARGET_ORG" 2>&1 \
       | tee /dev/stderr | grep -qiE 'success|already'; then
    green "  PSL $psl assigned (or already assigned)."
  else
    yellow "  PSL $psl assignment skipped — may not be available in this org."
  fi
}

assign_permset() {
  local ps="$1"
  if sf org assign permset --name "$ps" --target-org "$TARGET_ORG" 2>&1 \
       | tee /dev/stderr | grep -qiE 'success|already'; then
    green "  Permset $ps assigned (or already assigned)."
  else
    red "  Permset $ps assignment failed."
    return 1
  fi
}

# Tableau Next access
assign_psl "TableauEinsteinIncludedAppPsl" || true
assign_permset "TableauEinsteinAdmin"
assign_permset "TableauEinsteinAnalyst"

# FluentMetric Tableau edition access
assign_permset "FluentMetric_AI_Tableau_User"

# --- 8. Workspace ACL share -------------------------------------------------
echo
bold "[Step 8/10] Share FluentMetric_AI_Workspace with ALL_USERS (Viewer)"
# The FluentMetric_AI_Tableau_User permset enables tab/app visibility, but the
# Tableau Next workspace itself enforces a separate ACL via record access
# shares. Without this step, recipients can hold the permset and still hit
# "Access denied" on the launcher tile. Idempotent — skipped silently if the
# share already exists at Viewer.
"$SCRIPT_DIR/share-workspace.sh" "$TARGET_ORG" Viewer

# --- 9. Agent publish -------------------------------------------------------
echo
bold "[Step 9/10] Publish FluentMetric_Tableau_Analyst agent"
"$SCRIPT_DIR/publish-agent.sh" "$TARGET_ORG"

# --- 10. Verification -------------------------------------------------------
echo
bold "[Step 10/10] Verify install"
"$SCRIPT_DIR/verify-tableau.sh" "$TARGET_ORG"

echo
green "=========================================================="
green "  Install complete."
green "  Remember: activate the agent in Agent Builder (manual)."
green "=========================================================="
