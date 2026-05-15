# FluentMetric AI — Tableau Next Edition

The super-powered edition: Tableau Next workspace dashboards over Data Cloud
GenAI Audit data, plus a Lightning App Page entry point hosting a KPI
snapshot tile, an "Open in Tableau Next" launcher, and an Agentforce
conversational analyst.

> **Heads up:** this edition requires **Tableau Next on Salesforce**
> (Salesforce-native analytics, not Tableau Cloud). If the customer has
> Tableau Cloud instead, this edition is the wrong fit — the embed model and
> data path are different.

## Prerequisites

| | Required | Notes |
|---|---|---|
| Salesforce Sales/Service Cloud | ✅ | Enterprise Edition or higher. |
| Data Cloud | ✅ | Same DMOs the Lightning edition reads. |
| Einstein GenAI Audit & Feedback | ✅ | The data source itself. |
| Tableau Next on Salesforce | ✅ | Provisions the `Tableau Einstein` app, the AnalyticsWorkspace / AnalyticsDashboard / AnalyticsVisualization metadata types, and the `TableauHostMapping` sObject in the org. |
| Agentforce | ✅ | Hosts the FluentMetric Tableau Analyst agent. |
| Lightning Edition (`force-app/`) of this repo | ✅ | The Tableau Next edition's Apex delegates to `AiInsightsService` from the Lightning edition. Deploy `force-app/` first. |
| Platform Cache | Recommended | Same `FluentMetric_AI` partition the Lightning edition uses. |

## Setup steps

### 1. Tableau Next — author the FluentMetric_AI semantic model

Tableau Next semantic models are **not deployable via the Salesforce Metadata
API** — they're authored in the Tableau Next Data Manager UI and referenced
by name from the workspace XML this package ships.

1. Open the **Tableau Einstein** app in your org (App Launcher → Tableau
   Einstein).
2. Navigate to **Data Manager → Semantic Models → New**.
3. Name it exactly **`FluentMetric_AI`** (must match the
   `<asset>FluentMetric_AI</asset>` value in
   [analyticsWorkspaces/FluentMetric_AI_Workspace.uawork-meta.xml](../force-app-tableau/main/default/analyticsWorkspaces/FluentMetric_AI_Workspace.uawork-meta.xml)).
4. Connect it to the GenAI Audit DMOs (see
   [LIVE-SCHEMA.md](./LIVE-SCHEMA.md) for field-level detail). At minimum:
   - `GenerativeAiAuditFeedback__dlm`
   - related GenAI gateway DMOs that surface request/response/feedback rows
5. Define dimensions and measures: user name, prompt template name, model
   name, request count, acceptance rate, input/output tokens, timestamp.

### 2. Salesforce — Deploy the Lightning Edition first

```bash
sf project deploy start \
    --source-dir force-app \
    --target-org <your-org> \
    --test-level RunLocalTests
```

The Tableau Next edition's Apex (`FmTableauNextController`,
`GetUsageOverviewAction`, `GetUsageByUserAction`, `GetUsageByPromptAction`)
delegates to `AiInsightsService` from this package. Without it the Tableau
Next edition won't compile.

### 3. Salesforce — Deploy the Tableau Next Edition

```bash
sf project deploy start \
    --source-dir force-app-tableau \
    --target-org <your-org> \
    --test-level RunSpecifiedTests \
    --tests FmTableauNextTest
```

This deploys:

- **Lightning shell**: `FluentMetric_AI_Tableau` app, `FluentMetric_AI_Tableau` tab,
  `FluentMetric_AI_Tableau_Home` FlexiPage, `FluentMetric_AI_Tableau_User`
  permission set.
- **3 LWCs**: `fmTableauKpiTile`, `fmTableauNextLauncher`,
  `fmTableauAgentChat`.
- **Apex**: `FmTableauNextController` (KPI tile + launcher target),
  three invocable actions for the agent, plus `FmTableauNextTest` (9 tests).
