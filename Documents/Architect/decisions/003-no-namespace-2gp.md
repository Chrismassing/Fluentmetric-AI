# ADR 003 — No-namespace 2GP packages

**Status:** Accepted
**Date:** 2026-04-20

## Context

Both editions ship as Salesforce Unlocked Packages (2GP). 2GP supports
two namespace modes:

- **Namespaced** — every metadata API name gets prefixed (e.g.,
  `fmai__AiInsightsService`, `fmai__FluentMetric_AI_User`). Required for
  AppExchange managed packages but optional for unlocked.
- **No-namespace** — metadata API names stay as authored (`AiInsightsService`,
  `FluentMetric_AI_User`).

We chose no-namespace.

## Decision

`sf package create` for both editions uses `--no-namespace`. Resulting
packages declare `"namespace": ""` in `sfdx-project.json`.

## Rationale

| Concern | Namespaced | No-namespace ✅ |
|---|---|---|
| Existing scratch-org installs (developers) keep working without rename | ❌ — every API name changes | ✅ |
| Metadata names in code, CHANGELOG, docs stay stable | ❌ | ✅ |
| Customer can install alongside another package that defines `AiInsightsService` | ✅ | ❌ — naming collision risk |
| AppExchange listing path | ✅ | ❌ — needs managed |
| One-way migration cost when we ever go managed | Already paid | Will need to pay |

The trade-off is **collision risk vs migration cost**. We accept some
collision risk (the names `AiInsightsService` / `FluentMetric_AI_User` are
specific enough to be unlikely to collide) in exchange for keeping every
existing developer install + every doc reference + every customer install
working without metadata renames.

If we ever pursue an AppExchange listing, we'll need to:

- Migrate to a namespaced 2GP first.
- Rename every metadata API reference in customer orgs (one-time pain).
- Update every doc and the CHANGELOG.

That's a deferred problem; not v1's problem.

## Consequences

### Positive

- Clone-deploy-iterate works without metadata-name fix-ups.
- Docs reference the same names that exist in the package and in scratch
  orgs.
- Existing customer scratch-org installs migrate to 2GP installs cleanly.

### Negative

- **No AppExchange path** without a future one-way migration to
  namespaced 2GP (or a managed package).
- **Collision risk** — if a customer org has another package or homebrew
  Apex named `AiInsightsService`, install will fail. Acceptable risk given
  the specificity of the name.
- **Permission Set name collisions** — if a customer has a permset called
  `FluentMetric_AI_User` already, install fails with a clear error. The
  permset name is package-specific enough that this is unlikely.

## When to revisit

Revisit if:

- We pursue an AppExchange listing.
- A customer hits a metadata-name collision (open a GitHub issue if you
  encounter this — we'll consider a name-prefix migration).
- Salesforce changes 2GP rules to make namespaced installs as cheap as
  no-namespace (currently the "rename everything" cost is one-way).

## Alternatives considered

- **Namespaced 2GP from day one** — rejected because every existing
  scratch-org install would need a rename pass. Premature optimization for
  an AppExchange listing we haven't committed to.
- **Managed package** — rejected because admins should be able to inspect
  and customize Apex / LWCs. See [001-two-editions.md](001-two-editions.md)
  for the parallel discussion on customer-edit affordances.
