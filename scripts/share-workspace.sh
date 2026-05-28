#!/usr/bin/env bash
# scripts/share-workspace.sh
#
# Grants Viewer access on the FluentMetric_AI_Workspace to ALL_USERS in the
# target org via the Tableau Next Record Access Shares REST API. Wraps the
# patterns documented in the alaviron/tableau-next-record-access-shares
# skill (~/.claude/skills/tableau-next-record-access-shares/SKILL.md):
#
#   1. GET  /tableau/workspaces      → resolve workspace ID by DeveloperName
#   2. POST /tableau/records/{id}/shares with accessRequestItems
#
# Why this exists in addition to the FluentMetric_AI_Tableau_User permset:
# the permset enables tab/app visibility, but the Tableau Next workspace
# itself enforces a separate ACL via record access shares. Without an
# explicit share, recipients can hold the permset and still see "Access
# denied" when they click the launcher tile. Sharing with ALL_USERS at
# Viewer level is the simplest production-safe default.
#
# Usage:  ./scripts/share-workspace.sh <target-org-alias> [accessType]
#   accessType: Viewer (default), Editor, Owner
# Env override: WORKSPACE_NAME (default: FluentMetric_AI_Workspace)
#
# Idempotent: re-running with the same accessType returns 'duplicate' from
# the API; we treat that as success. To upgrade access, pass a higher tier
# (this script will PATCH instead of POST when an existing share is found).

set -euo pipefail

TARGET_ORG="${1:-${TARGET_ORG:-cvk-dev}}"
ACCESS_TYPE="${2:-Viewer}"
API_VERSION="${API_VERSION:-64.0}"
WORKSPACE_NAME="${WORKSPACE_NAME:-FluentMetric_AI_Workspace}"
USER_OR_GROUP_ID="${USER_OR_GROUP_ID:-ALL_USERS}"

red()    { printf '\033[31m%s\033[0m\n' "$*"; }
green()  { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
bold()   { printf '\033[1m%s\033[0m\n' "$*"; }

case "$ACCESS_TYPE" in
  Viewer|Editor|Owner) ;;
  *)
    red "ERROR: accessType must be Viewer, Editor, or Owner (got '$ACCESS_TYPE')."
    exit 2
    ;;
esac

if ! command -v jq >/dev/null 2>&1; then
  red "ERROR: 'jq' is required."
  exit 2
fi

bold "==> Sharing workspace '$WORKSPACE_NAME' with $USER_OR_GROUP_ID ($ACCESS_TYPE) on '$TARGET_ORG'"

# --- Resolve org credentials ------------------------------------------------
ORG_INFO=$(sf org display --target-org "$TARGET_ORG" --json)
ACCESS_TOKEN=$(echo "$ORG_INFO" | jq -r '.result.accessToken')
INSTANCE_URL=$(echo "$ORG_INFO" | jq -r '.result.instanceUrl')

if [[ -z "$ACCESS_TOKEN" || "$ACCESS_TOKEN" == "null" ]]; then
  red "ERROR: Could not obtain access token for '$TARGET_ORG'."
  exit 2
fi

# --- 1. Resolve workspace ID -----------------------------------------------
echo
bold "[1/3] Resolve workspace ID by DeveloperName"
WS_LIST=$(curl -sS \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  "${INSTANCE_URL}/services/data/v${API_VERSION}/tableau/workspaces?limit=200")

# The Tableau workspaces endpoint returns workspaces with a `name` field that
# matches the DeveloperName. Some environments key the array as
# `analyticsWorkspaces`; jq's `..|objects?` is robust to either shape.
WS_ID=$(echo "$WS_LIST" \
  | jq -r --arg n "$WORKSPACE_NAME" \
      '.. | objects? | select(.name == $n) | .id' \
  | head -1)

if [[ -z "$WS_ID" || "$WS_ID" == "null" ]]; then
  red "  ✗ Workspace '$WORKSPACE_NAME' not found in target org."
  yellow "  Did 'sf project deploy --source-dir force-app-tableau' run successfully?"
  yellow "  Raw response (first 500 chars): $(echo "$WS_LIST" | head -c 500)"
  exit 1
fi
green "  ✓ id=$WS_ID"

SHARES_URL="${INSTANCE_URL}/services/data/v${API_VERSION}/tableau/records/${WS_ID}/shares"

# --- 2. Check for existing share -------------------------------------------
echo
bold "[2/3] Check existing shares for $USER_OR_GROUP_ID"
EXISTING=$(curl -sS \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  "${SHARES_URL}?userOrGroupId=${USER_OR_GROUP_ID}&limit=10")

CURRENT_ACCESS=$(echo "$EXISTING" \
  | jq -r --arg uid "$USER_OR_GROUP_ID" \
      '.recordAccessMappings[]? | select(.userOrGroupId == $uid) | .accessType' \
  | head -1)

if [[ "$CURRENT_ACCESS" == "$ACCESS_TYPE" ]]; then
  green "  ✓ Share already exists at $ACCESS_TYPE — idempotent skip."
  exit 0
fi

# --- 3. POST or PATCH share -----------------------------------------------
echo
if [[ -z "$CURRENT_ACCESS" || "$CURRENT_ACCESS" == "null" ]]; then
  bold "[3/3] POST new share ($ACCESS_TYPE)"
  PAYLOAD=$(jq -n --arg t "$ACCESS_TYPE" --arg uid "$USER_OR_GROUP_ID" '{
    accessRequestItems: [{
      accessType: $t,
      applicationDomain: "Tableau",
      setupObjectType: "AnalyticsWorkspace",
      userOrGroupId: $uid
    }]
  }')
  METHOD="POST"
else
  bold "[3/3] PATCH existing share ($CURRENT_ACCESS → $ACCESS_TYPE)"
  PAYLOAD=$(jq -n --arg t "$ACCESS_TYPE" --arg uid "$USER_OR_GROUP_ID" '{
    updateSetupRecordAccessItems: [{
      accessType: $t,
      userOrGroupId: $uid
    }]
  }')
  METHOD="PATCH"
fi

RESPONSE=$(curl -sS -X "$METHOD" "$SHARES_URL" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD")

FAILED_COUNT=$(echo "$RESPONSE" | jq '[.failedRecordShares // []] | length')
SUCCESS_COUNT=$(echo "$RESPONSE" | jq '[.successfulRecordShares // []] | length')

if [[ "$FAILED_COUNT" -gt 0 ]]; then
  red "  ✗ $METHOD reported $FAILED_COUNT failure(s):"
  echo "$RESPONSE" | jq '.failedRecordShares' | sed 's/^/      /'
  exit 1
fi

green "  ✓ $METHOD ok ($SUCCESS_COUNT share(s) applied)."
echo
green "==> $WORKSPACE_NAME shared with $USER_OR_GROUP_ID at $ACCESS_TYPE."
