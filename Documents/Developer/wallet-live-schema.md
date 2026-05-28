# WALLET-LIVE-SCHEMA.md — Digital Wallet (Consumption Tags) Schema Reference

> **Status:** Verified end-to-end against `cvk-dev` on 2026-05-15. Schema is provisioned, the DLO is queryable, **and at least one consumption event has billed through**. `AiWalletDAO.isWalletAvailable()` returns `true`, `getTotalFlexCredits` returns a non-zero value, and `CostCalculatorService.costForWindow` returns `confidence=ACTUAL` / `source=ACTUAL_WALLET`. The full Wallet codepath is exercised in this org.

## Verified findings — cvk-dev (2026-05-15)

`cvk-dev` (Storm trial EE org, `OrganizationType: Enterprise Edition`, `IsSandbox: false`, instance `NA231`) **does** have Consumption Tagging provisioned after enabling Digital Wallet, and as of 2026-05-15 has billed-through consumption rows. The single live object FluentMetric AI reads is:

| Live object | Status | Field count | Rows (last 30 days) |
|---|---|---|---|
| `TenantEnrichedUsageEvent__dll` | queryable | 36 | ≥ 1 (1 FC total observed) |

Important corrections vs. the doc-derived guesses:
- The DLO suffix is **`__dll`** (Data Lake — `__dll`) **not** `__dlm` (Data Model). Verified by `sobject list` and `sobject describe`.
- All field names are **lowercase + `__c`** (e.g. `unitsconsumed__c`, `eventtime__c`, `userid__c`) — not camelCase like FluentMetric AI's GenAI DMOs (which still use camelCase per [live-schema.md](./live-schema.md)).
- `SELECT COUNT()` is **rejected** by this DLO ("SELECT COUNT() is not supported"). `isWalletAvailable()` uses `SELECT Id FROM ... LIMIT 1` instead.
- Resource/root-resource tags are stored as a **JSON-encoded string column** (`resourcetags__c`, `rootresourcetags__c`) directly on the same DLO — there is no separate Consumption Insights Extended object. Custom-tag aggregation parses this JSON in Apex.
- `userid__c` is on the DLO, so Wallet **can** attribute consumption per Salesforce User Id. The original plan's "Wallet doesn't tag by user" caveat is wrong for this schema.

These objects do **not** exist in cvk-dev (and per Salesforce docs, only appear in some configurations of fully provisioned Wallet orgs):
- `TenantEnrichedUsageEvent__dlm` (the DMO that the help docs reference)
- `TenantUsageAttrDetail`, `TenantHourlyEntitlementConsumption`, `TenantDailyEntitlementConsumption`

`EntityDefinition` queries for `%TenantEnriched%`, `%TenantHourly%`, `%TenantDaily%`, and `%__dlm` patterns also return no Consumption-Tagging rows. The org does have:
- `TenantUsageEntitlement` (87 rows) — entitlement metadata (e.g. "Einstein Service Credits = 1") but no per-event consumption.
- `TenantEntitlementTransaction` — transaction wrapper.
- `TenantUsageTypeMultiplier` — billing multipliers.
- The full `GenAi*__dlm` suite (Audit & Feedback DMOs) with 1,198 real `GenAIGatewayRequest__dlm` rows — this is what FluentMetric AI reads today.

`DigitalWallet` does exist as a standard object but it is the **Industries Payment** Digital Wallet (45 fields about payment gateway tokens, not consumption tagging). It is **not** the Wallet feature documented in `xcloud.wallet_*`.

## Why the gap

