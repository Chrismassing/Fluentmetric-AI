# FluentMetric_AI — Tableau Next SDM Field Map

This document captures the **actual** field apiNames inside the `FluentMetric_AI`
Tableau Next semantic model in `cvk-dev`, as discovered via
`/services/data/v66.0/ssot/semantic/models/FluentMetric_AI` on 2026-05-28.

**Why this exists:** Tableau Next derives SDM `apiName` values from the source
DMO field labels and adds numeric suffixes when the same name appears across
multiple data objects (e.g. `userId__c` exists on both `GenAIGatewayRequest__dlm`
and `GenAIFeedback__dlm` → SDM emits `User_Id` and `User_Id1`). The raw DMO
field names are NOT what calc-field expressions, viz_specs, or relationship
criteria reference — they reference the SDM apiNames below. Anything written
against the raw DMO field names will fail with "field not found" at POST time.

**Scope:** This map is for the cvk-dev SDM. A different org's SDM may produce
different suffix numbers if the data objects are added in a different order.
Re-run `python ~/.claude/skills/tableau-semantic-authoring/scripts/discover_sdm.py
--sdm FluentMetric_AI --json` to confirm before authoring against a new org.

---

## Data objects in the SDM

| SDM `apiName`              | Source DMO                  | Role                                  |
| -------------------------- | --------------------------- | ------------------------------------- |
| `GenAIGatewayRequest_dlm`  | `GenAIGatewayRequest__dlm`  | Request rows (one per gateway call)   |
| `GenAIGeneration_dlm`      | `GenAIGeneration__dlm`      | Generation outputs                    |
| `GenAIFeedback_dlm`        | `GenAIFeedback__dlm`        | Feedback events                       |
| `GenAIFeedbackDetail_dlm`  | `GenAIFeedbackDetail__dlm`  | Feedback detail rows                  |
| `GenAIContentCategory_dlm` | `GenAIContentCategory__dlm` | Content moderation categories         |
| `GenAIContentQuality_dlm`  | `GenAIContentQuality__dlm`  | Content quality + toxicity scores     |
| `User_dlm`                 | `ssot__User__dlm`           | Standard User profile (added 5/28)    |

## Relationships

| apiName                       | Left → Right                                 | Cardinality |
| ----------------------------- | -------------------------------------------- | ----------- |
| `User_GenAIGatewayRequest`    | `User_dlm.User_Id2` ↔ `GenAIGatewayRequest_dlm.User_Id` | OneToMany   |

---

## Field apiNames — by data object

### `GenAIGatewayRequest_dlm`

Source: `GenAIGatewayRequest__dlm`. This is the highest-cardinality table and
projected fields drive every dashboard.

| Source field (raw DMO)         | SDM `apiName`               | Notes                                       |
| ------------------------------ | --------------------------- | ------------------------------------------- |
| `userId__c`                    | `User_Id`                   | Join key to `User_dlm.User_Id2`             |
| `timestamp__c`                 | `Timestamp1`                | Suffix 1 because `Timestamp` collides       |
| `model__c`                     | `Model`                     |                                             |
| `feature__c`                   | `Feature`                   |                                             |
| `prompt__c`                    | `Prompt`                    |                                             |
| `maskedPrompt__c`              | `Masked_Prompt`             |                                             |
| `promptTemplateDevName__c`     | `Prompt_Template_Dev_Name`  |                                             |
| `totalTokens__c`               | `Total_Tokens`              | Already aggregated upstream (Sum)           |
| `completionTokens__c`          | `Completion_Tokens`         |                                             |
| `promptTokens__c`              | `Prompt_Tokens`             |                                             |

### `User_dlm`

Source: `ssot__User__dlm`. Projected 2026-05-28.

| Source field           | SDM `apiName` | Notes                                           |
| ---------------------- | ------------- | ----------------------------------------------- |
| `ssot__Id__c`          | `User_Id2`    | Join key to `GenAIGatewayRequest_dlm.User_Id`   |
| `ssot__Department__c`  | `Department`  | Clean name — no suffix                          |
| `ssot__Title__c`       | `Title`       | Closest analogue to "Profile" in viz_specs      |
| `ssot__Username__c`    | `Username`    |                                                 |
| `ssot__FluentMetric_IsEntitled__c` | `Is_Entitled` | Stamped nightly by `FluentMetricEntitlementSyncSchedulable` from PSA. Projects as Text (`'true'` / `'false'`). Drives `Distinct_Entitled_Users_clc` and `Adoption_Rate_clc`. |

**Notable absences in `ssot__User__dlm`:**

- **`IsActive`** — not projected; viz_specs originally referenced it as a filter,
  but it does not exist on `ssot__User__dlm`. Drop the filter.
- **Profile (the sObject)** — Data Cloud's User DMO doesn't project Profile;
  `Title` is the closest categorical dimension. Use `Title` wherever the plan
  says "Profile."

### `GenAIFeedback_dlm`

| Source field   | SDM `apiName` | Notes                                              |
| -------------- | ------------- | -------------------------------------------------- |
| `userId__c`    | `User_Id1`    | Suffix 1; collides with GatewayRequest's `User_Id` |
| `timestamp__c` | `Timestamp3`  | Suffix 3                                           |

### `GenAIContentQuality_dlm`

| Source field                | SDM `apiName`           | Notes                                       |
| --------------------------- | ----------------------- | ------------------------------------------- |
| `isToxicityDetected__c`     | `Is_Toxicity_Detected`  | Use this — `isToxic__c` does NOT exist      |
| `feature__c`                | `Feature4`              | Suffix 4                                    |
| `timestamp__c`              | `Timestamp6`            | Suffix 6                                    |

---

## Calc-field expression reference syntax

Per the `tableau-semantic-authoring` skill:

- **Table fields** are qualified: `[GenAIGatewayRequest_dlm].[Total_Tokens]`
- **Calc fields** are unqualified: `[Total_Tokens_clc]`
- Aggregation hint: `UserAgg` when the expression already contains aggregation
  functions (`SUM`, `COUNT`, `COUNTD`); `Sum` / `Avg` / etc. when the expression
  is a raw measure reference.

Example — Distinct Active Users:

```
COUNTD([GenAIGatewayRequest_dlm].[User_Id])
aggregation: UserAgg
```

Example — Adoption Rate (calc-field reference, no table qualification):

```
[Distinct_Active_Users_clc] / [Distinct_Entitled_Users_clc]
aggregation: UserAgg
```

---

## What's NOT in the SDM (and why it matters)

| Concept                 | Reason                                         | Workaround                                       |
| ----------------------- | ---------------------------------------------- | ------------------------------------------------ |
| `PermissionSetAssignment` | Not provisioned in cvk-dev Data Cloud         | Compute "entitled users" in Apex (`EntitlementService`) — agent action only |
| `IsActive` on User      | Not projected by `ssot__User__dlm`             | Drop the filter from viz_specs                   |
| `Profile` (sObject)     | User DMO doesn't carry Profile                 | Use `Title` as the categorical dimension         |
| `isToxic__c` on Feedback | Field doesn't exist; `isToxicityDetected__c` lives on `GenAIContentQuality_dlm` | Reference `Is_Toxicity_Detected` on `GenAIContentQuality_dlm` |

This means **`Distinct_Entitled_Users_clc` / `Adoption_Rate_clc` cannot be
computed in the SDM** in cvk-dev — there is no entitled-users denominator
available. Adoption KPIs are surfaced via the `GetEntitlementSnapshotAction`
agent action instead. The dashboard layer falls back to "Distinct Active Users"
as the headline KPI.
