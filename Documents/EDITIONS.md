# FluentMetric AI — Editions Guide

This repository ships **two editions** of the same product. Pick the one that
matches the licenses your customer already owns.

| | **Lightning Edition** | **Tableau Next Edition** |
|---|---|---|
| Package directory | `force-app/` | `force-app-tableau/` |
| Unlocked package | `FluentMetric AI` | `FluentMetric AI for Tableau Next` |
| Surface | 19 native LWCs on a Lightning App Page | Lightning App Page (KPI tile + launcher + agent chat) + the Tableau Einstein app for full dashboards |
| Data path | Apex → Data Cloud DMOs (SOQL) | Apex → Data Cloud DMOs (SOQL) for the Salesforce-side surface; Tableau Next semantic model → Data Cloud (native, in-platform) for the workspace |
| Dashboards | KPI cards, drill panels, Explorer pivot | Tableau Next workspace dashboards (drag-drop pivot, full canvas) |
| Conversational AI | — | Agentforce "Tableau Analyst" agent with three Apex invocable actions (overview / users / prompts) |
| Cost engine | `CostCalculatorService` (Flex Credit modeling) | Modeled inside Tableau Next semantic dataset |
| Apex dependency | Self-contained | Depends on the Lightning edition's Apex services, DAO, DTOs |
| Min Salesforce edition | Enterprise + | Enterprise + |

The two editions can co-exist in the same org. The Tableau Next edition's
Apex layer **delegates to the Lightning edition's `AiInsightsService`** — so
the Lightning edition must be deployed first.

## License matrix

| Capability | Lightning Edition | Tableau Next Edition |
|---|---|---|
| Salesforce Sales/Service Cloud | Required | Required |
| Data Cloud | Required | Required |
| Einstein GenAI Audit & Feedback | Required | Required |
| Tableau Next on Salesforce | — | **Required** |
| Tableau Einstein app provisioned in org | — | **Required** |
| Agentforce | — | **Required** for chat surface |
| Platform Cache (FluentMetric_AI partition) | Recommended | Recommended |

> **Important:** This edition targets **Tableau Next** — the Salesforce-native
> analytics product (semantic models, AnalyticsWorkspace/Dashboard/Visualization
> metadata, in-platform). It is **not** Tableau Cloud / Tableau Server. There
> is no JWT Connected App, no REST callouts, and no Tableau site URL.

## When to choose which

**Pick the Lightning Edition if:**
- The customer doesn't have Tableau Next provisioned.
- Native Lightning UX is sufficient (KPI cards, drill panels, Explorer pivot).

**Pick the Tableau Next Edition if:**
- The customer has Tableau Next on Salesforce enabled.
- Analysts need drag-and-drop pivot freedom that LWC dashboards can't match.
- Conversational analytics ("top users this week", "which prompts dropped in
  acceptance?") is on the requirements list.

## Install both?

Both packages can be deployed to the same org. Some customers will run them
side-by-side: the Lightning edition for ops users (curated dashboards), and
the Tableau Next edition for analysts who want raw exploratory power +
conversational agent.

## Setup guides

- Lightning edition setup → [LIGHTNING-EDITION.md](./LIGHTNING-EDITION.md)
- Tableau Next edition setup → [TABLEAU-EDITION.md](./TABLEAU-EDITION.md)
