# BUILD-LOG.md — Running Record of Build Decisions & Findings

Chronological log of what was built, what was discovered, and what changed from the original design docs. Written as we go so later sessions can pick up without re-deriving context.

## 2026-04-29 — Phase 0: Scaffolding + Preflight

- Read all 7 design docs in [Documents/](./).
- Evaluated external references:
  - [agentforce-adlc](https://github.com/SalesforceAIResearch/agentforce-adlc) and [afv-library](https://github.com/forcedotcom/afv-library) — target agent authoring, not dashboard analytics. **Skipped.**
  - [salesforcecli/mcp](https://github.com/salesforcecli/mcp) — direct `sf` CLI via Bash covers the same ground. **Not installed.**
- Discovered 39 `sf-*` skills already installed under `~/.claude/skills/`. **Wired relevant ones into [CLAUDE.md](../CLAUDE.md).**
- **Org switch:** originally targeted `agentforce` org — preflight showed no Data Cloud, no DMOs. Switched to `cvk-dev` (Storm org with full GenAI Audit stack and 1,198 real request records).
- Scaffolded SFDX project: [sfdx-project.json](../sfdx-project.json), [.forceignore](../.forceignore), [config/project-scratch-def.json](../config/project-scratch-def.json), `force-app/main/default/` directory skeleton.

## 2026-04-29 — Phase 1a-d: Apex Data Layer

### Schema deltas vs. docs (documented in [LIVE-SCHEMA.md](./LIVE-SCHEMA.md))

The docs describe PascalCase fields; the live platform uses **camelCase**. Major shifts:

| Area | Doc says | Live |
|---|---|---|
| User ID | `UserId__c` | `userId__c` |
| Date | `CreatedDate__c` | `timestamp__c` |
| Prompt template | join via `RequestTags__dlm` | `promptTemplateDevName__c` directly on Request |
| Tokens | Response row | **Request row has aggregate totals** |
| Tags DMO | `GenAIGatewayRequestTags__dlm` (plural) | `GenAIGatewayRequestTag__dlm` (singular) |
| Toxic flag | Boolean | String `"true"`/`"false"` |
| Category score | Number(3,2) | String-encoded decimal |

### Build order

1. **DTOs (9 classes)** — [force-app/main/default/classes/dto/](../force-app/main/default/classes/dto/). All LSP-validated.
2. **DAO layer** — `IAiInsightsDAO` interface + live `AiInsightsDAO` + `AiInsightsDAOMock` for tests. Deployed to `cvk-dev` (12 components). Smoke-tested with 1-day window:
   - 158 requests fetched in ~1 sec
   - Business-key joins (Request → Response → Generation → ContentQuality) all worked
   - Feedback rows = 0 for the sample (expected — feedback is rare on internal agent calls)
3. **UserResolverService** — Resolved live data end-to-end:
   - `005Hn00000JWiIUIA1` → **Christoffer Mässing**
   - `005Hn00000JWnX4IAL` → **EinsteinServiceAgent User**
   - `"Atlas__GroundednessValidationPrompt"` → **Atlas · Groundedness Validation Prompt**
   - Second call on cached values: 17 ms (Platform Cache partition not yet deployed — falling back gracefully to direct SOQL)

### Runtime gotchas discovered

- **`LIMIT 50000` on a 90-day window blew the heap.** The busy `cvk-dev` org has >50k requests in 90 days. DAO queries are bounded but service layer will cap effective date ranges in heavy orgs — or downshift to batchable.
- **`ORDER BY COUNT(Id)` is rejected** on DMOs — aggregates sorted in Apex instead.
- **Prompt template names come back quote-wrapped** (`"Atlas__Foo"`) in the DMO — `UserResolverService.stripQuotes()` handles this before humanization or `GenAiPromptTemplate` lookup.
- **`userId__c` sentinel `"NOT_SET"`** for system calls — treated as its own "System Call" bucket, never resolved.

### Deployed to cvk-dev

- 9 DTOs, 1 interface, 1 live DAO, 1 mock DAO, 1 UserResolverService — 13 Apex classes, 0 errors

## Next (delegated in parallel)

- **Phase 1e** → `ps-technical-architect`: Service, Controller, tests, cache partition, permission set
- **Phase 2** → `fde-experience-specialist`: LMS channel, 5 LWCs, App, Tab, FlexiPage

Main thread will do integrated deploy after both agents complete.

## 2026-04-29 — Phase 1e + Phase 2 integrated deploy

### Delegated work delivered

- `ps-technical-architect` wrote `AiInsightsService` (1,287 lines, 7 core methods + Explorer pivot + prereqs), `AiInsightsController` (thin wrapper, 9 `@AuraEnabled` methods), `AiInsightsServiceTest` + `AiInsightsControllerTest` (36 tests via `StubService extends AiInsightsService`).
- `fde-experience-specialist` wrote 5 LWCs (`aiInsightsApp`, `aiInsightsDateFilter`, `aiInsightsEmptyState`, `aiInsightsOverview`, `aiInsightsUserAdoption`) scoring 165/165 on SLDS 2 + a11y rubric, plus the LMS channel, App, Tab, FlexiPage, Permission Set.

### Issues found at deploy and fixed

1. Service methods needed `virtual` modifier — controller test stub overrides all 8 methods; fixed in main thread.
2. Tab `<icon>` isn't a schema element — replaced with `<motif>Custom17: Flask</motif>`.
3. Cache partition XML rejected `<capacity>0</capacity>` — **temporarily removed the partition**. `UserResolverService` degrades gracefully; proper cache deployment deferred to Phase 4.
4. Test helper `makeRequest` parameters were `Double`, call sites passed `Decimal` literals — changed signature to `Decimal`.
5. `aiInsightsUserAdoption.html` had `resize-column-disabled={false}` — LWC templates disallow boolean literals; removed the attribute (default is already not-disabled).

### Deploy result

- 27 components deployed to `cvk-dev`, 0 errors.
- 36 Apex tests pass, 100% pass rate.
- Controller coverage 90%; service + DAO + resolver coverage low (stub path) — full coverage is Phase 4 work.

### End-to-end validation (live DMO data)

Running `AiInsightsController.getOverview` + `getUsageByUser` against 1-day window in `cvk-dev`:

- **153 requests · 2 users · 9 prompt templates · 302K input tokens · 9,855 output tokens · 1 safety flag**
- **Users resolved to names:** `005Hn00000JWnX4IAL` → "EinsteinServiceAgent User" (127 requests), `005Hn00000JWiIUIA1` → "Christoffer Mässing" (26 requests)
- **Prompts humanized:** `"Atlas__GroundednessValidationPrompt"` → "Atlas · Groundedness Validation Prompt", `"einstein_gpt__aiAssistTopicCreateDraft"` → "einstein gpt · ai Assist Topic Create Draft"

**Mission statement (human-readable DMO data) delivered end-to-end through the full stack.**

## 2026-04-29 — Scale fix: DMO server-side aggregates

### Bug found in browser

User opened the app in `cvk-dev` for a 7-day range. Both Overview and User Adoption showed: *"Inline query has too many rows for direct assignment, use FOR loop"*. Root cause: `AiInsightsService.getOverview` and `getUsageByUser` were pulling all raw request rows into heap (1,102 rows for 7 days, 30k+ for 90 days), hitting the 50k SOQL row limit that the DAO already guarded with `LIMIT 50000`.

### Fix

DMOs support `COUNT`, `SUM`, `MIN`, `MAX` and multi-column `GROUP BY` server-side (they don't support `ORDER BY` on aggregates — sort in Apex). Pushed aggregation into SOQL:

- New DAO methods: `getRequestAggregatesByUser`, `getRequestAggregatesByPrompt`, `getRequestAggregatesByUserAndPrompt`, `getRequestTotals`, `countDistinctUsers`, `countDistinctPromptTemplates`.
- New service helper: `countToxicFlagsInRange` — queries `GenAIContentQuality__dlm` directly by its own `timestamp__c` and `isToxicityDetected__c = 'true'`, avoiding the expensive Request→Response→Generation→Quality walk just to count flags.
- `getOverview` now runs 5 scale-independent queries (totals, distinct users, distinct prompts, feedback aggregate, toxic count).
- `getUsageByUser` runs 3 queries: user-level aggregate + user-and-prompt aggregate (for "top 3 prompts per user") + feedback. Sort still happens in Apex because DMOs forbid `ORDER BY COUNT(Id)`.
- Feedback and Overview queries are wrapped in try/catch so a huge-feedback-volume org still gets a populated overview (with 0 acceptance rate) instead of an outright error.

### Validated live

| Scenario | Result |
|---|---|
| 7-day Overview | 4.0 sec (5 queries; 1,102 requests / 3 users / 23 prompts / 1 toxic flag) |
| 7-day User Adoption | 298 ms — 3 user rows: `EinsteinServiceAgent User` (994 req), `Christoffer Mässing` (99 req), `System Call` (9 req, shown as the `NOT_SET` bucket) |
| 30-day Overview | 357 ms (1,198 requests) |

36 existing Apex tests still pass (stub-based tests exercise controller paths, not the refactored aggregate paths — those need new mock seeds in Phase 4).

### Next: Phase 3 (remaining dashboards + Explorer)

All backing Apex methods (`getUsageByPrompt`, `getPromptOutputs`, `getTokenConsumption`, `getSafetyOverview`, `runExplorerQuery`) already exist and are callable — remaining LWC work is UI only. **Note:** `getUsageByPrompt`, `getTokenConsumption`, `getSafetyOverview`, and `runExplorer` still pull raw rows internally. They will need the same aggregate-refactor treatment before Phase 3's LWCs can safely call them with wide date ranges — plan a similar refactor pass at the start of Phase 3.

## 2026-04-29 — Plan additions (user request)

Two additions confirmed with the user and reflected in the plan file:

1. **Column tooltips across all dashboards** — every header in every datatable/chart gets a `lightning-helptext` tooltip explaining what the metric measures and how it's calculated. Centralized in `force-app/main/default/lwc/aiInsightsTooltips/tooltips.js` so terminology stays consistent. Folded into Phase 3: new LWCs get them from day one, Phase 2 LWCs retrofitted at the start of Phase 3.
2. **Flex Credit + USD cost analytics** → **new Phase 3.5 — Cost Analytics** (between Phase 3 and Phase 4). Scope: custom-metadata rate card (`FluentMetric_Rate_Card__mdt`), hierarchy custom setting for per-org USD/credit rate + discount, `CostCalculatorService`, two new LWCs (`aiInsightsCostBreakdown`, `aiInsightsCostSettings`), cost fields added to existing DTOs, retrofitted cost column on User Adoption + Prompt Analytics tables. Will use the `sf-flex-estimator` skill's public rate-card reference data as the seed.

Placement rationale: tokens data from Phase 3's Token Consumption must exist first; rate card is its own data model that shouldn't get bundled into polish; must ship before packaging so installs land with cost analytics included.

## 2026-04-29 — Phase 3 complete

### Phase 3a — Scale refactor of remaining service methods

Applied the same aggregate-DAO pattern to `getUsageByPrompt`, `getTokenConsumption`, `getSafetyOverview`, and `runExplorer`. New DAO methods added: `getRequestAggregatesByModel`, `getRequestAggregatesByFeature`, `getRequestAggregatesByUserAndModel`, `getRequestAggregatesByUserAndFeature`, `countGenerationsByDateRange`, `countToxicFlagsByDateRange`.

**Live-data validation on `cvk-dev` (7-day window):**

| Endpoint | Latency | Result |
|---|---|---|
| `getUsageByPrompt` | 5.8 s | 23 prompts, top: topic selector prompt (188 invocations, 657K tokens) |
| `getTokenConsumption` groupBy=prompt | **69 ms** | 11 top + Others bucket |
| `getTokenConsumption` groupBy=user | **136 ms** | EinsteinServiceAgent 2.37M tokens, Christoffer Mässing 1.2M, System Call 7K |
| `getSafetyOverview` | 3.6 s | 1,102 generations, 1 toxic (0.09%), category breakdown empty (known v1 limitation — string-encoded `value__c`) |
| `runExplorerQuery` User/RequestCount | **59 ms** | 3-row pivot |
| `runExplorerQuery` Model/TotalTokens | **106 ms** | 5-row pivot: gpt-4.1 2.78M tokens, gpt-5 492K, gpt-4o 272K, EinsteinHyperClassifier 35K, texteval_12b 0 |

36/36 Apex tests still pass.

### Phase 3b — LWC suite + tooltips

Delivered:
- `aiInsightsTooltips/tooltips.js` — central constant with tooltip text for every column/KPI across all dashboards. Imported by every LWC so terminology stays consistent and future translation work has one place to update.
- **5 new LWCs**: `aiInsightsPromptAnalytics` (sortable table, row click fires `promptselected`), `aiInsightsPromptOutputViewer` (expandable accordion cards), `aiInsightsTokenConsumption` (SLDS div bar chart + table, groupBy selector), `aiInsightsSafety` (summary card + category breakdown with empty-state fallback + recent flagged outputs), `aiInsightsExplorer` (**dynamic pivot** — group-by × metric × filter pills × CSV export, calls `runExplorerQuery` imperatively, the centerpiece of the "highly dynamic" mission).
- **Phase 2 retrofit**: `aiInsightsOverview` KPI cards and `aiInsightsUserAdoption` datatable columns now carry `lightning-helptext` tooltips sourced from the same central module.
- `aiInsightsApp` updated to host all 7 children in the documented order and bridge the `promptselected` event from PromptAnalytics → PromptOutputViewer.

Deploy result: 11 LWC components + app update = clean deploy on `cvk-dev`, 0 errors.

**Two LWC template fixes applied during integrated deploy:**
- `aiInsightsSafety.html` used `lwc:if={x} lwc:else` on the same `<template>` element (LWC forbids). Replaced with a dedicated inverted-state getter (`hasNoCategoryData`, `hasNoFlaggedOutputs`) driving a plain `lwc:if` on the empty-state branch.

### Open items rolled into Phase 4 or Phase 3.5

- **Feedback correlation per prompt / per model** — v1 ships with `acceptanceRate` = 0 on Prompt Analytics and Explorer because the Feedback DMO doesn't carry `promptTemplateDevName__c`. Phase 4 revisit: correlate via the Generation→Request→Prompt chain on narrow scopes, or request a schema enhancement.
- **Safety category score breakdown** — `GenAIContentCategory__dlm.value__c` is string-encoded; `SUM`/`AVG` doesn't work. Phase 4 revisit: pull raw rows for the date range (volume is tiny — only a % of generations get categorized), parse in Apex, cache on the service.
- **Platform Cache partition** — still not deployed; resolver degrades gracefully. Phase 4 revisit.

### Next

Phase 3c: user refreshes the FluentMetric AI tab and confirms all 7 dashboards render on live data.

## 2026-04-29 — UX refactor: tabs + expand modal + defensive dates

### Bugs / UX issues reported by user after first browser test

1. Explorer surfaced `Unable to run Explorer query: startDate and endDate are required` when interacting before the LMS date publish arrived — LMS race condition.
2. Prompt input/output text in Output Viewer was truncated with no way to see the full content.
3. Vertical stacking of 7 dashboards made scrolling painful; needed tabs.

### Changes applied

- **Tab layout** — `aiInsightsApp.html` rewritten to use `lightning-tabset` with 6 tabs: Overview, Users, Prompts, Tokens, Safety, Explorer. Date Filter stays above the tabset so it applies to every tab. All tabs mount eagerly (no lazy-loading) so every child's LMS subscribe fires before the initial date publish. Each tab gets an icon (`utility:dashboard`, `utility:user`, `utility:prompt_builder`, `utility:number_input`, `utility:shield`, `utility:search`) and a tooltipped help text. Prompts tab adds a small helper line: "Click a row below to see the actual inputs and outputs." The `promptselected` event bridge from PromptAnalytics → PromptOutputViewer is preserved, now internal to the Prompts tab.
- **Expand modal** — new reusable `aiInsightsTextModal` LWC exposes `@api open(title, content, metadata)`. Renders in an SLDS modal with copy-to-clipboard button, "Open in new window" (blob URL + minimally-styled HTML), Escape-to-close, backdrop click to dismiss, role="dialog"/aria-modal/autofocus for a11y. `utility:expand_alt` icons next to each Input Prompt / Generated Output label open the modal with the untruncated text — in both `aiInsightsPromptOutputViewer` and `aiInsightsSafety`'s flagged outputs section. The modal also builds a standalone HTML page for the new-tab flow using a Blob URL (no URL length limits, auto-revoked after load).
- **Defensive date defaults** — every date-sensitive LWC seeds `startDate` / `endDate` to a default 30-day window at class declaration (`new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString()`). Each `connectedCallback` calls its load method after subscribing so tab-switchers see data even if the LMS never re-fires. If the Date Filter later publishes a different range, `handleDateRange` overwrites and re-runs. Applied across: Overview, UserAdoption, PromptAnalytics, TokenConsumption, Safety, Explorer (PromptOutputViewer doesn't need it — it only loads on `promptselected`).

### Deploy result

12 components deployed to `cvk-dev`, 0 errors. 36 Apex tests still pass.

### Open items

- Preflight component still not built (Phase 4)
- Platform Cache partition still not deployed (Phase 4)
- Safety category breakdown still uses v1 "empty map" fallback (Phase 4 will parse string-encoded scores)
