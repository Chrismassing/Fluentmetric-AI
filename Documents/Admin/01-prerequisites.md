# 01 — Prerequisites

> Confirm everything in this checklist *before* you click an install URL.
> Most install failures we see in the field are missing prerequisites, not
> bugs in the package.

## Org-level features

| Feature | How to verify | Where to enable |
|---|---|---|
| **Data Cloud** | Setup → Data Cloud → Data Cloud is **Enabled** | Provisioned by Salesforce or via Sales/Service Cloud bundle. If missing, open a Salesforce case. |
| **Einstein Generative AI Audit & Feedback** | Setup → Einstein → Generative AI → Audit and Feedback Data is **On** | Setup → Einstein → Generative AI → toggle **Audit and Feedback Data** |
| **At least 1,000 audit rows** (recommended) | Use any Audit DMO query — see [../Developer/live-schema.md](../Developer/live-schema.md) | Use the org for ~1 week of normal Einstein activity. The dashboards work with less data, but headlines look sparse. |

## License entitlements

### For the Lightning edition

No additional licenses required beyond Sales/Service Cloud Enterprise + Data
Cloud + Einstein GenAI.

### For the Tableau Next edition (additional)

| License / PSL | Verify |
|---|---|
| **Tableau Next on Salesforce** | Setup → Permission Set Licenses → look for `TableauEinsteinIncludedAppPsl` *or* `TableauEinsteinUserPsl` with **Status = Active**. |
| **Agentforce** (Einstein Copilot) | Setup → Einstein → Copilot exists in nav. |

If `TableauEinsteinIncludedAppPsl`, `TableauEinsteinUserPsl`, and
`TableauBusinessUserPsl` are *all* missing, **Tableau Next is not provisioned
in the org** — open a Salesforce case before continuing.

## Platform Cache (recommended)

The Lightning edition uses Platform Cache for User and Prompt name
resolution. Without it, the package falls back to per-request SOQL — slower
but functional.

To provision (Setup-UI):

1. **Setup → Platform Cache → New Platform Cache Partition**.
2. **Label:** `FluentMetric AI`. **Name:** `FluentMetric_AI`.
3. **Org Cache Allocation:** at least **5 MB**.
4. **Default Partition:** leave unchecked.
5. Save.

The package's metadata declares the partition; the install URL will skip
provisioning if the partition exists with at least 5 MB allocated.

## User permissions

The admin doing the install needs:

- **System Administrator** (or equivalent) profile
- For the Tableau Next edition: also assign yourself
  `TableauEinsteinIncludedAppPsl` (PSL), `TableauEinsteinAdmin` (permset),
  and `TableauEinsteinAnalyst` (permset). After assignment, log out and back
  in — the **Tableau Next** app appears in the App Launcher.

## What to do if anything in this checklist is missing

| Missing | Action |
|---|---|
| Data Cloud not enabled | Salesforce case |
| Einstein Audit & Feedback not enabled | Setup toggle (link above) |
| Tableau Next not provisioned | Salesforce case **before** install |
| Agentforce not licensed | Skip the Tableau edition install for now |
| Platform Cache partition not provisioned | Provision it (steps above), or accept slower name resolution |

Once the checklist is green, head to
[02-install-lightning.md](02-install-lightning.md).
