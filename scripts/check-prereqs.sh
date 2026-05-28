#!/usr/bin/env bash
# scripts/check-prereqs.sh
#
# Verifies that the target org has Tableau Next provisioned before the
# FluentMetric AI for Tableau Next install runs. Hard-fails with a remediation
# message if any check fails — there is no point continuing the install
# otherwise.
#
# Usage: ./scripts/check-prereqs.sh <target-org-alias>

set -euo pipefail

TARGET_ORG="${1:-${TARGET_ORG:-cvk-dev}}"
API_VERSION="${API_VERSION:-67.0}"

red()   { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
yellow(){ printf '\033[33m%s\033[0m\n' "$*"; }
bold()  { printf '\033[1m%s\033[0m\n' "$*"; }

bold "==> Checking Tableau Next prerequisites in org '$TARGET_ORG'"

require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    red "ERROR: 'jq' is required. Install via 'brew install jq' (macOS) or your package manager."
    exit 2
  fi
}

require_sf() {
  if ! command -v sf >/dev/null 2>&1; then
    red "ERROR: Salesforce CLI ('sf') is required. See https://developer.salesforce.com/tools/salesforcecli"
    exit 2
  fi
}

require_jq
require_sf

FAIL=0

# --- Check 1: Tableau Next CustomApplication exists -------------------------
echo
bold "[1/3] CustomApplication 'TableauEinstein' (label: Tableau Next)"
APP_COUNT=$(sf data query \
  --query "SELECT Id FROM CustomApplication WHERE DeveloperName = 'TableauEinstein'" \
  --target-org "$TARGET_ORG" \
  --use-tooling-api \
  --json 2>/dev/null | jq -r '.result.totalSize // 0')

if [[ "$APP_COUNT" -ge 1 ]]; then
  green "  OK — Tableau Next app is installed."
else
  red "  FAIL — Tableau Next app not found."
  yellow "  Remediation: Tableau Next must be provisioned by Salesforce. Open a case before continuing."
  FAIL=1
fi

# --- Check 2: Tableau Next sObjects exist -----------------------------------
echo
bold "[2/3] Required sObjects: SemanticModel, SemanticView, TableauHostMapping"
SOBJ_COUNT=$(sf data query \
  --query "SELECT QualifiedApiName FROM EntityDefinition WHERE QualifiedApiName IN ('SemanticModel','SemanticView','TableauHostMapping')" \
  --target-org "$TARGET_ORG" \
  --use-tooling-api \
  --json 2>/dev/null | jq -r '.result.totalSize // 0')

if [[ "$SOBJ_COUNT" -eq 3 ]]; then
  green "  OK — all 3 Tableau Next sObjects present."
else
  red "  FAIL — expected 3 Tableau Next sObjects, found $SOBJ_COUNT."
  yellow "  Remediation: Tableau Next is not fully provisioned in this org. Open a Salesforce case."
  FAIL=1
fi

# --- Check 3: Tableau Next Permission Set Licenses --------------------------
echo
bold "[3/3] Permission Set Licenses: TableauEinsteinIncludedAppPsl / TableauEinsteinUserPsl"
PSL_COUNT=$(sf data query \
  --query "SELECT DeveloperName FROM PermissionSetLicense WHERE DeveloperName IN ('TableauEinsteinIncludedAppPsl','TableauEinsteinUserPsl','TableauBusinessUserPsl') AND Status = 'Active'" \
  --target-org "$TARGET_ORG" \
  --json 2>/dev/null | jq -r '.result.totalSize // 0')

if [[ "$PSL_COUNT" -ge 1 ]]; then
  green "  OK — at least one active Tableau Next PSL is available for assignment."
else
  red "  FAIL — no active Tableau Next PSL found."
  yellow "  Remediation: contact your Salesforce account team to enable Tableau Next licensing."
  FAIL=1
fi

echo
if [[ "$FAIL" -ne 0 ]]; then
  red "==> Prerequisites NOT met. Aborting."
  exit 1
fi

green "==> All prerequisites met."
