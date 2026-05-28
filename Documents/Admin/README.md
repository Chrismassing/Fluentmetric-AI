# Admin Guide — FluentMetric AI

> **Audience:** Salesforce admins installing or operating FluentMetric AI in
> their org. **No CLI required** — every step has a Setup-UI path.
> Need to extend the package or read the Apex? See [../Developer/README.md](../Developer/README.md).
> Want design rationale? See [../Architect/README.md](../Architect/README.md).

FluentMetric AI ships in two editions, governed by separate Permission Sets
and installable independently. This guide walks an admin through prerequisites,
install, first-run, configuration, and day-2 ops.

## Reading order

1. **[01-prerequisites.md](01-prerequisites.md)** — Pre-flight checklist.
   Confirm Data Cloud, Einstein Audit & Feedback, license entitlements, and
   Platform Cache before installing.
2. **[02-install-lightning.md](02-install-lightning.md)** — Lightning edition
   install. **One-click URL → permset assign → smoke test.** ~15 min.
3. **[03-install-tableau.md](03-install-tableau.md)** — Tableau Next edition
   install (optional). Requires Lightning edition installed first plus
   Tableau Next + Agentforce licenses. ~30 min.
4. **[04-getting-started.md](04-getting-started.md)** — First-run walkthrough
   for end users. Pin the app, pick a date range, tour the five tabs.
5. **[05-configure.md](05-configure.md)** — Custom Settings (cost gate,
   Wallet), Custom Metadata (rate cards, entitlement sources), permset
   assignment patterns.
6. **[06-troubleshooting.md](06-troubleshooting.md)** — Common issues with
   remediation. *"Dashboards show no data", "permset not visible", "agent
   won't activate"*.
7. **[07-upgrade.md](07-upgrade.md)** — Installing a newer 2GP version. What
   changes vs. preserves.

## When to call your developer team instead

This Admin guide assumes a clicks-not-code install. Hand off to your
developer / release team if:

- The org needs custom dashboards beyond the five shipped tabs.
- You want to extend the Apex services or add new DMOs.
- You want to publish the package from your *own* DevHub instead of
  installing the published 2GP version (see [../Developer/release.md](../Developer/release.md)).
