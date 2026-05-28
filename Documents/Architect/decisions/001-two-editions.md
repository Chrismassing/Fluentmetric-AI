# ADR 001 — Two editions, one repo

**Status:** Accepted
**Date:** 2026-04-15

## Context

FluentMetric AI started as a Lightning-only product: native LWCs over Data
Cloud GenAI Audit DMOs, no Tableau dependency. Customer demand emerged for
a second surface — full Tableau Next workspaces over the same data, plus an
Agentforce conversational analyst — for accounts that already pay for
Tableau Next on Salesforce.

We had three plausible structures:

1. **Single package, both surfaces.** One install URL, both Lightning and
   Tableau metadata together.
2. **Two repos.** Lightning lives in this repo; Tableau spins out into a
   separate repo with duplicated Apex business logic.
3. **One repo, two packages.** Both editions in `force-app/` and
   `force-app-tableau/`, two separate 2GP packages from the same DevHub,
   Tableau-edition Apex *delegates* to Lightning-edition services.

## Decision

**Option 3.** One repo, two `packageDirectories`, two 2GP packages, with the
Tableau edition declaring Lightning as a `packageDependency`. Tableau-
edition invocable actions and controllers thin-wrap calls into
`AiInsightsService` from the Lightning edition.

## Rationale

| Concern | Option 1 (single pkg) | Option 2 (two repos) | Option 3 (one repo / two pkgs) ✅ |
|---|---|---|---|
| Customer who only wants Lightning | Pays for Tableau metadata they don't use | Clean | Clean |
| Customer who only wants Tableau | Pays for Lightning UI they don't use | Clean | Forces Lightning install (acceptable — Apex delegation) |
| Single source of truth for business rules | Yes | **No** — duplicated `AiInsightsService` | Yes |
| Independent release cadence | No — one CHANGELOG | Yes | Yes — separate `04t...` per edition |
| Drift risk | Low | **High** | Low |

The decisive factor: **drift risk on duplicated business rules**. `AiInsightsService`
encodes the entitled-user denominator, the Wallet-first cost engine, and
the acceptance-rate computation. Forking this logic into a second repo
guarantees the two products silently diverge. Delegation keeps it
single-sourced.

Option 1 was rejected because we have customers who buy *only* Lightning
and customers who buy *only* Tableau Next — bundling them in one package
forces both populations to install metadata they'll never use, and a
Tableau-Cloud-on-the-side customer would refuse the Tableau Next-specific
metadata entirely.

## Consequences

### Positive

- Single CHANGELOG / GitHub Releases trail for the project.
- `AiInsightsService` is the single source of truth — fix a bug once,
  both editions benefit.
- Customers get edition-specific install URLs and only pay (in metadata
  weight) for what they use.

### Negative

- **Tableau edition installs depend on Lightning** — admins installing the
  Tableau-edition URL also pull Lightning. The 2GP `packageDependency`
  handles this transparently, but admins occasionally do a double-take.
  Mitigated by docs: [../../Admin/03-install-tableau.md](../../Admin/03-install-tableau.md)
  states this clearly.
- **Cross-package PRs are tricky to review** — touching `AiInsightsService`
  may break Tableau-edition compile. Mitigated by the
  [Developer contributing checklist](../../Developer/contributing.md) and
  CI running both edition test suites on every PR.
- **Two `04t...` install URLs to maintain per release.** The `make release`
  target handles this; manually it's two `sf package version create` calls.

## Alternatives considered

- **Managed package** — rejected because we want admins to be able to
  inspect and customize Apex / LWCs, and a managed package locks that down.
  Also requires a namespace, which would prefix every metadata API name and
  force a one-way migration for existing scratch-org installs.
- **Namespaced 2GP** — rejected for the same metadata-rename reason. See
  [003-no-namespace-2gp.md](003-no-namespace-2gp.md).

## Reverses

This ADR can be reversed if we ever add a third edition (e.g., a Slack-
native edition) that doesn't make sense to delegate through Lightning — at
that point, the `AiInsightsService`-as-shared-kernel model may need to
become a small published "core" package both surface-editions depend on.
