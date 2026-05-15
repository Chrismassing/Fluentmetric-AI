# FluentMetric AI

A Salesforce-native dashboard that makes Einstein Generative AI Audit &
Feedback data **humanly readable** — resolves User IDs to names, prompt
developer names to labels, pre-joins the 9+ Data Cloud DMOs, and presents
curated dashboards for admins, prompt engineers, and AI product owners.

This repo ships **two editions** of the same product. Pick the one that fits
the customer's licenses.

| | [Lightning Edition](Documents/LIGHTNING-EDITION.md) | [Tableau Next Edition](Documents/TABLEAU-EDITION.md) |
|---|---|---|
| Package directory | `force-app/` | `force-app-tableau/` |
| Tableau license required | **No** | **Yes** (Tableau Next on Salesforce — *not* Tableau Cloud) |
| Surface | 19 native LWCs | Lightning App Page (KPI tile + launcher + agent chat) + Tableau Next workspace dashboards |
| Conversational AI | — | FluentMetric Tableau Analyst agent (3 invocable actions over Data Cloud) |
| Apex dependency | Self-contained | Depends on the Lightning edition's `AiInsightsService` |
| Best for | Anyone with Data Cloud + Audit & Feedback | Customers with Tableau Next provisioned who want drag-and-drop pivot freedom + conversational analytics |

Full comparison and license matrix → [Documents/EDITIONS.md](Documents/EDITIONS.md)

## Quick install

**Lightning edition** (no Tableau required):

```bash
sf project deploy start --source-dir force-app --target-org <your-org> --test-level RunLocalTests
sf org assign permset --name FluentMetric_AI_User --target-org <your-org>
```

**Tableau Next edition** (requires Tableau Next on Salesforce + Agentforce, plus the Lightning edition deployed first):

```bash
# 1. Lightning edition first — Tableau Next edition's Apex delegates to AiInsightsService
sf project deploy start --source-dir force-app --target-org <your-org> --test-level RunLocalTests
# 2. Manually author the FluentMetric_AI semantic model in Tableau Next Data Manager (UI)
# 3. Then deploy Tableau Next edition
sf project deploy start --source-dir force-app-tableau --target-org <your-org> --test-level RunSpecifiedTests --tests FmTableauNextTest
sf org assign permset --name FluentMetric_AI_Tableau_User --target-org <your-org>
sf agent publish --api-name FluentMetric_Tableau_Analyst --target-org <your-org>
```

Full setup → [Documents/TABLEAU-EDITION.md](Documents/TABLEAU-EDITION.md).

## Repo layout

```
sfdx-project.json              # Two packageDirectories
force-app/                     # Lightning edition (default)
force-app-tableau/             # Tableau Next edition
Documents/                     # Design + setup docs (not deployed)
CLAUDE.md                      # Project context for Claude Code
```

## Documents

- [EDITIONS.md](Documents/EDITIONS.md) — pick an edition; license matrix
- [LIGHTNING-EDITION.md](Documents/LIGHTNING-EDITION.md) — Lightning setup
- [TABLEAU-EDITION.md](Documents/TABLEAU-EDITION.md) — Tableau Next setup
- [ARCHITECTURE.md](Documents/ARCHITECTURE.md) — Lightning edition architecture
- [LIVE-SCHEMA.md](Documents/LIVE-SCHEMA.md) — verified DMO schema
- [APEX-SERVICES.md](Documents/APEX-SERVICES.md) — Apex layer reference
- [COMPONENTS.md](Documents/COMPONENTS.md) — LWC reference
- [DEPLOYMENT.md](Documents/DEPLOYMENT.md) — release process
