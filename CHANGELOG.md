# Changelog

All notable changes to FluentMetric AI are documented here.

The format is based on [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html).

> Each released version lists **install URLs** for both editions. Install
> via Setup → click the URL while logged into the target org → Install for
> Admins Only. See [Documents/Admin/02-install-lightning.md](Documents/Admin/02-install-lightning.md)
> and [Documents/Admin/03-install-tableau.md](Documents/Admin/03-install-tableau.md)
> for full admin runbooks.

---

## [Unreleased]

---

## [1.1.1] - 2026-06-02

**Install URL:**
- **Lightning Edition (promoted, production-installable):** https://login.salesforce.com/packaging/installPackage.apexp?p0=04tHn000001NtnlIAC
- **Tableau Next Edition:** Deferred to a later release.
- For sandboxes, replace `login` with `test`.

**Promotion status:** Non-beta — installs cleanly into Production, Sandbox,
and Developer Edition orgs. v1.1.1-1 cut with `--code-coverage` against
DevHub `cvk-dev`; package coverage 81% with all 17 previously-failing
fixture tests now passing in the validation scratch org.

**Upgrade notes:** No customer-visible changes from v1.1.0. The rate-card
upload flow, schema, and permission set are byte-for-byte identical. The
test-debt fix is a single new test-only object plus a 12-line fallback in
`AiInsightsTestUtil.deserialize`. Permission Set assignments and Custom
Setting values are preserved through upgrade.

### Fixed

- **17 fixture-dependent tests** that were NPE-ing in package-validation
  scratch orgs (`AiInsightsServiceTest` × 4, `AiInsightsServiceCoverageTest`
  × 11, `AiInsightsTestUtilSmokeTest` × 2). Root cause: the validation org
  has no Data Cloud DMOs provisioned, so `Type.forName('GenAIGatewayRequest__dlm')`
  returned null and the DMO fixture builders produced null SObjects, which
  then NPE'd in `AiInsightsService.collectBusinessKeys` and friends. Fix is
  in [v1_test_debt_path_a](Documents/Developer/v1.1-test-debt.md) Path A
  category — additive, no production-code changes.

### Added

- **`Fm_Test_Dmo_Row__c`** custom object — internal test stand-in carrying
  the camelCase field shape the GenAI Audit DMOs use (`userId__c`,
  `gatewayRequestId__c`, `model__c`, `feature__c`, `timestamp__c`,
  `promptTokens__c`, `completionTokens__c`, `totalTokens__c`, `prompt__c`,
  `promptTemplateDevName__c`, `feedback__c`, `action__c`,
  `generationRequestId__c`, `generationResponseId__c`, `generationId__c`,
  `responseText__c`, `isToxicityDetected__c`, `category__c`, `value__c`,
  `parent__c`). The `FluentMetric_AI_User` permission set deliberately
  omits this object — customers will see it in Object Manager but no
  user-facing surface ever queries or writes it.
- **`AiInsightsTestUtil.deserializeIntoShadow`** fallback — when
  `Type.forName(typeName)` returns null (no DMOs), the helper rewrites
  `attributes.type` to `Fm_Test_Dmo_Row__c` and deserializes into the
  shadow SObject. The service's `r.get('userId__c')` etc. semantics are
  preserved unchanged. On orgs with DMOs (e.g. `cvk-dev`), the live DMO
  type still resolves first and the fallback is never hit.

### Notes

- No production Apex changed. `AiInsightsService`, `AiInsightsDAO`,
  `AiInsightsController`, and the LWC layer are byte-for-byte identical
  to v1.1.0.
- This unblocks the v1.1.0 production-install limitation — admins can now
  install v1.1.1 directly into a Production org via the URL above.

---

## [1.1.0] - 2026-06-01

**Install URL:**
- **Lightning Edition (beta):** https://login.salesforce.com/packaging/installPackage.apexp?p0=04tHn000001NtjYIAS
- **Tableau Next Edition:** Deferred to a later release.
- For sandboxes, replace `login` with `test`.

