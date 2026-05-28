# 07 — Upgrade to a Newer Version

> **Audience:** Admins moving an org from one published 2GP version to
> another. **Same install URL pattern as the initial install** — Salesforce
> handles the upgrade in place.

## Before you upgrade

- ✅ Read the **target version's CHANGELOG entry** in
  [../../CHANGELOG.md](../../CHANGELOG.md). Pay attention to:
  - **Upgrade notes** call-out (e.g., new permset fields, new Custom Setting fields).
  - **Removed** section — anything you depend on that's been deleted.
  - **Security** section — new permset grants you may need to review.
- ✅ Schedule the upgrade outside of peak Einstein usage. Upgrades take
  1–3 minutes and don't take dashboards offline, but the cache invalidates
  briefly so the first page load post-upgrade is slower.
- ✅ Test in a sandbox first if you have one. Use the **`https://test.salesforce.com/...`**
  variant of the install URL.

## Step 1 — Open the new install URL

1. Find the target version's install URL in
   [../../CHANGELOG.md](../../CHANGELOG.md).
2. Open it in the same browser session you're logged into the target org.
3. Salesforce detects an existing `FluentMetric AI` install and shows
   **"Upgrade FluentMetric AI to version X.Y.Z"**.
4. Pick **Install for Admins Only** (the existing permset assignments are
   preserved either way, but Admin-Only avoids re-running profile pickers).
5. Click **Upgrade**.

> **What 2GP preserves on upgrade:**
> - All Custom Setting values (rates, gates).
> - All Custom Metadata records (rate cards, entitlement sources).
> - All Permission Set assignments.
> - Platform Cache partition allocations.
>
> **What 2GP overwrites:**
> - Apex classes, LWCs, Flows, FlexiPages, Permission Set definitions
>   (the permset *assignments* persist; the permset's grants are replaced
>   by the new version's definitions).
> - Custom Labels, Lightning Message Channels.

## Step 2 — Smoke test (same as the initial install)

After upgrade completes:

1. **App Launcher → FluentMetric AI** → tab through Overview / Adoption /
   Explorer / Safety / Cost. KPIs should render.
2. **Click a preset chip in Explorer** — verify the chart re-runs.
3. If you have the Tableau edition, also test **Open in Tableau Next** and
   ask the agent a question.

## Step 3 — Apply any version-specific upgrade notes

The CHANGELOG **Upgrade notes** call-out flags one-time admin tasks tied to
this release. Examples:

- *"Permset adds new field-level read on `Enable_Wallet_Costs__c`"* — no
  action; the install handled it.
- *"New Custom Metadata record needed: `FluentMetric_Entitlement_PermissionSet__mdt`
  → `My_Custom_Source`"* — manual step; follow
  [05-configure.md](05-configure.md).
- *"Cost Tab now defaults to enabled"* — review your Custom Setting if you
  want to override the new default.

## Rollback

2GP doesn't support automatic version rollback. If a release breaks
something:

1. **Setup → Installed Packages → FluentMetric AI → Uninstall**.
2. Re-install the previous version's URL from CHANGELOG.md.
3. Re-apply Custom Setting / Custom Metadata values from your records (they
   *should* persist through uninstall+reinstall, but back them up before
   uninstalling just in case).

For non-critical regressions, prefer **forward fixes** — file a GitHub
issue and wait for a patch release rather than rolling back.

## Coordinating with the Tableau Next edition

If you have **both editions** installed, upgrade them in this order:

1. Lightning edition first.
2. Tableau Next edition second.

The Tableau edition's Apex delegates to Lightning's services, so a Lightning
upgrade that changes a method signature could leave the Tableau edition
temporarily broken until you upgrade it too. Each release tested together
in `cvk-dev`, but the version-pair install order matters.
