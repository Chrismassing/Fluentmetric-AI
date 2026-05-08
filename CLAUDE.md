# FluentMetric AI — Project Context for Claude Code

## What This Project Is

A Salesforce-native Lightning app that makes Einstein Generative AI Audit & Feedback DMO data **humanly readable** — resolving User IDs to names, prompt developer names to labels, pre-joining the 9+ Data Cloud DMOs, and presenting curated dashboards + a dynamic Explorer for admins, prompt engineers, and AI product owners.

Packaged two ways for shareability:
1. **Source tree** in this git repo — recipients run `sf project deploy start --source-dir force-app --target-org <theirs>`
2. **Unlocked Package (2GP)** from `cvk-dev` DevHub — recipients get a one-click install URL

## Architecture

4-layer Apex: **LWC → Controller → Service → DAO**. Full detail in [Documents/ARCHITECTURE.md](Documents/ARCHITECTURE.md).

- `AiInsightsController` — `@AuraEnabled(cacheable=true)` for all dashboard reads + `runExplorerQuery` for dynamic pivots
- `AiInsightsService` — business logic, aggregation, sorting (since DMO SOQL cannot ORDER BY aggregates)
- `AiInsightsDAO` — all DMO `Database.query()` calls, interface-backed for mockability
- `UserResolverService` — User/Prompt name resolution with Platform Cache + graceful degradation
- `AiInsightsDateRange` LMS channel — one publisher (date filter), N subscribers (dashboards)

## Key Design Docs (read before coding)

- **[Documents/LIVE-SCHEMA.md](Documents/LIVE-SCHEMA.md)** — verified DMO schema from `cvk-dev`. **This overrides DATA-MODEL.md where they disagree.** Live schema uses camelCase fields (`userId__c`, `timestamp__c`), and prompt template names are directly on the Request row (no tag join needed).
- [Documents/APEX-SERVICES.md](Documents/APEX-SERVICES.md) — class structure, method signatures, DTOs
- [Documents/COMPONENTS.md](Documents/COMPONENTS.md) — LWC specifications, layout, behavior
- [Documents/DEPLOYMENT.md](Documents/DEPLOYMENT.md) — project structure, what ships in the package

## Coding Standards

- **Apex:** `with sharing` on every class. All DMO queries via `Database.query()` (dynamic SOQL — `__dlm` objects require it). All controller reads are `@AuraEnabled(cacheable=true)`.
- **DMO SOQL rules:**
  - Field names are camelCase with `__c` suffix; object names are PascalCase with `__dlm` suffix
  - Use `timestamp__c` for date filtering, NOT `CreatedDate__c`
  - Do NOT `ORDER BY COUNT(Id)` — sort aggregates in Apex
  - Do NOT use parent-child SOQL subqueries — join in Apex via business keys
  - Always date-filter to avoid scanning the full DMO
- **LWC:** SLDS only, no external CSS. All components must handle loading / empty / error states. Cross-component comms via LMS channel `AiInsightsDateRange`.
- **Testing:** DAO interface + mock pattern. DMO data never exists in Apex test context. Target 80%+ coverage.

## File Organization

```
force-app/main/default/classes/
   controllers/  — @AuraEnabled controllers
   services/     — Business logic + UserResolver
   dao/          — DMO SOQL (interface-backed)
   dto/          — @AuraEnabled data transfer objects
   tests/        — Mock-based tests
force-app/main/default/lwc/               — 11 LWC components (10 per docs + aiInsightsExplorer)
force-app/main/default/applications/      — FluentMetric_AI Lightning App
force-app/main/default/tabs/              — Custom tab
force-app/main/default/flexipages/        — App Page layout
force-app/main/default/messageChannels/   — LMS channel
force-app/main/default/permissionsets/    — FluentMetric_AI_User
force-app/main/default/cachePartitions/   — FluentMetric_AI org partition
force-app/main/default/labels/            — Custom Labels for UI strings
```

## Connected Org

**Dev target:** `cvk-dev` (storm.8e409668951bf2@salesforce.com) — Storm org with Data Cloud + Einstein Audit & Feedback enabled and 1,198+ real GenAI requests to exercise dashboards.

**Pre-ship validation:** Fresh scratch org from `cvk-dev` DevHub.

**Not used:** `agentforce` org (cmassing+dev4af) — does not have Data Cloud / Audit & Feedback enabled.

API version: 62.0 (package pinned here; orgs are on 66.0 — backward compatible).

## Claude Code Assets Used on This Project

### Skills (all under `~/.claude/skills/`)

Invoke with `Skill` tool by exact name. These are authoritative for their domain — follow their reference files before writing code.

| Skill | Phase / Use |
|---|---|
| `sf-apex` | Every Apex class — 150-point production scoring |
| `sf-lwc` | Every LWC — 165-point SLDS 2 + a11y scoring |
| `sf-soql` | Every DMO query — natural-language → SOQL with plan analysis |
| `sf-metadata` | App, Tab, FlexiPage, Permission Set, Message Channel, Cache Partition XML |
| `sf-deploy` | Every `sf project deploy start`, scratch-org provisioning, validation deploys |
| `sf-testing` | Apex test classes, coverage targets, mock patterns |
| `sf-debug` | DMO query failures, governor-limit triage |
| `sf-permissions` | Permission Set audit / "who has access" |
| `sf-datacloud-retrieve` | Fallback to `sf data360 query` if Apex `Database.query` hits DMO limits |
| `sf-data` | Test data, bulk ops |
| `sf-docs` | Fetching official Salesforce help articles cleanly |
| `sf-ai-agentforce-observability` | **v2 only** — Session Tracing / STDM integration |

### MCP Servers

`mcp-adaptor` is already configured in `~/.claude/settings.json`. Use `mcp__mcp-adaptor__doc_search` for Salesforce-internal doc lookups during the build. The `@salesforce/mcp` server from the SF CLI repo is intentionally NOT installed — direct `sf` CLI access via Bash provides the same capabilities.

### External Resources (Evaluated and Skipped)

- **[agentforce-adlc](https://github.com/SalesforceAIResearch/agentforce-adlc)** — targets `.agent` file authoring and agent lifecycle. Not a dashboard-building tool. (The skills `developing-agentforce`, `testing-agentforce`, `observing-agentforce` *are* installed locally as part of this family — same conclusion, skip for v1.)
- **[afv-library](https://github.com/forcedotcom/afv-library)** — Agentforce Validation Library; curated agent skills for app generation. Not relevant to a passive analytics dashboard.
- **[salesforcecli/mcp](https://github.com/salesforcecli/mcp)** — MCP wrapper for SF CLI. Not installed; direct CLI access via Bash covers the same ground.

## Execution Plan

See [/Users/cmassing/.claude/plans/read-all-docs-in-witty-stearns.md](/.claude/plans/read-all-docs-in-witty-stearns.md) for the approved 6-phase plan.

Current phase: **Phase 0 — scaffolding complete, moving to Phase 1 (Apex data layer) using `sf-apex` + `sf-soql` + `sf-datacloud-retrieve` skills.**