**Promotion status:** Beta only. A `--code-coverage` build attempt (1.1.0-2)
failed with 17 pre-existing test failures in `AiInsightsServiceTest`,
`AiInsightsServiceCoverageTest`, and `AiInsightsTestUtilSmokeTest` —
NPEs at `AiInsightsService.collectBusinessKeys` and assertion failures in
fixture helpers. The new `RateCardImportServiceTest` (8 tests) and
extended `CostCalculatorServiceTest` (49 tests) all pass against `cvk-dev`.
Test-debt fix tracked for v1.1.1.

**Upgrade notes:** Adds the rate-card upload flow on the Cost panel. When an
org has no Salesforce Digital Wallet (no `TenantEnrichedUsageEvent__dll`),
the "Estimates, not billing" banner now exposes an **Upload latest rate
card** button. Admins upload the Salesforce Flex Credits Rate Card PDF; an
Apex-invoked LLM extracts the 8 multipliers (`standard_action`,
`custom_action`, `standard_voice_action`, `custom_voice_action`,
`starter_prompt`, `basic_prompt`, `standard_prompt`, `advanced_prompt`),
the user reviews a diff, confirms, and the values are written to
`FluentMetric_Cost_Settings__c`. The PDF + parsed JSON + per-field diff are
persisted in a new `RateCardUpload__c` audit object so admins can revert.

### Added

- **`RateCardImportService`** Apex class — `parseUpload`,
  `applyParsedUpload`, `revert`, `listRecent`. The LLM call is encapsulated
  behind an `ILlmAdapter` interface so tests inject a stub via
  `adapterOverride`. Production wiring of `ConnectApi.EinsteinLLM` is
  per-org (the inner `EinsteinLlmAdapter` carries the strict-JSON system
  prompt; the `invokeEinsteinReflective` body throws today and must be
  filled in once the target org has a published Flex prompt template).
- **`RateCardUpload__c`** custom object — AutoNumber Name (`RC-{0000}`),
  fields: `ContentDocumentId__c`, `ParsedJson__c`, `EffectiveDate__c`,
  `AppliedBy__c`, `Status__c` (Draft/Applied/Reverted, restricted),
  `ChangeSummary__c`, `Notes__c`. ReadWrite sharing model.
- **4 new fields on `FluentMetric_Cost_Settings__c`**: `Custom_Action_FC__c`
  (default 20), `Standard_Voice_Action_FC__c` (default 30),
  `Custom_Voice_Action_FC__c` (default 30), `Tier_Starter_FC__c` (default
  2). Brings the schema to parity with the Salesforce public rate card's
  8 production multipliers.
- **`aiInsightsRateCardUpload`** LWC — 3-step modal (file → review diff →
  applied), uses `lightning-file-upload` scoped to the running user,
  fires `rateCardApplied` so `aiInsightsCostAnalysis` reloads tiles.
- **CTAs in `aiInsightsCostAnalysis`** — "Upload latest rate card" button
  in the estimates banner and "Refresh from rate card" inline link below
  the Estimated USD tile. Both gated on `costSource !== 'ACTUAL_WALLET'`.
- **5 custom labels**: `FM_Cost_Upload_Rate_Card_Button`,
  `FM_Cost_Upload_Rate_Card_Helper`, `FM_Cost_Upload_Diff_Header`,
  `FM_Cost_Upload_Confirm`, `FM_Cost_Upload_Applied_Toast`.
- **Permissions** — `FluentMetric_AI_User` extended with `RateCardImportService`
  class access, R/W on the 4 new cost-settings fields and 7 new
  `RateCardUpload__c` fields, and full CRU + viewAllRecords on
  `RateCardUpload__c`. Cost-settings object permissions upgraded to
  Create/Edit so the upsert path succeeds.
- **`CostCalculatorService.resetSettingsCacheForRefresh()`** — public hook
  the import service calls after upsert so the rest of the transaction
  sees the new multipliers.
- **`RateCardImportServiceTest`** — 8 tests covering happy-path parse +
  apply, revert restoring prior values, malformed JSON, missing
  multipliers, blank payloads, unknown revert IDs, `listRecent` ordering,
  and adapter-error friendly surfacing. Uses a `StubAdapter` injected via
  `adapterOverride`.
