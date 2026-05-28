# 03 — Install the Tableau Next Edition

> **Time:** ~30 minutes. **CLI required:** none for the install URL itself.
> **Manual steps the URL can't perform:** semantic-model publish + agent
> activation. Both have UI-equivalent workflows below.

> ⚠️ **This edition requires Tableau Next on Salesforce — *not* Tableau
> Cloud.** If your org has Tableau Cloud, this is the wrong edition.

## Before you start

- ✅ [02-install-lightning.md](02-install-lightning.md) is complete — the
  Lightning edition's Apex is a hard dependency.
- ✅ The Tableau Next prerequisites in [01-prerequisites.md](01-prerequisites.md)
  are green: `TableauEinsteinIncludedAppPsl` PSL is active, the **Tableau
  Next** app is in your App Launcher, and Agentforce is licensed.
- ✅ You have the Tableau-edition install URL from [../../CHANGELOG.md](../../CHANGELOG.md).

## Step 1 — Install the Tableau-edition package

1. Open the **Tableau-edition install URL** from CHANGELOG.md.
   - The 2GP install URL declares the Lightning edition as a dependency; if
     for any reason Lightning isn't installed yet, the install will pull it
     in first. (You should still install Lightning first explicitly so you
     can validate it independently.)
2. **Install for Admins Only**. Approve third-party access if prompted.
3. Wait for install to finish.

> **What's now in your org (in addition to the Lightning edition):** 1 new
> Lightning App (`FluentMetric AI Tableau`), 1 tab, 1 FlexiPage, 3 LWCs
> (KPI tile, launcher, agent chat), 4 Apex classes (controller + 3
> invocable actions), 1 AnalyticsWorkspace, 4 AnalyticsDashboards,
> 1 Permission Set (`FluentMetric_AI_Tableau_User`), `FM_TBL_*` Custom
> Labels.
>
> **What's NOT yet in your org:** the **Semantic Model** (deployed
> separately — Step 2) and the **Agentforce agent activation** (Step 4).

## Step 2 — Publish the Semantic Model

The Tableau Next semantic model is *not* a Metadata API artifact, so the
install URL can't deploy it. There are two paths:

### Option A — Run the helper script (recommended if your release engineer is available)

If you have shell access and the SF CLI installed:

```bash
make publish-semantic-model TARGET_ORG=<your-org-alias>
```

This script POSTs the committed JSON tree to
`/services/data/v67.0/ssot/semantic/models` using your existing `sf` CLI
session — no new credentials needed. Idempotent.

### Option B — Author manually in Data Manager

If you can't run the script, recreate the model in the Setup UI:

1. Open the **Tableau Next** app → **Data Manager** → **Semantic Models** → **New**.
2. Name it `FluentMetric_AI` (exact API name — the agent and dashboards reference it).
3. Connect it to the Einstein GenAI Audit DMOs (`GenerativeAiAuditFeedback__dlm`
   plus the gateway DMOs surfacing request / response / feedback rows).
4. Define the dimensions and measures listed in
   [../Architect/tableau-edition.md](../Architect/tableau-edition.md#authoring-artifacts-one-time-in-cvk-dev).
5. Save and publish.

Either way, after this step the semantic model exists in your org.

## Step 3 — Assign permissions

Setup → Permission Sets, assign each of these to the same end users:

| Type | Name | Why |
|---|---|---|
| PSL | `TableauEinsteinIncludedAppPsl` | Tableau Next app access |
| Permission Set | `TableauEinsteinAdmin` | Build / view dashboards |
| Permission Set | `TableauEinsteinAnalyst` | Author dashboards (admins only) |
| Permission Set | `FluentMetric_AI_Tableau_User` | FluentMetric Tableau app + agent access |

> Same drill as the Lightning permset assignment in Step 2 of
> [02-install-lightning.md](02-install-lightning.md) — pick users via
> **Manage Assignments → Add Assignments**.

## Step 4 — Activate the Agentforce agent

The package ships the agent bundle (`FluentMetric_Tableau_Analyst`) but
Salesforce does not expose a public API for *activating* an agent — one
manual click is required.

1. **Setup → Einstein → Copilots** (URL: `${INSTANCE_URL}/lightning/setup/EinsteinCopilot/home`).
2. Find **FluentMetric Tableau Analyst** in the list.
3. Click **Activate**.

After activation, the agent appears in the Einstein Copilot tray for any
user who has `FluentMetric_AI_Tableau_User` assigned.

## Step 5 — Smoke test

1. **App Launcher → FluentMetric AI Tableau**.
2. The home page shows three regions:
   - **GenAI Snapshot** tile — KPIs (request volume, unique users,
     acceptance rate, tokens) for the last 30 days.
   - **Open in Tableau Next** launcher — click it, you should land on the
     `FluentMetric_AI_Workspace` with all four dashboards.
   - **Agent chat panel** — open Einstein Copilot, pick **FluentMetric
     Tableau Analyst**, ask: *"What was the prompt acceptance rate last
     week?"* The agent should respond with numbers, not an error.
3. Optionally re-run the verifier:

   ```bash
   make verify-tableau TARGET_ORG=<your-org-alias>
   ```

## What's next

- **Train end users** with [04-getting-started.md](04-getting-started.md).
- **Customize cost rates / Wallet / adoption denominator:**
  [05-configure.md](05-configure.md).
- **Something not rendering?** [06-troubleshooting.md](06-troubleshooting.md).
