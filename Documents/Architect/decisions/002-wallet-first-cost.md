# ADR 002 — Wallet-first cost engine

**Status:** Accepted
**Date:** 2026-05-15

## Context

The Cost tab needs to answer "how much did Einstein GenAI cost us last
week?" Two data sources are available, and they have different precision /
availability profiles:

1. **Tier-rate estimate** — multiply token counts on
   `GenAIGatewayRequest__dlm` and `GenAIGatewayResponse__dlm` by a
   configurable Flex Credit rate (Custom Setting + per-model rate cards).
   Always available; rough.
2. **Digital Wallet actuals** — `TenantEnrichedUsageEvent__dll` carries
   actual FC consumption per request, sourced from the org's Consumption
   Tagging app. Precise; only present in orgs that license Wallet.

Customers who *do* have Wallet expect the Cost tab to show actual numbers.
Customers who *don't* still need a useful answer.

Two design questions:

1. **Which source wins when both are available?**
2. **How do we tell users which source they're looking at?**

## Decision

**Wallet-first, with explicit confidence badges.** `CostCalculatorService.costForWindow()`
checks two conditions:

- `Enable_Wallet_Costs__c = true` on the Custom Setting (admin opt-in).
- `AiWalletDAO.isWalletAvailable()` returns true (Wallet present in this org
  and queryable).

Both true ⇒ return Wallet actuals tagged `confidence=ACTUAL` /
`source=ACTUAL_WALLET`.

Either false ⇒ fall back to the tier-rate estimate, tagged with
`confidence=HIGH` (known model) / `ESTIMATED` (fallback model) / `FALLBACK`
(Wallet was attempted but failed) / `NOT_COSTED` (couldn't compute).

Confidence and source are surfaced as **visible badges in the UI** so users
always know the basis for the number they're looking at.

## Rationale

### Why Wallet-first instead of tier-first

Wallet's actuals reflect contract pricing and any in-flight FC promotions
the customer has. Tier-rate is at best an approximation we maintain in
Custom Metadata. **When Wallet is available, it's strictly more accurate.**
Defaulting to tier-rate even when Wallet is present would silently
under-trust the better source.

### Why opt-in via Custom Setting

We could enable Wallet automatically when `AiWalletDAO.isWalletAvailable()`
returns true. We chose admin opt-in because:

- Admins should know which data source is feeding their cost number.
- Wallet may be present-but-not-fully-populated in early adopter orgs;
  admins can keep tier-rate while Wallet's data backfills.
- Reversing to tier-rate is one toggle, no metadata change.

### Why confidence badges instead of a "data quality" sidebar

The number itself is the headline. A separate sidebar would be ignored.
Inline badges force the user to see the basis at the same moment they read
the number. **Trust signals next to numbers > trust signals on a different
screen.**

## Consequences

### Positive

- Wallet-licensed customers see precise numbers; tier-rate customers get a
  rough but documented estimate.
- The DAO layer (`AiWalletDAO` + `IAiWalletDAO` + `AiWalletDAOMock`) is
  defended at every method with try/catch + a transaction-scoped
  availability cache, so non-Wallet orgs never throw.
- Confidence badge UX double-serves a debugging affordance — when something
  looks wrong, the badge tells you whether to investigate the rate card or
  the Wallet feed.

### Negative

- **More moving parts.** Two data paths to maintain, two test suites.
  Mitigated by the DAO-mock pattern.
- **Beta-ish Wallet schema.** `TenantEnrichedUsageEvent__dll` is a relatively
  new DLO; field-name conventions differ from the GenAI DMOs (lowercase +
  `__c` instead of camelCase). [../../Developer/wallet-live-schema.md](../../Developer/wallet-live-schema.md)
  captures the verified schema; we'll need to re-verify if Salesforce
  changes it.
- **Custom Setting opt-in is a step admins can miss.** Mitigated by docs
  ([../../Admin/05-configure.md](../../Admin/05-configure.md) §1b) and by
  making the badge clearly say `ESTIMATED` so the discrepancy is visible.

## What we didn't pick (and why)

- **Compute both, show side-by-side.** Rejected — clutters the UI and
  creates an implicit suggestion that the two sources should agree (they
  often won't, due to PromoCredits, etc.).
- **Per-model USD pricing** — rejected because vendors price per-token in
  contract terms but Salesforce bills via Flex Credits with custom
  conversion. Encoding USD per model creates a maintenance burden that
  drifts every contract negotiation.

## Verification

End-to-end verified against `cvk-dev` 2026-05-15. Wallet-on path returns
`confidence=ACTUAL`; Wallet-off path falls through to `ESTIMATED`. Toggling
the Custom Setting flips the dashboard within one cache-invalidation
window.
