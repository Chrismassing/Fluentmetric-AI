#!/usr/bin/env bash
# scripts/publish-agent.sh
#
# Publishes the FluentMetric_Tableau_Analyst Agentforce agent to the target
# org. Designed to be safely re-runnable: 'sf agent publish' is treated as
# idempotent — if the agent is already published, the script reports success
# rather than failing.
#
# Activation (flipping the agent to "Active" in Agent Builder) is NOT
# scripted because Salesforce does not expose a public CLI/API for it.
# The script prints the activation URL at the end.
#
# Usage: ./scripts/publish-agent.sh <target-org-alias>

set -euo pipefail

TARGET_ORG="${1:-${TARGET_ORG:-cvk-dev}}"
AGENT_API_NAME="${AGENT_API_NAME:-FluentMetric_Tableau_Analyst}"
SOURCE_DIR="${SOURCE_DIR:-force-app-tableau}"

red()    { printf '\033[31m%s\033[0m\n' "$*"; }
green()  { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
bold()   { printf '\033[1m%s\033[0m\n' "$*"; }

bold "==> Publishing agent '$AGENT_API_NAME' to org '$TARGET_ORG'"

if ! command -v sf >/dev/null 2>&1; then
  red "ERROR: 'sf' CLI required."
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  red "ERROR: 'jq' required."
  exit 2
fi

# --- Confirm bundle exists in source ----------------------------------------
BUNDLE_DIR="${SOURCE_DIR}/main/default/aiAuthoringBundles/${AGENT_API_NAME}"
if [[ ! -d "$BUNDLE_DIR" ]]; then
  red "ERROR: agent bundle not found at $BUNDLE_DIR"
  exit 2
fi

# --- Run sf agent publish ---------------------------------------------------
# Captures both stdout and exit status. We grep for the 'already published'
# signal so re-runs succeed rather than fail.
echo
bold "[1/1] sf agent publish --api-name $AGENT_API_NAME"

PUBLISH_LOG="$(mktemp)"
trap 'rm -f "$PUBLISH_LOG"' EXIT

set +e
sf agent publish \
  --api-name "$AGENT_API_NAME" \
  --target-org "$TARGET_ORG" \
  > "$PUBLISH_LOG" 2>&1
PUBLISH_EXIT=$?
set -e

cat "$PUBLISH_LOG"

if [[ $PUBLISH_EXIT -eq 0 ]]; then
  green "  Agent published."
elif grep -qiE 'already published|no changes to publish|nothing to publish' "$PUBLISH_LOG"; then
  yellow "  Agent already published — treating as success (idempotent re-run)."
else
  red "  sf agent publish failed (exit $PUBLISH_EXIT). See log above."
  exit 1
fi

# --- Print activation URL ---------------------------------------------------
INSTANCE_URL=$(sf org display --target-org "$TARGET_ORG" --json | jq -r '.result.instanceUrl')

echo
bold "==> Agent publish complete. ONE manual step remains:"
echo
yellow "    1. Open Agent Builder:"
yellow "       ${INSTANCE_URL}/lightning/setup/EinsteinCopilot/home"
yellow "    2. Find '$AGENT_API_NAME' and click 'Activate'."
echo
yellow "    (Salesforce does not currently expose an API for agent activation."
yellow "     This is a one-time, one-click step per org.)"