- **Tableau Next workspace**: `FluentMetric_AI_Workspace` (uawork) — references
  the `FluentMetric_AI` semantic model.
- **Custom Labels**: `FM_TBL_*`.

### 4. Salesforce — Permission Set

```bash
sf org assign permset --name FluentMetric_AI_Tableau_User --target-org <your-org>
```

### 5. Tableau Next — author the dashboard in the UI

`AnalyticsDashboard` and `AnalyticsVisualization` files are XML-heavy and
brittle when authored by hand. The recommended workflow:

1. In the **Tableau Einstein** app, open the **FluentMetric_AI Workspace**
   created by step 3.
2. Build dashboards using the FluentMetric_AI semantic model — start with one
   "Usage Overview" dashboard mirroring the Lightning edition's KPI strip,
   then add User Adoption, Prompt Performance, Cost.
3. Once the dashboards exist, retrieve them into source for version control:
   ```bash
   sf project retrieve start \
       --metadata "AnalyticsDashboard:FluentMetric_*" \
       --metadata "AnalyticsVisualization:FluentMetric_*" \
       --target-org <your-org>
   ```
4. Commit the retrieved files into `force-app-tableau/main/default/`.

### 6. Agentforce — Activate the Tableau Analyst

The `aiAuthoringBundles/FluentMetric_Tableau_Analyst` is part of source. To
publish:

```bash
sf agent publish --api-name FluentMetric_Tableau_Analyst --target-org <your-org>
```

Then activate in **Agent Builder**. The agent uses these Apex Invocable
Actions deployed by this package: `GetUsageOverviewAction`,
`GetUsageByUserAction`, `GetUsageByPromptAction`. All three call the Lightning
edition's `AiInsightsService` — no external callouts.

## What gets deployed

- **Lightning App + Tab + FlexiPage**: `FluentMetric_AI_Tableau`,
  `FluentMetric_AI_Tableau_Home`.
- **3 LWCs**: `fmTableauKpiTile`, `fmTableauNextLauncher`,
  `fmTableauAgentChat`.
- **Apex** (4 classes + 1 test): `FmTableauNextController`,
  `GetUsageOverviewAction`, `GetUsageByUserAction`, `GetUsageByPromptAction`,
  `FmTableauNextTest`.
- **AnalyticsWorkspace**: `FluentMetric_AI_Workspace` (referencing the
  `FluentMetric_AI` semantic model authored manually in step 1).
- **Permission Set**: `FluentMetric_AI_Tableau_User`.
- **Custom Labels**: `FM_TBL_*` (including `FM_TBL_Launcher_Workspace_Path`
  for the deep-link target).
- **Agent bundle**: `FluentMetric_Tableau_Analyst` (published via
  `sf agent publish`, not bundled into the project deploy).

## Verification

1. Navigate to the **FluentMetric AI for Tableau Next** app.
2. The **GenAI Snapshot** tile should render KPIs (request volume, unique
   users, acceptance rate, total tokens) for the last 30 days.
3. Click **Open in Tableau Next** — it navigates to the Tableau Einstein
   app where the FluentMetric_AI workspace lives.
4. Open Einstein Copilot, pick **FluentMetric Tableau Analyst**, ask
   "what was the prompt acceptance rate last week?" — confirm the agent
   invokes `GetUsageOverviewAction` and returns the headline numbers.

## Known limitations

- **Semantic model authoring is manual**: the `FluentMetric_AI` semantic model
  must be authored in the Tableau Next Data Manager UI before the workspace
  XML deploys cleanly. The workspace references it by name.
- **Dashboard XML is hand-authored after the fact**: this package ships only
  the workspace as a deployable starting point. Dashboards are intended to be
  built in the Tableau Next UI, then retrieved into source.
- **No Tableau Cloud, no JWT, no REST**: this edition is Salesforce-native.
  If you need Tableau Cloud embedding instead, this is not the right
  edition.
