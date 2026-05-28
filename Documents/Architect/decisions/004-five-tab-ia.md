# ADR 004 — Five-tab information architecture

**Status:** Accepted
**Date:** 2026-05-22

## Context

The Lightning edition shipped originally with **four tabs**: Overview,
Activity, Safety, Explorer. Three issues surfaced after design-partner use:

1. **Adoption analysis was buried.** "Are we getting value from our
   Einstein license spend?" was the most-asked leadership question, but
   the answer required cross-referencing Overview + Activity manually.
2. **Activity tab duplicated the Overview daily volume chart** plus a
   per-user table that Explorer could already produce.
3. **Cost was not a tab at all** — it was rolled into Activity as a
   "tokens" panel, which under-served the (separate) audience that wants
   to monitor FC spend.
4. **Prompt Analytics and Token Consumption were standalone screens** that
   Explorer's preset-chip pattern made redundant.

## Decision

Refactor to **five tabs**:

1. **Overview** — KPI strip, top contributors, daily volume trend.
2. **Adoption** *(new)* — Adoption rate (entitled-denominator), top users,
   AI heavy users Pareto chip, retention indicators.
3. **Explorer** — Free-form pivot tool with **preset chips** that absorb
   the retired Prompt Analytics + Token Consumption surface. Detail table
   collapsed by default.
4. **Safety** — Toxicity / hate / violence / etc. flags + 8 content-safety
   category scores.
5. **Cost** *(promoted to a tab)* — FC consumption + USD estimate, with
   confidence badges per [002-wallet-first-cost.md](002-wallet-first-cost.md).

Compact sticky toolbar. Date pill shows resolved start/end dates rather
than just the relative range label. Preset chips in Explorer for one-click
common pivots.

## Rationale

### Why a dedicated Adoption tab

"Adoption" is the question with the highest stakeholder pull. Burying it
forces every stakeholder conversation to start with "let me build a custom
view." A dedicated tab with the **right denominator** (entitled users via
[Custom Metadata](../../Admin/05-configure.md#2-adoption-denominator-entitled-user-count))
front-loads the answer.

### Why Explorer absorbs Prompt Analytics + Token Consumption

The preset-chip pattern (one click → curated pivot) is strictly more
flexible than two fixed screens that show specific (Group by, Metric)
combos. Users who only want the "old" Prompt Analytics view click "Top
prompts"; users who want a variant click "Acceptance by prompt"; users
who want something neither screen offered build it via Group by + Metric.

Three screens collapse into one tab with five preset chips and ad-hoc
build.

### Why Cost gets its own tab

The audience for cost monitoring (Finance, FinOps, the CIO) is different
from the audience for adoption analysis (Engineering managers, AI product
owners). Separating them lets each audience pin the tab that matters and
ignore the rest.

### Why the date pill shows resolved dates

The original "Last 30 days" label hid the actual start/end. After clicking
through dashboards, users would lose track of what window they were in.
Showing **"Last 30 days · Apr 28 – May 28"** at all times makes the
context explicit and unambiguous.

## Consequences

### Positive

- Each tab has one job and one audience. Faster mental model for new users.
- Explorer's preset chips reduce time-to-first-insight from ~30 seconds
  (find the right tab) to ~2 seconds (click a chip).
- Cost tab's confidence badges (combined with this IA) make the FC vs
  USD trust story coherent in a single screen.

### Negative

- **Three retired components.** `aiInsightsActivity`, `aiInsightsPromptAnalytics`,
  `aiInsightsTokenConsumption` are no longer in the package. Customers who
  bookmarked deep links into those tabs will get 404s on upgrade. Acceptable
  — these are dashboards, not data; the same data is on other tabs.
- **Adoption tab requires entitlement-denominator config.** If admins skip
  [05-configure.md §2](../../Admin/05-configure.md#2-adoption-denominator-entitled-user-count),
  the tab falls back to "all active users" and shows
  `entitledFallback=true` in the funnel tooltip. Clear signal, but a step
  to miss.
- **Cost tab requires opt-in.** Admins must enable the cost engine (see
  [05-configure.md §1a](../../Admin/05-configure.md#1a-enable-cost-analysis))
  before the tab renders meaningful numbers.

## Migration

Customers upgrading from the 4-tab version will see the new IA on their
next page reload. Bookmarked URLs to retired tabs return a benign 404 from
the SPA router. Permset assignments and Custom Setting values carry forward
without changes — the IA refactor was UI-only.

## Verification

Deployed to `cvk-dev` 2026-05-22. 210/210 metadata components, 0 errors,
job `0AfHn00000UQH5lKAH`. End-user smoke test: pin app, set 7-day window,
walk all five tabs, click two preset chips, drill into one entity. ~90
seconds end-to-end. Acceptance test: 5 design-partner admins clicked
through the new IA and named all five tabs correctly without prompting.
