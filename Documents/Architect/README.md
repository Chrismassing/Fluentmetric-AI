# Architect Guide — FluentMetric AI

> **Audience:** Architects evaluating fit, reviewing design, or coordinating
> across editions. Want to extend code? [../Developer/README.md](../Developer/README.md).
> Installing the package? [../Admin/README.md](../Admin/README.md).

## Reading order

1. **[architecture.md](architecture.md)** — 4-layer Apex stack, LMS channels,
   Platform Cache, Wallet-first cost engine. The "how the pieces fit"
   document.
2. **[editions.md](editions.md)** — License matrix and edition selection
   guide. Lightning vs Tableau Next, when each is the right fit.
3. **[lightning-edition.md](lightning-edition.md)** — Design rationale for
   the Lightning edition (entitlement CMT, adoption denominator, Wallet
   override).
4. **[tableau-edition.md](tableau-edition.md)** — Design rationale for the
   Tableau Next edition (delegation pattern, agent data path, semantic-
   model authoring cycle).
5. **[data-model.md](data-model.md)** — Original DMO design intent.
   ⚠️ [../Developer/live-schema.md](../Developer/live-schema.md) is the
   authoritative live schema; this doc is reference for design history.
6. **[decisions/](decisions/)** — Short ADRs for major design choices.

## Architecture Decision Records (ADRs)

We capture load-bearing design decisions as short ADRs in
[decisions/](decisions/). Each ADR is one or two pages — context, decision,
consequences. Don't litigate the same decision twice; if the trade-offs
change, write a new ADR that supersedes the old one.

Current ADRs:

- **[001 — Two editions, one repo](decisions/001-two-editions.md)** — Why we
  ship Lightning + Tableau Next as separate 2GP packages from the same
  monorepo, with the Tableau edition delegating to Lightning's services.
- **[002 — Wallet-first cost engine](decisions/002-wallet-first-cost.md)** —
  Why `CostCalculatorService` prefers Digital Wallet actuals over the
  tier-rate estimate, and how the confidence-badge model was chosen.
- **[003 — No-namespace 2GP packages](decisions/003-no-namespace-2gp.md)** —
  Why both editions ship as no-namespace Unlocked Packages instead of
  managed packages or namespaced 2GP.
- **[004 — Five-tab IA](decisions/004-five-tab-ia.md)** — The 2026-Q2
  navigation refactor from 4 tabs to 5: Overview / Adoption / Explorer /
  Safety / Cost. Why Activity / Prompt Analytics / Token Consumption were
  retired and what they were replaced by.

## When to write a new ADR

Write one when you're about to make a decision that:

- Affects more than one edition or layer.
- Shapes external surface area (admin install, CHANGELOG, customer-visible
  behavior).
- Will be contested again in 3 months if you don't write it down.

Don't write ADRs for:

- Implementation details visible in code (variable names, helper
  factoring).
- Reversible-in-an-afternoon choices.

## Cross-edition coordination

Most design changes touch only one edition. The exceptions where you
*must* think across both:

| Change | Both editions affected? |
|---|---|
| New public method or DTO field on `AiInsightsService` | ✅ Tableau-edition invocable actions delegate to it |
| New DMO field used in an aggregate | ✅ Both editions read DMOs |
| New Permission Set permission | ❓ Usually one edition; double-check |
| New Custom Setting / Custom Metadata | ❓ One edition unless explicitly cross-cutting |
| Tableau Next semantic-model schema | ❌ Tableau edition only |
| Agent skill (`.agent` file) | ❌ Tableau edition only |

[../Developer/contributing.md](../Developer/contributing.md) has the
mechanical PR checklist for cross-edition changes.

## Data model authority

[../Developer/live-schema.md](../Developer/live-schema.md) is **authoritative**
for DMO field names. [data-model.md](data-model.md) captures original
design intent and query patterns but uses outdated field-name conventions.
When the two disagree, trust the live schema.
