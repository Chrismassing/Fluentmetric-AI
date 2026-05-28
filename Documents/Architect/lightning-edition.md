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
- **Permission Set:** `FluentMetric_AI_User`.
- **Custom Setting** `FluentMetric_Cost_Settings__c` — per-org Flex Credit
  rate, fallback model, Wallet toggle.
- **Custom Metadata Types:**
  - `FluentMetric_Cost_RateCard__mdt` — per-model FC/USD rate cards.
  - `FluentMetric_Entitlement_PermissionSet__mdt` — declares which sources
    define the **entitled-user denominator** for adoption analytics. Each row
    pairs a developer name with an `Entitlement_Type__c` picklist value
    (`PermissionSet`, `PermissionSetGroup`, or `Profile`); the resolver routes
    to the right query path. Three seed rows ship: `Prompt_Template_User`,
    `Einstein_Generative_AI_User`, `Prompt_Template_Manager` (all
    `PermissionSet`). When the CMT is empty, no row matches the org, or any
    resolution query throws, the engine flips `entitledFallback = true` and
    falls back to "all active users" so the dashboards never break.
- **Message channels** for date and filter coordination across LWCs.

## Design rationale

### Adoption denominator via CMT, not hard-coded

Different orgs grant Einstein GenAI capability differently — some via a single
Permission Set, others via a Permission Set Group, others via a Profile.
Encoding the denominator in `FluentMetric_Entitlement_PermissionSet__mdt`
lets admins tune which sources count *without an Apex change*. The
`entitledFallback` flag preserves dashboard rendering when the CMT is
misconfigured, trading visible accuracy (a tooltip) for never breaking the UI.

Adoption rate formula: `(active ∩ entitled) / entitled`, bounded to [0, 1.0].
When `entitledFallback=true` shows in the funnel tooltip, the denominator
silently switched to "all active users" — that's a config signal, not a bug.

Admin-side runbook for the CMT lives at
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
