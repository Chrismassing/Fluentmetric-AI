# 05 — Configure FluentMetric AI

> **Audience:** Admins tuning the package post-install. All steps are
> Setup-UI; no code.

There are three independent configuration surfaces:

1. **Cost engine** (Custom Setting + Custom Metadata)
2. **Adoption denominator** (Permission Set assignment)
3. **Permission Set assignment** (Setup → Permission Sets)

## 1. Cost engine

The Cost tab is **disabled by default** to avoid showing rough estimates
without admin sign-off. Two-step opt-in:

### 1a. Enable cost analysis

1. **Setup → Custom Settings → FluentMetric Cost Settings → Manage**.
2. **New** (or **Edit** if a Default Organization Level Value already exists).
3. Set:
   - **Enable Cost Analysis** = ✅ checked
   - **Default Flex Credit Rate (USD)** = your org's negotiated FC rate
     (typical: `$0.0006` per FC — confirm with your AE).
   - **Fallback Model** = the model name to use when the request row
     doesn't carry one (typical: `gpt-4o-mini`).
4. Save.

The Cost tab now renders. Confidence badges appear on every row:

| Badge | Meaning |
|---|---|
| **ACTUAL** | Cost came from Digital Wallet (`TenantEnrichedUsageEvent__dll`). Most precise. |
| **HIGH** | Tier-rate estimate using a known model name. |
| **ESTIMATED** | Tier-rate estimate using the fallback model (request row had no model name). |
| **FALLBACK** | Estimate after Wallet was attempted but unavailable. |
| **NOT_COSTED** | Couldn't compute — typically a malformed row. |

### 1b. (Recommended) Enable Wallet-first cost

If the org has Digital Wallet (Consumption Tagging app installed and
`TenantEnrichedUsageEvent__dll` populated):

1. Same Custom Setting record from step 1a.
2. Tick **Enable Wallet Costs** = ✅.
3. Save.

`CostCalculatorService` now calls `AiWalletDAO.isWalletAvailable()` first;
if Wallet returns true, dashboards show **ACTUAL** badges. If Wallet is
unavailable for any reason (org doesn't have it, transient API error), the
service falls back silently to tier-rate estimates with **FALLBACK** badges.
Dashboards never error.

### 1c. (Optional) Customize per-model rate cards

If your org has negotiated different FC rates for different models:

1. **Setup → Custom Metadata Types → FluentMetric Cost Rate Card → Manage Records**.
2. **New** for each model:
   - **Model Name** = exact model identifier (e.g., `gpt-4o`, `claude-3-5-sonnet`).
   - **FC per 1k Input Tokens** + **FC per 1k Output Tokens**.
3. Save.

When a model has a rate-card row, the Cost tab uses it; otherwise it falls
back to the Custom Setting's Default Rate.

## 2. Adoption denominator (entitled-user count)

The Adoption tab computes `adoption rate = (active users) / (entitled users)`.
"Entitled" is defined by membership of a single permission set —
`FluentMetric_AI_Entitled_User` — that ships with the package and grants
no functional access on its own (runtime AI permissions still come from
Einstein Generative AI User / Prompt Template User / etc.).

1. **Setup → Permission Sets → FluentMetric AI Entitled User → Manage Assignments → Add Assignments**.
2. Select every user expected to use Einstein Generative AI features —
   typically the same population you assigned `Einstein Generative AI User`
   to, but the two lists are independent so you can scope adoption
   measurement narrower (e.g., a pilot cohort) or wider (e.g., everyone
   you *plan* to onboard).
3. **Assign**.

Reload the FluentMetric AI app — the Adoption tab now uses the assignee
count as the denominator.

> **`entitledFallback=true` in the funnel tooltip** = `FluentMetric_AI_Entitled_User`
> has zero assignees in this org (or the underlying PSA query failed) and
> the engine silently fell back to "all active users". Treat as a config
> signal, not a bug — assign the permset to scope the denominator.

### Tableau Next: nightly entitlement sync

If you have the Tableau Next edition, the SDM-side adoption rate reads
`User.FluentMetric_IsEntitled__c`, which is stamped from PSA by the
`FluentMetricEntitlementSyncSchedulable` Apex job. The installer
(`make install`) schedules the job nightly at 02:00 org time. Verify it's
running with:

```bash
sf data query --query \
  "SELECT CronExpression, NextFireTime FROM CronTrigger \
   WHERE CronJobDetail.Name LIKE '%FluentMetric Entitlement Sync%'"
```

If you change permset assignments mid-day and need the Tableau dashboard
to refresh immediately, run the sync ad-hoc from Anonymous Apex:

```apex
FluentMetricEntitlementSyncSchedulable.syncEntitledFlags();
```

The Lightning side resolves PSA live every transaction and never needs
a manual refresh.

## 3. Permission Set assignment patterns

| Permset | Edition | Grants |
|---|---|---|
| `FluentMetric_AI_User` | Lightning | App, tab, all 19 LWCs, controller Apex |
| `FluentMetric_AI_Tableau_User` | Tableau Next | App, tab, KPI tile / launcher / agent chat, invocable actions |
| `TableauEinsteinIncludedAppPsl` (PSL) | Tableau Next | Tableau Next app access (license-bearing) |
| `TableauEinsteinAdmin` | Tableau Next | Build / view dashboards |
| `TableauEinsteinAnalyst` | Tableau Next | Author dashboards |

Common patterns:

- **End user, Lightning only** — assign `FluentMetric_AI_User`. Make sure
  they also have a Permission Set Group that grants Data Cloud read.
- **End user, Tableau Next** — assign all five rows above (you can bundle
  them in a Permission Set Group for hygiene).
- **Author / power user** — same as end user plus author privileges on
  Custom Settings if you want them to tweak rates without you.

## What this guide doesn't cover

- **Adding new dashboards** — that's a developer task. See
  [../Developer/README.md](../Developer/README.md).
- **Building new agent skills** — see
  [../Architect/tableau-edition.md](../Architect/tableau-edition.md) for the
  agent architecture.
- **Customizing Tableau Next dashboards** — author in `cvk-dev` and re-cut a
  release. The package's dashboards ship as immutable Metadata API
  artifacts.
