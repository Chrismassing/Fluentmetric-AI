# 02 — Install the Lightning Edition

> **Time:** ~15 minutes. **CLI required:** none. **Reversible:** yes — uninstall via Setup → Installed Packages.

## Before you start

- ✅ [01-prerequisites.md](01-prerequisites.md) checklist is green.
- ✅ You have **System Administrator** in the target org.
- ✅ You have the install URL from [../../CHANGELOG.md](../../CHANGELOG.md) for
  the version you're installing (look for the most recent
  `## [X.Y.Z]` entry — both edition install URLs are listed there).

## Step 1 — Install the package

1. **Open the install URL** from CHANGELOG.md in the same browser session
   you're logged into the target org.
   - Production: `https://login.salesforce.com/packaging/installPackage.apexp?p0=04t...`
   - Sandbox: replace `login` with `test`.
2. Salesforce shows the **Install FluentMetric AI** screen. Pick:
   - **Install for Admins Only** (recommended) — you'll assign permset to
     end users in Step 2.
3. Click **Install**.
4. If prompted *"Approve Third-Party Access"* — check the box and Approve.
   *(The package does not make external callouts; this consent is for the
   Apex framework's standard requests.)*
5. Wait for install to finish (1–3 min). You'll get a green banner.

> **What's now in your org:** 1 Lightning App (`FluentMetric AI`), 1 tab,
> 19 LWCs, ~30 Apex classes, 1 Permission Set (`FluentMetric_AI_User`),
> 1 Custom Setting, 2 Custom Metadata Types, 1 Lightning Message Channel,
> 1 Platform Cache Partition (skipped if you already provisioned it),
> 1 Custom Labels bundle.

## Step 2 — Assign the Permission Set to users

1. **Setup → Permission Sets → FluentMetric AI User**.
2. Click **Manage Assignments → Add Assignments**.
3. Pick the users who should see dashboards (admins, prompt engineers,
   AI product owners — whoever needs visibility).
4. Click **Assign**.

> **Heads up:** Users also need **Data Cloud permissions** to query DMOs.
> If your org uses a Permission Set Group that bundles "Data Cloud Admin" or
> "Data Cloud User" with `FluentMetric AI User`, assignees inherit both. If
> not, assign Data Cloud access separately.

## Step 3 — Smoke test

1. **Click the App Launcher** (9-dot grid, top-left).
2. Search for **FluentMetric AI**. Click the app.
3. The header shows a **date pill** (default: last 30 days) with resolved
   start/end dates. The five tabs are **Overview, Adoption, Explorer,
   Safety, Cost**.
4. **Overview tab** — KPIs render (Requests, Unique Users, Acceptance Rate,
   Tokens). If you see all zeros, your org has no Audit data in the
   selected window — pick a wider range or check
   [06-troubleshooting.md](06-troubleshooting.md).
5. **Explorer tab** — click any preset chip ("Top prompts", "Tokens by
   user", etc.). A bar chart should render in <2 seconds.

If steps 1–5 pass, the install is healthy.

## Step 4 — (Optional) Configure cost engine

The Lightning edition ships with cost analysis disabled by default to avoid
surprising users with rough tier-based estimates. To enable, see
[05-configure.md](05-configure.md).

## What's next

- **Want end users to learn the app?** Send them
  [04-getting-started.md](04-getting-started.md).
- **Adding the Tableau Next edition?** Continue to
  [03-install-tableau.md](03-install-tableau.md).
- **Need to change cost rates, Wallet behavior, or adoption denominator?**
  See [05-configure.md](05-configure.md).

## Uninstall

If you need to remove the package:

1. **Setup → Installed Packages → FluentMetric AI → Uninstall**.
2. Salesforce will block uninstall if any custom Apex / Flows reference the
   package's metadata. Resolve those references first (Setup will list them).
3. Permission Sets and Custom Settings *may* persist after uninstall — clean
   them up manually if needed.