Per [Troubleshoot Digital Wallet](https://help.salesforce.com/s/articleView?id=xcloud.wallet_troubleshoot.htm&type=5):

> "Be sure you're in a Digital-Wallet-enabled production org. The Digital Wallet setup page isn't available in sandboxes or Data Cloud One companion orgs."

And per [Install the Consumption Tagging App](https://help.salesforce.com/s/articleView?id=xcloud.wallet_consumption_tagging_app_install.htm&type=5):

> "Installing the Consumption Tagging app in a sandbox or Data Cloud One companion org isn't supported."

So the Wallet DLOs are **provisioned only when**:
1. The org is a **production** org (not sandbox, not scratch, not Data Cloud One companion).
2. The org has **purchased a Digital-Wallet-enabled consumption product** (Agentforce, Data 360, etc.) — Wallet flows from billing entitlements, not from feature activation.
3. The admin has installed the **Consumption Tagging app** from Setup → Digital Wallet.

`cvk-dev` is a Storm trial EE org — production-classed but without the consumption-product purchase that would provision Wallet entitlements, so the DLOs never appear.

## Sandbox / non-prod path

**There is no supported sandbox path** to the Consumption Tagging DLOs. Specifically:
- Sandboxes are not eligible for the Digital Wallet setup page.
- Scratch orgs and Data Cloud One companion orgs are explicitly not supported.
- A non-purchaser org (like `cvk-dev`) can't install the app even though it's classified as production.

For development and CI, FluentMetric AI must:
1. **Treat Wallet data as optional everywhere.** All Wallet reads go through `IAiWalletDAO.isWalletAvailable()` which returns `false` on any `QueryException`. The cost path then falls back to today's tier-rate estimate.
2. **Mock the Wallet DAO in Apex tests.** No live DLO exists in cvk-dev or any scratch org, so unit tests must use mock implementations of `IAiWalletDAO`.
3. **Surface a clear UI disclaimer.** When `isWalletAvailable() == false`, the Cost panel shows "Digital Wallet data unavailable in this org — actuals require a Wallet-enabled production org with the Consumption Tagging app installed" plus a deep link to the install help article.

Until we get access to a Wallet-enabled production org for empirical schema verification, this doc records the doc-derived schema FluentMetric AI codes against. The DAO is built such that **a field-name mismatch only impacts the Wallet-actual codepath** — the estimate fallback is untouched.

## Verified live schema — `TenantEnrichedUsageEvent__dll` (cvk-dev, 36 fields)

| Live field | Type | FluentMetric usage |
|---|---|---|
| `Id` | id | Primary key |
| `id__c` | string | Internal record id (Wallet's own key) |
| `eventtime__c` | datetime | **Date filter — use this, not `CreatedDate`** |
| `processedtime__c` | datetime | When Wallet ingested the event |
| `unitsconsumed__c` | double | **Flex Credits billed** — primary measure |
| `usagevalue__c` | double | Raw usage before multiplier |
| `multiplier__c` | double | Currency / market-value multiplier |
| `unit__c` | double | Unit factor |
| `multipliertier__c` | string | Tier label (Basic/Standard/Advanced equivalent) |
| `usagetypedevelopername__c` | string | **Standard tag: usage type** (Flex Credits, etc.) |
| `usagesubtype0__c` / `usagesubtype1__c` / `usagesubtype2__c` | string | Subtype hierarchy |
| `featuredevelopername__c` | string | **Standard tag: feature** (e.g., `prompt_builder`) |
| `resourcetype__c` | string | **Standard tag: resource type** (agent, action, etc.) |
| `resourceidorapiname__c` | string | **Standard tag: resource id / GenAI prompt API name** |
| `rootresourcetype__c` | string | Root resource type |
| `rootresourceidorapiname__c` | string | Root resource id (top-level agent/source) |
| `resourcetags__c` | string (JSON) | **Custom tags** — JSON map of key/value pairs |
| `rootresourcetags__c` | string (JSON) | Custom tags applied at root resource level |
| `userid__c` | string | **Salesforce User Id** when user-initiated; null for system |
| `cardname__c` | string | Wallet card label |
| `carddefinitiondevelopername__c` | string | Wallet card type |
| `tenantbillingusageeventid__c` | string | Business key for joins |
| `tenantusagetypemultiplierid__c` | string | FK to `TenantUsageTypeMultiplier` |
| `usagereportingorgid__c` | string | Reporting org id |
| `entitlementorgid__c` | string | 18-digit entitlement org id |
| `usagebusinessenvtype__c` | string | Production / sandbox env classification |
| `correlationidentifier__c` | string | Cross-system correlation id |
| `replayid__c` | string | Wallet replay cursor |
| `additionalinfo__c` | string (JSON) | Free-form metadata |
| `additionalinfoschema__c` | string | Schema id for `additionalinfo__c` |
| `DataSource__c`, `DataSourceObject__c`, `InternalOrganization__c`, `KQ_id__c` | string | Data Cloud bookkeeping fields |

### Calculated field example from the docs

The "Data Space" calculated field per [Example: Create a Report on Usage by Data Space](https://help.salesforce.com/s/articleView?id=xcloud.wallet_custom_report_dcr_dataspace.htm&type=5):

```
REGEXP_EXTRACT([Consumption Insights DMO].[Additional Info], '"data_space":\s+"(.*?)"')
```

This tells us:
- `Additional Info` is a JSON string with a `data_space` key.
- The DMO name is `Consumption Insights DMO` — the *DMO* layered on top of the `TenantEnrichedUsageEvent` *DLO*.
- We should mirror this calculated-field pattern in Apex (parse the JSON for `data_space` after the SOQL fetch).

## Doc-derived schema — sibling DLOs

| DLO | Purpose | When we use it |
|---|---|---|
| `TenantEnrichedUsageEvent` | Per-event tagged consumption | Primary cost source for FluentMetric AI when Wallet is available |
| `TenantUsageAttrDetail` | Per-event attributes including `Data Space API Name` | Join target when slicing by data space |
| `TenantHourlyEntitlementConsumption` | Hourly aggregate per entitlement | Tableau workbook source per [Query Wallet Data in Tableau](https://help.salesforce.com/s/articleView?id=xcloud.wallet_query_tableau_data.htm&type=5) |
| `TenantDailyEntitlementConsumption` | Daily aggregate per entitlement | Tableau workbook source for trend visualizations |

## DAO design implications

`AiWalletDAO` (Apex) and the corresponding LWC code:

1. **Field names live in one constant block** at the top of the DAO. If a real prod org reveals different casing, we update one map and re-deploy.
2. **`isWalletAvailable()` is the gatekeeper.** Wraps `Database.query('SELECT count() FROM TenantEnrichedUsageEvent__dlm LIMIT 1')` in a try/catch that returns `false` on `QueryException` (object missing, no permission, no data space mapping). Cached per-transaction via static.
3. **All Wallet queries are dynamic SOQL** (consistent with rest of FluentMetric AI's DMO pattern).
4. **Field-list builder is conservative** — every queried field is wrapped in a try/check; if the SObjectField doesn't exist in `Schema.getGlobalDescribe()`, the DAO logs a warning and returns `isWalletAvailable() = false` rather than crashing.
5. **Custom-tag SDM is treated as separate** — `getFlexCreditByCustomTag(...)` probes `Consumption Insights Extended` semantic model availability independently. If the standard SDM is present but the Extended one isn't (pilot status), Custom Tag pivots are disabled in the UI but Wallet totals still render.

## Verification checklist (run when consumption events start billing through)

- [x] Confirm `TenantEnrichedUsageEvent__dll` exists as a queryable object — verified 2026-05-13 in cvk-dev.
- [x] Capture verbatim field list via `sf sobject describe`.
- [x] Update [AiWalletDAO.cls](../../force-app/main/default/classes/dao/AiWalletDAO.cls) field-name constant block to lowercase + `__dll`.
- [x] Verify all DAO methods succeed against the empty live DLO without exceptions.
- [ ] Once consumption-product events bill through (`unitsconsumed__c` > 0 rows appear): rerun `CostCalculatorWalletTest` against a real Wallet-tagged date range.
- [ ] Reconcile FluentMetric AI Cost panel "Total Flex Credits" with Salesforce Consumption Analytics (Tableau Next) — within $0.01.
- [ ] Validate `resourcetags__c` JSON structure once real tag rows arrive (current `aggregateTagRows` assumes `Map<String, String|primitive>` shape).
- [ ] Update `tableau/NAMING-ALIGNMENT.md` if any Tableau Next column has been renamed since the workbook was published.

## References

- [Standard Consumption Tags overview](https://help.salesforce.com/s/articleView?id=xcloud.wallet_usage_tags_overview.htm&type=5)
- [Build Custom Reports Using Standard Consumption Tags](https://help.salesforce.com/s/articleView?id=xcloud.wallet_custom_reports_build.htm&type=5)
- [Track Consumption for GenAI Prompts for Flex Credits](https://help.salesforce.com/s/articleView?id=xcloud.wallet_genai_prompts_usage.htm&type=5)
- [Consumption Analytics Dashboard (Tableau Next)](https://help.salesforce.com/s/articleView?id=xcloud.wallet_consumption_analytics_dash.htm&type=5)
- [Install the Consumption Tagging App](https://help.salesforce.com/s/articleView?id=xcloud.wallet_consumption_tagging_app_install.htm&type=5)
- [Troubleshoot Digital Wallet](https://help.salesforce.com/s/articleView?id=xcloud.wallet_troubleshoot.htm&type=5)
- [Query Digital Wallet Data in Tableau](https://help.salesforce.com/s/articleView?id=xcloud.wallet_query_tableau_data.htm&type=5)
- [Example: Usage by Data Space (DMO)](https://help.salesforce.com/s/articleView?id=xcloud.wallet_custom_report_dcr_dataspace.htm&type=5)
- [Example: Usage by Data Space (DLO join)](https://help.salesforce.com/s/articleView?id=xcloud.wallet_custom_report_dcr_dataspace_join.htm&type=5)
- [Digital Wallet Permissions](https://help.salesforce.com/s/articleView?id=xcloud.wallet_permissions.htm&type=5)