- **`CostCalculatorServiceTest`** — added `testRateCardRefresh_LegacyFieldsStillDriveCost`
  asserting the 4 new multiplier fields, when populated alongside the
  legacy 4, do NOT alter `costForRequests` / `costForAgentforceActions`
  output. Guards against an accidental wiring change.

### Notes

- The Wallet path is untouched. Customers with `Enable_Wallet_Costs__c = true`
  AND a working `TenantEnrichedUsageEvent__dll` see ACTUAL figures and the
  upload CTA stays hidden.
- Tableau Edition transitively benefits via `AiInsightsService` — no
  changes to `force-app-tableau/`.

---

## [1.0.1] - 2026-05-29

**Install URLs:**
- **Lightning Edition (beta):** https://login.salesforce.com/packaging/installPackage.apexp?p0=04tHn000001NtfLIAS
- **Tableau Next Edition:** Deferred to v1.1.
- For sandboxes, replace `login` with `test`.

**Upgrade notes:** Beta patch. Internal test infrastructure rebuild — no
customer-visible feature changes. v1.0.1 closes the v1.0.0 test-debt gap so
v1.1 can ship as a promoted (non-beta) version. Permission Set
`FluentMetric_AI_User` assignments and Custom Setting values are preserved
through upgrade.

### Changed

- **AiInsightsService coverage 25% → 83%** and **AiInsightsDAO coverage 4%
  → 92%**, both now well above the 75% per-class threshold required for
  non-beta promotion. Achieved by (a) refactoring eight service-level
  `Database.queryWithBinds` call sites into the DAO so they become
  mockable, and (b) a fixture rebuild using `Type.forName +
  System.JSON.deserialize` for DMO SObjects + a real-aggregate trick for
  `AggregateResult` rows.
- **`AiInsightsTestUtil`** — new shared fixture helper class providing
  DMO SObject builders (`makeRequest` / `makeResponse` / `makeGeneration`
  / `makeFeedback` / `makeQuality` / `makeCategory`) and AggregateResult
  helpers (`oneRowAggregate`, `aggregateRow`, `aggregateRows`,
  `totalsAggregate`).
- **`config/project-scratch-def.json`** — corrected feature names so
  scratch-org provisioning works on the `cvk-dev` DevHub
  (`DataCloud` / `EinsteinGenAI` were rejected as not-valid feature
  values; resolved to `EinsteinGPTPlatform`).

### Added

- **`AiInsightsDAOTest`** — new test class covering all 49 public DAO
  methods. Each test asserts the SOQL builder produces syntactically
  valid SOQL by either succeeding or raising only the expected
  `QueryException` (DMOs are not seedable in Apex test context).

### Known gaps (v1.0.1)

- **Install-URL roundtrip on a fresh scratch was not run** because the
  `cvk-dev` DevHub hit its daily scratch-org signup limit during the
  release window. The package created cleanly and shares 100% of its
  metadata with v1.0.0 (which was successfully installed on `cvk-dev`),
  so risk is low — but a roundtrip smoke is owed before v1.1 ships.
  Tracked as a v1.1 prerequisite.
- **Tableau Next edition packaging** remains deferred to v1.1 alongside
  promote-to-non-beta.

---

## [1.0.0] - 2026-05-28

**Install URLs:**
- **Lightning Edition (beta):** https://login.salesforce.com/packaging/installPackage.apexp?p0=04tHn000001NtfGIAS
- **Tableau Next Edition:** Deferred to v1.1.
- For sandboxes, replace `login` with `test`.

**Upgrade notes:** First public release. Permission Set `FluentMetric_AI_User`
required after install. v1.0.0 ships as a **beta** (Salesforce shows an
"installing a beta version" banner) because two Apex classes
(`AiInsightsService`, `AiInsightsDAO`) are below the 75% per-class coverage
threshold required for promotion to non-beta. v1.1 will rebuild the fixtures
and ship as a promoted version. See
[Documents/Developer/v1.1-test-debt.md](Documents/Developer/v1.1-test-debt.md).

### Added

- **Three-persona documentation tree** under [Documents/](Documents/):
  Admin (UI-first install + day-2 ops), Developer (local-dev, coding
  standards, release engineering), Architect (design rationale + ADRs).
