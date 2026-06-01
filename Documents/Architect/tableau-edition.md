# FluentMetric AI — Tableau Next Edition (Architect)

> **Audience:** Architects evaluating fit, reviewing design intent, or planning
> the workspace authoring cycle.
> Looking to install? See [../Admin/03-install-tableau.md](../Admin/03-install-tableau.md).

The super-powered edition: Tableau Next workspace dashboards over Data Cloud
GenAI Audit data, plus a Lightning App Page entry point hosting a KPI
snapshot tile, an "Open in Tableau Next" launcher, and an Agentforce
conversational analyst.

> **Heads up:** this edition requires **Tableau Next on Salesforce**
> (Salesforce-native analytics, *not* Tableau Cloud). If the customer has
> Tableau Cloud instead, this edition is the wrong fit — the embed model and
> data path are different.

## Prerequisites

| | Required | Notes |
|---|---|---|
| Salesforce Sales/Service Cloud | ✅ | Enterprise Edition or higher. |
| Data Cloud | ✅ | Same DMOs the Lightning edition reads. |
| Einstein GenAI Audit & Feedback | ✅ | The data source itself. |
| Tableau Next on Salesforce | ✅ | Provisions the Tableau Next app (DeveloperName `TableauEinstein`, displayed as **Tableau Next**), the `AnalyticsWorkspace` / `AnalyticsDashboard` / `AnalyticsVisualization` metadata types, and the `SemanticModel` / `SemanticView` / `TableauHostMapping` sObjects. |
| Agentforce | ✅ | Hosts the FluentMetric Tableau Analyst agent. |
| Lightning Edition (`force-app/`) | ✅ | The Tableau edition's Apex delegates to `AiInsightsService` from the Lightning edition. **Lightning must be installed first**, or both deployed together. |
| Platform Cache | Recommended | Same `FluentMetric_AI` partition the Lightning edition uses. |

Detailed admin checklist: [../Admin/01-prerequisites.md](../Admin/01-prerequisites.md).

## What gets deployed

Through `sf project deploy --source-dir force-app-tableau`:

- **Lightning App + Tab + FlexiPage**: `FluentMetric_AI_Tableau`,
  `FluentMetric_AI_Tableau_Home`.
- **3 LWCs**: `fmTableauKpiTile`, `fmTableauNextLauncher`, `fmTableauAgentChat`.
- **Apex** (4 classes + 1 test): `FmTableauNextController`,
  `GetUsageOverviewAction`, `GetUsageByUserAction`, `GetUsageByPromptAction`,
  `FmTableauNextTest`.
- **AnalyticsWorkspace**: `FluentMetric_AI_Workspace` referencing the
  `FluentMetric_AI` semantic model.
- **AnalyticsDashboard / AnalyticsVisualization**: 4 dashboards
  (`FluentMetric_Adoption`, `FluentMetric_Feature_Adoption`,
  `FluentMetric_Tokens_And_Safety`, `FluentMetric_Cost`) + their
  visualizations.
- **Permission Set**: `FluentMetric_AI_Tableau_User`.
- **Custom Labels**: `FM_TBL_*` (including `FM_TBL_Launcher_Workspace_Path`
  for the deep-link target).

Ships **out-of-band** (not via Metadata API):

- **Semantic Model JSON tree** at
  `force-app-tableau/src-non-mdapi/semanticModels/FluentMetric_AI/` —
  published via SSOT REST in `make publish-semantic-model`.
- **Agent bundle** `FluentMetric_Tableau_Analyst` — published via
  `sf agent publish`.

## Design rationale

### Why two Apex layers instead of duplicating logic

Both editions read the same DMOs and apply the same business rules. Rather
than fork `AiInsightsService`, the Tableau edition's invocable actions
(`GetUsageOverviewAction`, `GetUsageByUserAction`, `GetUsageByPromptAction`)
**delegate to the Lightning edition's service classes**. This keeps the
business rules single-sourced and makes the Tableau edition a thin facade.
The cost: Lightning must be installed first. The benefit: behavioural drift
between the two surfaces is impossible.

ADR: [decisions/001-two-editions.md](decisions/001-two-editions.md).

### Why the agent's data path stays inside Salesforce

The `FluentMetric_Tableau_Analyst` agent answers questions by invoking Apex
actions, not by calling Tableau Cloud REST endpoints. **No JWT, no Named
Credentials, no external callouts at runtime.** The SSOT REST endpoints used
during install (`/ssot/semantic/models`) authenticate with the same OAuth
bearer the `sf` CLI already holds — they are *install-time only*.

