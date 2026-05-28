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