- **CHANGELOG.md** + GitHub Releases discipline — each tagged version
  lists both edition install URLs.
- **`make release VERSION=X.Y.Z`** target wraps `sf package version
  create/promote` for both editions, appends a CHANGELOG entry, and
  prints the GitHub Release-creation URL.
- **Adoption tab** as a dedicated 5th tab with entitled-denominator
  adoption rate, top users, and AI heavy users Pareto chip.
- **Cost tab** promoted to a dedicated tab with confidence badges
  (`ACTUAL` / `HIGH` / `ESTIMATED` / `FALLBACK` / `NOT_COSTED`).
- **Wallet-first cost engine** — `CostCalculatorService.costForWindow()`
  prefers Digital Wallet actuals when both `Enable_Wallet_Costs__c` is on
  and `AiWalletDAO.isWalletAvailable()` returns true. See
  [ADR 002](Documents/Architect/decisions/002-wallet-first-cost.md).
- **Explorer preset chips** — one-click curated pivots (Top prompts,
  Tokens by user, Tokens by day, Acceptance by prompt) absorbing the
  retired Prompt Analytics + Token Consumption screens.

### Changed

- **5-tab IA**: Overview / Adoption / Explorer / Safety / Cost. See
  [ADR 004](Documents/Architect/decisions/004-five-tab-ia.md).
- **Date pill** shows resolved start/end dates alongside the relative
  label (e.g., *"Last 30 days · Apr 28 – May 28"*).
- **Compact sticky toolbar** at the top of every tab.
- **Detail table in Explorer is collapsed by default** — chart conveys
  ranking; users open the table only for exact numbers.

### Removed

- **Activity tab** (`aiInsightsActivity` LWC) — folded into Overview daily
  trend + Adoption top users.
- **Prompt Analytics tab** (`aiInsightsPromptAnalytics` LWC) — replaced by
  Explorer's "Top prompts" / "Acceptance by prompt" preset chips.
- **Token Consumption tab** (`aiInsightsTokenConsumption` LWC) — replaced
  by Explorer's "Tokens by user" / "Tokens by day" preset chips.
- `Documents/DEPLOYMENT.md` — split into
  [Documents/Developer/release.md](Documents/Developer/release.md)
  (release engineering) and [Documents/Admin/02-install-lightning.md](Documents/Admin/02-install-lightning.md)
  (admin install).

### Migration

- Customers on previous versions: bookmarked URLs into removed tabs return
  a benign SPA 404 — pivot to Adoption / Explorer instead.
- Permission Set assignments and Custom Setting values persist through
  upgrade. See [Documents/Admin/07-upgrade.md](Documents/Admin/07-upgrade.md).

### Known gaps (v1.0.0)

- **AiInsightsService (25%) and AiInsightsDAO (4%) ship below the 75%
  per-class Apex coverage threshold.** v1.0.0 is therefore released as a
  beta version (`sf package version create` without `--code-coverage`);
  the install URL works, but Salesforce shows an "installing a beta
  version" banner during install. v1.1 will rebuild fixtures using the
  `Type.forName + System.JSON.deserialize` DMO workaround and ship as a
  promoted (non-beta) release. Full context, rebuild plan, and timeline:
  [Documents/Developer/v1.1-test-debt.md](Documents/Developer/v1.1-test-debt.md).

---

<!--
  When cutting a release:

  1. Rename `[Unreleased]` heading above to `[X.Y.Z] - YYYY-MM-DD`.
  2. Insert a fresh `## [Unreleased]` block at the top.
  3. Below the rename, insert this template populated with both edition install URLs:

  ## [X.Y.Z] - YYYY-MM-DD

  **Install URLs:**
  - **Lightning Edition:** https://login.salesforce.com/packaging/installPackage.apexp?p0=04t...
  - **Tableau Next Edition:** https://login.salesforce.com/packaging/installPackage.apexp?p0=04t...
  - For sandboxes, replace `login` with `test`.

  **Upgrade notes:** <one-line callout — e.g., "New Custom Setting field 'Enable_Wallet_Costs__c' added; existing values preserved.">

  ### Added / Changed / Fixed / Removed / Security
  ...
-->
