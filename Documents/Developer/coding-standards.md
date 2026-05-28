# Coding Standards

> Applies to anything that lands in `force-app/` or `force-app-tableau/`.

## Apex

- **`with sharing` on every class.** No exceptions. If you need `without
  sharing`, justify it in the PR description.
- **All DMO queries via `Database.query()`** — `__dlm` objects don't compile
  in static SOQL. Build query strings carefully and bind via `:` for date
  literals.
- **All controller reads are `@AuraEnabled(cacheable=true)`.** Mutating
  methods get plain `@AuraEnabled`. Never expose a `cacheable=true` method
  that performs a DML or callout.
- **DAO interface + mock pattern** — every DAO has a paired interface
  (`IAiInsightsDAO`, `IAiWalletDAO`) and a mock used in tests. Tests never
  hit real DMOs (the test runtime can't see them).

## DMO SOQL rules

- Field names are **camelCase** with `__c` suffix; object names are
  **PascalCase** with `__dlm` suffix. Wallet DLOs are `__dll` with
  lowercase + `__c` field names — different convention.
- Use `timestamp__c` for date filtering, **NOT** `CreatedDate__c`. (The
  legacy [data-model.md](../Architect/data-model.md) shows the wrong
  convention; [live-schema.md](live-schema.md) is authoritative.)
- **Do NOT `ORDER BY COUNT(Id)`** — sort aggregates in Apex code instead.
- **Do NOT use parent-child SOQL subqueries** — join in Apex via business
  keys.
- **Always date-filter** to avoid scanning the full DMO. The dataset is
  large.
- Prefer `LIKE` over `=` for text comparisons (per Salesforce DMO docs).

## LWC

- **SLDS only**, no external CSS frameworks. Reference SLDS design tokens
  (`--slds-g-...`) instead of hard-coded colors. Hard-coded fallback values
  in `var(..., #fff)` are fine.
- **Every component handles loading / empty / error** as separate render
  branches. The `c-ai-insights-empty-state` component is the canonical
  empty-state UI.
- **Cross-component comms via the LMS channel** `AiInsightsDateRange__c`
  (date) and `AiInsightsFilters__c` (filters). One publisher per channel,
  N subscribers.
- **Imports** — local `numberFormat.js` for shared formatting helpers, NOT
  cross-component imports. LWC component imports resolve to default
  exports, not sibling modules.
- **Custom Labels for all user-facing strings.** No hard-coded English
  text in HTML or JS — use `@salesforce/label/c.FM_*`. The labels file is
  [force-app/main/default/labels/CustomLabels.labels-meta.xml](../../force-app/main/default/labels/CustomLabels.labels-meta.xml).

## API version

- **`62.0`** for all metadata files (the package version pinned in
  `sfdx-project.json`'s `sourceApiVersion`).
- Org runtimes are typically 66.0 — backward-compatible.

## Testing

- **Target 80%+ Apex coverage.** Tests must run in a vanilla scratch org
  (no DMO data, no Wallet rows). Use the DAO mocks for everything DMO-
  related.
- **`@TestSetup`** for shared fixtures. Build entities through
  `AiInsightsTestFactory` rather than ad-hoc SObject construction in each
  test.
- **`Test.startTest()` / `Test.stopTest()`** wrap any code path that hits a
  governor limit you want to assert isolation around.
- **No real callouts** — wrap any HTTP via the standard mock callout
  pattern.

## Skills (for Claude Code authoring)

When generating new code, defer to these skills (under `~/.claude/skills/`):

| Domain | Skill |
|---|---|
| New Apex class | `sf-apex` (150-pt scoring) |
| New LWC | `sf-lwc` (165-pt SLDS 2 + a11y scoring) |
| New DMO query | `sf-soql` (natural-language → SOQL with plan analysis) |
| Metadata XML (App, Tab, FlexiPage, Permset, Channel, Cache) | `sf-metadata` |
| Deploy / scratch org / validation | `sf-deploy` |
| Apex tests | `sf-testing` |
| Permissions audit | `sf-permissions` |
| Tableau-edition `.agent` authoring | `developing-agentforce` |
| Tableau-edition Agent Script | `sf-ai-agentscript` |

## Lint / format

The repo doesn't ship Prettier or ESLint configs in v1. Match surrounding
style. Tabs vs spaces follow whatever's in the file you're editing.

## What we don't do

- **No external CSS frameworks** (no Tailwind, no Bootstrap).
- **No npm dependencies in LWC bundles** beyond the SF-provided ones.
- **No `with sharing` workarounds** — see Apex section.
- **No hard-coded English text** — Custom Labels only.
- **No tests against real DMOs** — they don't exist in `Test` context.