This makes the runtime governance story straightforward (one Salesforce org,
one auth boundary) and dodges the operational tax of maintaining a
Connected App + JWT cert rotation in customer orgs. The trade-off: rich
Tableau Cloud–only features are off-limits.

### Authoring cycle

`AnalyticsDashboard` and `AnalyticsVisualization` *are* Metadata API types —
once authored once in `cvk-dev` and retrieved into source, every subsequent
install deploys them automatically. The semantic model is **not** a Metadata
API type, so the installer uses the SSOT REST surface
(`POST /ssot/semantic/models`) with idempotent create-or-update logic. JSON
trees are exported via the
[Salesforce Tableau Semantics VS Code extension](https://github.com/forcedotcom/tableau-dx)
and committed alongside the rest of the package.

The first authoring pass is manual — Tableau Next dashboards aren't
reasonably hand-authored as XML.

## Authoring artifacts (one-time, in `cvk-dev`)

These artifacts must exist in `force-app-tableau/` *before* admins can
install. They're authored once per major UX change and committed to source.

### Semantic model JSON tree

1. Author the `FluentMetric_AI` semantic model in `cvk-dev`'s **Data
   Manager** (Tableau Next → Data Manager → Semantic Models → New). Connect
   to the GenAI Audit DMOs documented in
   [../Developer/live-schema.md](../Developer/live-schema.md):
   - `GenerativeAiAuditFeedback__dlm`
   - the GenAI gateway DMOs that surface request/response/feedback rows
   - dimensions: user name, prompt template name, model name
   - measures: request count, acceptance rate, input/output tokens, timestamp
2. Install the [`forcedotcom/tableau-dx`](https://github.com/forcedotcom/tableau-dx) extension.
3. Run **"Export to folder"** targeting
   `force-app-tableau/src-non-mdapi/semanticModels/FluentMetric_AI/`.
4. Commit the exported JSON tree (`model.json` + auxiliary collection files).

### Dashboards as Metadata API artifacts

1. In `cvk-dev`'s Tableau Next workspace, author 4 dashboards mirroring the
   Lightning edition's curated views:
   - `FluentMetric_Adoption` — adoption-rate KPI + active-users trend
   - `FluentMetric_Feature_Adoption` — per-feature breadth/depth
   - `FluentMetric_Tokens_And_Safety` — token consumption + toxicity
   - `FluentMetric_Cost` — token-economics proxies for cost
2. Retrieve into source:
   ```bash
   sf project retrieve start \
       --metadata "AnalyticsDashboard:FluentMetric_*" \
       --metadata "AnalyticsVisualization:FluentMetric_*" \
       --target-org cvk-dev
   ```
3. Commit the retrieved files into
   `force-app-tableau/main/default/analyticsDashboards/` and
   `force-app-tableau/main/default/analyticsVisualizations/`.
4. Update [analyticsWorkspaces/FluentMetric_AI_Workspace.uawork-meta.xml](../../force-app-tableau/main/default/analyticsWorkspaces/FluentMetric_AI_Workspace.uawork-meta.xml)
   with a `<workspaceAssetRelationships>` block per dashboard.

After authoring, every subsequent install is fully automated via
`make install-tableau`.

## Reference — Semantic model REST API surface

For background on what `make publish-semantic-model` actually does:

| Operation | Method | Endpoint |
|---|---|---|
| List models | `GET` | `/services/data/v67.0/ssot/semantic/models` |
| Get one model | `GET` | `/services/data/v67.0/ssot/semantic/models/{apiName}` |
| **Create model** | `POST` | `/services/data/v67.0/ssot/semantic/models` |
| **Update model** | `PUT` | `/services/data/v67.0/ssot/semantic/models/{apiName}` |
| Validate (dry run) | `POST` | `/services/data/v67.0/ssot/semantic/models/validate` |
| List DC data objects | `GET` | `/services/data/v67.0/ssot/semantic/ui/cdp-data-objects` |

> **Beta caveat:** the SSOT semantic-model REST surface is current as of
> May 2026 but documented as Beta. Lock the API version (`v67.0`) and treat
> the JSON shape as evolving — re-export from `tableau-dx` after each
> Tableau Next release.

## Known limitations

- **Semantic model is not a Metadata API type** — published via SSOT REST,
  not `sf project deploy`.
- **Agent activation requires a manual click** — Salesforce does not expose
  a public CLI/API for agent activation as of May 2026. One-time per org.
- **Dashboards must be authored once in `cvk-dev`** — first authoring pass
  is manual; subsequent installs deploy them automatically.
- **No Tableau Cloud, no JWT, no Tableau REST at runtime** — if you need
  Tableau Cloud embedding, this isn't the right edition.
