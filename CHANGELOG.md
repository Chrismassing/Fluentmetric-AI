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
