#!/usr/bin/env bash
# scripts/publish-semantic-model.sh
#
# Idempotently provisions the FluentMetric_AI Tableau Next semantic model into
# the target org via the Data Cloud SSOT REST API.
#
#   GET  /services/data/vXX.X/ssot/semantic/models/FluentMetric_AI
#     → 200  ⇒ PUT  (update existing)
#     → 404  ⇒ POST (create new)
#
# The model JSON is assembled from the tableau-dx export tree under
# force-app-tableau/src-non-mdapi/semanticModels/FluentMetric_AI/.
# That folder is *not* Salesforce metadata — it is managed out of band.
#
# Prerequisites:
#   1. Author the FluentMetric_AI semantic model once in cvk-dev Data Manager.
#   2. Export it via the 'Salesforce Tableau Semantics' VS Code extension
#      (https://github.com/forcedotcom/tableau-dx) → "Export to folder".
#   3. Commit the resulting folder to
#      force-app-tableau/src-non-mdapi/semanticModels/FluentMetric_AI/.
#
# Usage: ./scripts/publish-semantic-model.sh <target-org-alias>

set -euo pipefail

TARGET_ORG="${1:-${TARGET_ORG:-cvk-dev}}"
API_VERSION="${API_VERSION:-67.0}"
MODEL_NAME="${MODEL_NAME:-FluentMetric_AI}"
MODEL_DIR="${MODEL_DIR:-force-app-tableau/src-non-mdapi/semanticModels/${MODEL_NAME}}"

red()    { printf '\033[31m%s\033[0m\n' "$*"; }
green()  { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
bold()   { printf '\033[1m%s\033[0m\n' "$*"; }

bold "==> Publishing semantic model '$MODEL_NAME' to org '$TARGET_ORG'"

if ! command -v jq >/dev/null 2>&1; then
  red "ERROR: 'jq' is required. Install via 'brew install jq'."
  exit 2
fi

if [[ ! -d "$MODEL_DIR" ]]; then
  red   "ERROR: Semantic model export folder not found: $MODEL_DIR"
  yellow "Run the tableau-dx 'Export to folder' command in VS Code first."
  yellow "See Documents/TABLEAU-EDITION.md → Phase A for the authoring workflow."
  exit 2
fi

if [[ ! -f "$MODEL_DIR/model.json" ]]; then
  red   "ERROR: $MODEL_DIR/model.json not found. The export looks incomplete."
  exit 2
fi

# --- Resolve org credentials ------------------------------------------------
ORG_INFO=$(sf org display --target-org "$TARGET_ORG" --json)
ACCESS_TOKEN=$(echo "$ORG_INFO" | jq -r '.result.accessToken')
INSTANCE_URL=$(echo "$ORG_INFO" | jq -r '.result.instanceUrl')

if [[ -z "$ACCESS_TOKEN" || "$ACCESS_TOKEN" == "null" ]]; then
  red "ERROR: Could not obtain access token for org '$TARGET_ORG'. Run 'sf org login web --alias $TARGET_ORG'."
  exit 2
fi

BASE_URL="${INSTANCE_URL}/services/data/v${API_VERSION}/ssot/semantic/models"

# --- Assemble the payload ---------------------------------------------------
# The exact JSON shape is defined by tableau-dx. We pass through model.json
# as the canonical body. Any auxiliary collection files (relationships,
# calc dimensions, etc.) are referenced by tableau-dx inside model.json.
# If your export uses split files, merge them here before POST/PUT — the
# block below is the simplest pass-through that works for a flat export.
PAYLOAD_FILE="$(mktemp)"
trap 'rm -f "$PAYLOAD_FILE"' EXIT

cp "$MODEL_DIR/model.json" "$PAYLOAD_FILE"

# --- Detect existing model --------------------------------------------------
echo
bold "[1/2] Checking whether '$MODEL_NAME' already exists..."
HTTP_STATUS=$(curl -sS -o /dev/null -w '%{http_code}' \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  "${BASE_URL}/${MODEL_NAME}")

case "$HTTP_STATUS" in
  200)
    yellow "  Found existing model — will UPDATE via PUT."
    METHOD="PUT"
    URL="${BASE_URL}/${MODEL_NAME}"
    ;;
  404)
    green "  No existing model — will CREATE via POST."
    METHOD="POST"
    URL="${BASE_URL}"
    ;;
  401|403)
    red "  HTTP $HTTP_STATUS — access denied. The user must have the 'Tableau Next Admin' (TableauEinsteinAdmin) permset."
    exit 1
    ;;
  *)
    red "  Unexpected HTTP $HTTP_STATUS from GET ${BASE_URL}/${MODEL_NAME}"
    yellow "  This may indicate the SSOT semantic-model API is not enabled in this org's Data Cloud edition."
    exit 1
    ;;
esac

# --- Apply the change -------------------------------------------------------
echo
bold "[2/2] $METHOD $URL"
RESPONSE_FILE="$(mktemp)"
RESPONSE_TRAP_OLD=$(trap -p EXIT)
trap 'rm -f "$PAYLOAD_FILE" "$RESPONSE_FILE"' EXIT

HTTP_STATUS=$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X "$METHOD" "$URL" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  --data-binary "@$PAYLOAD_FILE")

if [[ "$HTTP_STATUS" -ge 200 && "$HTTP_STATUS" -lt 300 ]]; then
  green "  Success ($HTTP_STATUS). Response:"
  jq '.' < "$RESPONSE_FILE" 2>/dev/null || cat "$RESPONSE_FILE"
  echo
  green "==> Semantic model '$MODEL_NAME' is published."
else
  red "  Failed (HTTP $HTTP_STATUS). Response:"
  jq '.' < "$RESPONSE_FILE" 2>/dev/null || cat "$RESPONSE_FILE"
  echo
  red "==> Semantic model publish failed. See response above for validation errors."
  exit 1
fi
