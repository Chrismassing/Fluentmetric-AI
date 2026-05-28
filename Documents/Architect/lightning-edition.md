# FluentMetric AI — Lightning Edition (Architect)

> **Audience:** Architects evaluating fit and reviewing design intent.
> Looking to install? See [../Admin/02-install-lightning.md](../Admin/02-install-lightning.md).

The original FluentMetric AI: a Salesforce-native dashboard app reading the
Einstein Generative AI Audit & Feedback DMOs through a 4-layer Apex stack.
**No Tableau license required.**

## Prerequisites

- Salesforce org with Data Cloud + Einstein Audit & Feedback enabled.
- 1,000+ rows of audit history recommended (dashboards work with less, just
  sparser).
- (Recommended) Platform Cache partition `FluentMetric_AI` provisioned, 5+ MB,
  for User/Prompt name resolution caching.

Detailed admin checklist: [../Admin/01-prerequisites.md](../Admin/01-prerequisites.md).

## What gets deployed

- **Apex:** controllers, services (`AiInsightsService`, `UserResolverService`,
  `CostCalculatorService`, `EntitlementService`), DAO + interface
  (`AiInsightsDAO`, `AiWalletDAO`), DTOs, tests. See
  [../Developer/apex-services.md](../Developer/apex-services.md).
- **LWC (19 components):** the full Lightning dashboard surface. See
  [../Developer/components.md](../Developer/components.md).
- **Lightning App + Tab + FlexiPage:** `FluentMetric_AI`,
  `FluentMetric_AI_Dashboard`.
- **Permission Sets:**
  - `FluentMetric_AI_User` — grants access to the dashboards and Apex services.
  - `FluentMetric_AI_Entitled_User` — defines the **adoption-denominator scope**.
    Admins assign it to every user expected to use Einstein Generative AI;
    assignees become the denominator of the adoption rate. Grants no
    functional access — runtime AI permissions still come from
    Einstein Generative AI User / Prompt Template User / etc.
- **Custom Setting** `FluentMetric_Cost_Settings__c` — per-org Flex Credit
  rate, fallback model, Wallet toggle.
- **Custom Metadata Types:**
  - `FluentMetric_Cost_RateCard__mdt` — per-model FC/USD rate cards.
- **User custom field** `FluentMetric_IsEntitled__c` (Checkbox) — denormalized
  projection of "user is assigned to the entitled permset". Stamped nightly
  by `FluentMetricEntitlementSyncSchedulable` from PSA so the Tableau Next
  semantic model can compute adoption rate without joining PSA. Lightning
  adoption math still resolves entitlement live; the boolean is analytics-only.
- **Message channels** for date and filter coordination across LWCs.

## Design rationale

### Adoption denominator via a single permission set

Different orgs grant Einstein GenAI capability differently, so the original
design used a CMT mapping table to enumerate which permission sets / PSGs /
profiles defined "entitled". That extra indirection was removed in favor of
a single, well-known permission set: `FluentMetric_AI_Entitled_User`.
Admins assign that permset to the people they want measured; assignment is
a one-click action in Setup, surfaces in standard reports, composes with
PSGs the customer already uses, and doesn't require a deploy to change scope.

When the permset has no assignees (or the PSA query fails) the engine flips
`entitledFallback = true` and falls back to "all active users" so the
dashboards never break — it's a config signal, not a bug.

Adoption rate formula: `(active ∩ entitled) / entitled`, bounded to [0, 1.0].

Admin-side runbook for the permset lives at
[../Admin/05-configure.md](../Admin/05-configure.md).

### Wallet-first cost engine

`CostCalculatorService.costForWindow()` prefers Digital Wallet actuals
(`TenantEnrichedUsageEvent__dll`) when both `Enable_Wallet_Costs__c` is on and
`AiWalletDAO.isWalletAvailable()` returns true. Falls back to a tier-rate
estimate otherwise. Confidence/source surfaced as visible badges
(`ACTUAL` / `HIGH` / `ESTIMATED` / `FALLBACK` / `NOT_COSTED`) so users always
know the basis. Schema reference: [../Developer/wallet-live-schema.md](../Developer/wallet-live-schema.md).
ADR: [decisions/002-wallet-first-cost.md](decisions/002-wallet-first-cost.md).

## Architecture summary

```
LWC → @AuraEnabled Controller → Service → DAO → Data Cloud DMOs
```

Full architecture in [architecture.md](architecture.md). Live data model in
[../Developer/live-schema.md](../Developer/live-schema.md).

## Coexistence with the Tableau Next edition

The two editions don't share Lightning UI metadata, but the Tableau Next
edition's Apex *delegates* to `AiInsightsService` from the Lightning edition.
**Lightning must be installed first** (or both deployed together). Both apps
appear in the App Launcher, governed by separate Permission Sets. Detail:
[tableau-edition.md](tableau-edition.md).
