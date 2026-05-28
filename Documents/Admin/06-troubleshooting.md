# 06 — Troubleshooting

> Common issues and the fix. If your symptom isn't here, check
> [../Developer/release.md](../Developer/release.md) for release-engineering
> issues, or open a GitHub issue with the **org type / edition / install
> URL version / screenshot**.

## "Dashboards show no data"

**Likely cause:** the date range is outside the org's audit-retention window
or your org has no audit data yet.

| Check | Action |
|---|---|
| Is the date pill in the future? | Reset to **Last 30 days**. |
| Has Einstein GenAI been used in the org during the window? | Run a quick prompt manually, then re-load dashboards. Audit rows appear within ~5 min. |
| Is **Audit and Feedback Data** still On? | Setup → Einstein → Generative AI → toggle. |
| Is the user assigned `FluentMetric_AI_User` AND a Data Cloud read permset? | Assign both. |
| Run a sanity SOQL: `SELECT COUNT() FROM GenerativeAiAuditFeedback__dlm WHERE timestamp__c = LAST_N_DAYS:30` | Returns 0 = no data; not a bug. |

## "Permission Set not visible in Setup"

After installing the package, `FluentMetric_AI_User` (or
`FluentMetric_AI_Tableau_User`) doesn't show up.

**Likely cause:** install completed but didn't deploy the permset (rare —
usually means partial install).

1. **Setup → Installed Packages → FluentMetric AI → View Components**.
   Confirm the permset is listed.
2. If listed but invisible: clear the cache (`Setup → Cache → Clear`) or log
   out and back in.
3. If not listed: re-install from the same CHANGELOG URL. 2GP installs are
   idempotent.

## "App not in App Launcher"

**Likely causes (in order of frequency):**

1. **Permset not assigned to the user** — assign `FluentMetric_AI_User`
   (or `FluentMetric_AI_Tableau_User` for the Tableau edition).
2. **For the Tableau edition: Tableau Next PSL not assigned** — confirm
   `TableauEinsteinIncludedAppPsl` (or `TableauEinsteinUserPsl`) is on the
   user. After assigning, log out and back in.
3. **App is hidden by Profile** — check **Setup → Apps → App Manager →
   FluentMetric AI → User Profiles** and ensure the user's profile has
   "Visible".

## "Agent won't activate" (Tableau edition)

The `FluentMetric_Tableau_Analyst` agent appears in **Setup → Einstein →
Copilots** but the **Activate** button is greyed out, or activation
errors out.

| Symptom | Fix |
|---|---|
| Activate button greyed out | Confirm Agentforce is licensed. Open a Salesforce case if it is. |
| "Connected App not configured" error | Provision the Agentforce-required Connected App. The agent uses Salesforce-internal auth — no manual cert needed. |
| Activated but doesn't appear in Copilot tray | Reload the page; if still missing, the user lacks `FluentMetric_AI_Tableau_User` or `TableauEinsteinIncludedAppPsl`. |

## "Cost tab shows ESTIMATED everywhere — I expected ACTUAL"

`CostCalculatorService` falls back to the tier-rate estimate when Wallet is
unavailable. **ACTUAL** badges only appear when:

1. **Setup → Custom Settings → FluentMetric Cost Settings → Enable Wallet Costs** = ✅.
2. The **Consumption Tagging app** is installed in the org.
3. `TenantEnrichedUsageEvent__dll` is populated (queryable, has rows in the
   selected date range).

If all three are true and you still see ESTIMATED, run anonymous Apex:

```apex
System.debug(AiWalletDAO.isWalletAvailable());
```

A `false` result tells you the DAO can't reach the DLO — usually a Data
Cloud permission issue on the running user.

## "Adoption rate is 0% / 100% / nonsensical"

Symptom: numbers don't match what you expect.

1. Open the Adoption tab. Hover the funnel — is `entitledFallback=true`
   shown? If yes, the `FluentMetric_AI_Entitled_User` permission set has
   no assignees in this org and the denominator falls back to all active
   users. Assign that permset to every user expected to use Einstein
   Generative AI features; see
   [05-configure.md §2](05-configure.md#2-adoption-denominator-entitled-user-count).
2. If `entitledFallback=false` but the rate looks wrong: the denominator
   is the assignee count of `FluentMetric_AI_Entitled_User`. Verify the
   assignment list in Setup → Permission Sets → FluentMetric AI Entitled
   User → Manage Assignments matches who you expect to be in scope.
3. Tableau Next adoption KPI lagging the Lightning number: the Tableau
   denominator reads `User.FluentMetric_IsEntitled__c` which is stamped
   nightly by `FluentMetricEntitlementSyncSchedulable`. Force a refresh
   by re-running `System.schedule` of that class — the Lightning side
   resolves PSA live and updates immediately.

## "Explorer drill panel shows nothing"

Clicking a group label opens the side-sheet but it's empty.

**Likely cause:** the panel runs a follow-up SOQL with the same filters.
If your SOQL governor limit is exhausted (rare, but possible after heavy
ad-hoc Explorer use), the follow-up returns nothing.

Reload the page. If it still happens, narrow the date range — you're
probably hitting the 50,000 row SOQL ceiling.

## "Tableau Next dashboards are empty inside the workspace"

The semantic model wasn't published, or it doesn't reference the right DMOs.

1. Re-run `make publish-semantic-model TARGET_ORG=<your-org-alias>`, or
   re-author per [03-install-tableau.md §Step 2 Option B](03-install-tableau.md).
2. In **Tableau Next → Data Manager**, open `FluentMetric_AI` and confirm
   the connected DMOs match what the dashboards reference.
3. Republish the workspace from **Tableau Next → Workspace Manager**.

## When to escalate

Open a GitHub issue (or your support channel) when:

- A KPI shows a clearly wrong number (e.g., negative tokens, >100%
  acceptance) — that's a bug, not a config issue.
- A page errors with a red banner mentioning `AiInsightsController` /
  `FmTableauNextController` — capture the message and the org's API
  version.
- A 2GP install URL fails with a non-obvious error like *"Component
  conflict"* — paste the full Salesforce error into the issue.

Routine config questions ("how do I add a new entitlement source?") belong
in [05-configure.md](05-configure.md).
