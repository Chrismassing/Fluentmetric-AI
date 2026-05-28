# LIVE-SCHEMA.md — Verified DMO Schema (overrides Architect/data-model.md where they disagree)

**Source:** `sf sobject describe` against `cvk-dev` org on 2026-04-29. When this doc contradicts [../Architect/data-model.md](../Architect/data-model.md), **trust this doc** — the original was written from Salesforce's help article, which uses descriptive PascalCase names. The live platform uses camelCase.

## Naming Conventions — LIVE

- DMO object names still use `__dlm` suffix: ✅ same as docs
- **Field names are camelCase** (`userId__c`, `prompt__c`, `timestamp__c`), NOT PascalCase
- Relationship fields use generated names like `rel_1776753306938_end__c` — **don't use these for joins**. Join in Apex using business keys (`generationRequestId__c`, `parent__c`, `generationId__c`).
- There is a parallel `_std__dlm` schema (e.g. `GenAiGatewayRequest_std__dlm`) alongside the classic `__dlm`. **We use the classic `__dlm` set** because it has populated data in `cvk-dev` and matches Salesforce's public help docs. A later version may support both.

## GenAIGatewayRequest__dlm (Core Request — 31 fields)

| Live field | Type | Purpose |
|---|---|---|
| `Id` | id | Primary key |
| `gatewayRequestId__c` | string | Business key for joining to Response |
| `userId__c` | string | Salesforce User ID. **Note:** sentinel value `NOT_SET` for system calls |
| `orgId__c` | string | Originating org |
| `prompt__c` | string | Prompt text sent to LLM |
| `maskedPrompt__c` | string | PII-masked version (if PII masking enabled) |
| `model__c` | string | LLM model (e.g., `gpt-4.1-2025-04-14`, `EinsteinHyperClassifier`) |
| `provider__c` | string | LLM provider (OpenAI, Anthropic, etc.) |
| `feature__c` | string | Feature that invoked the request (e.g., `plannerservice`) |
| `appType__c` | string | App type |
| `promptTemplateDevName__c` | string | **Prompt Builder template dev name — directly on the Request row (no tag join needed)** |
| `promptTemplateVersionNo__c` | string | Template version |
| `timestamp__c` | datetime | Request time — **use this for date filters, not `CreatedDate__c`** |
| `promptTokens__c` | double | Input tokens |
| `completionTokens__c` | double | Output tokens |
| `totalTokens__c` | double | Sum (Request row already has aggregate tokens — no Response join needed) |
| `numGenerations__c` | double | Number of generations produced |
| `sessionId__c` | string | Session ID for multi-turn |
| `botVersionId__c` | string | Agentforce bot version, if applicable |
| `plannerId__c` | string | Agentforce planner ID, if applicable |
| `generationGroupId__c` | string | Groups related generations |
| `temperature__c`, `frequencyPenalty__c`, `presencePenalty__c`, `parameters__c`, `stopSequences__c` | — | LLM params |
| `enablePiiMasking__c`, `enableInputSafetyScoring__c`, `enableOutputSafetyScoring__c` | string | Trust/safety settings (string-encoded booleans) |
| `cloud__c` | string | Cloud identifier |

## GenAIGatewayResponse__dlm

| Live field | Type | Purpose |
|---|---|---|
| `Id` | id | Primary key |
| `generationResponseId__c` | string | Business key |
| `generationRequestId__c` | string | FK to Request (match to `gatewayRequestId__c`) |
| `timestamp__c` | datetime | Response time (for latency calc) |
| `parameters__c`, `orgId__c`, `cloud__c` | — | Metadata |

**Note:** Unlike the docs, there are **no token fields here** — token counts are on the Request row. This simplifies the DAO.

## GenAIGeneration__dlm

| Live field | Type | Purpose |
|---|---|---|
| `Id` | id | Primary key |
| `generationId__c` | string | Business key |
| `generationResponseId__c` | string | FK to Response |
| `responseText__c` | string | Generated text |
| `maskedResponseText__c` | string | PII-masked version |
| `feature__c` | string | Feature that produced generation |
| `responseParameters__c`, `timestamp__c`, `orgId__c`, `cloud__c` | — | Metadata |

## GenAIGatewayRequestTag__dlm (singular, not plural)

| Live field | Type | Purpose |
|---|---|---|
| `Id` | id | Primary key |
| `parent__c` | string | FK to Request.gatewayRequestId |
| `tag__c` | string | Tag key |
| `tagValue__c` | string | Tag value |
| `timestamp__c`, `orgId__c`, `cloud__c` | — | Metadata |

**Note:** Because `promptTemplateDevName__c` is already on the Request row, we don't need this table for prompt name resolution. Keep it available for other tag-driven analytics (e.g., feature flags).

## GenAIFeedback__dlm

| Live field | Type | Purpose |
|---|---|---|
| `Id` | id | Primary key |
| `feedbackId__c` | string | Business key |
| `generationId__c` | string | FK to Generation |
| `generationUpdateId__c` | string | FK to app-transformed generation |
| `userId__c` | string | Feedback author |
| `feedback__c` | string | The feedback value (e.g., `thumbs_up`, `thumbs_down`) |
| `action__c` | string | What the user did (`accepted`, `edited`, `rejected`) |
| `source__c` | string | Where feedback came from (explicit UI, implicit signal) |
| `feature__c`, `appType__c`, `generationGroupId__c` | — | Dimension fields |
| `timestamp__c`, `orgId__c`, `cloud__c` | — | Metadata |

## GenAIFeedbackDetail__dlm

| Live field | Type | Purpose |
|---|---|---|
| `Id` | id | Primary key |
| `feedbackDetailId__c` | string | Business key |
| `parent__c` | string | FK to Feedback.feedbackId |
| `appFeedback__c`, `feedbackText__c` | string | Qualitative notes |
| `feature__c`, `timestamp__c`, `orgId__c`, `cloud__c` | — | Metadata |

## GenAIContentQuality__dlm

| Live field | Type | Purpose |
|---|---|---|
| `Id` | id | Primary key |
| `id__c` | string | Business key |
| `parent__c` | string | FK to Generation.generationId |
| `isToxicityDetected__c` | **string** (not boolean) | `"true"` / `"false"` — parse in Apex |
| `contentType__c` | string | Content classification |
| `feature__c`, `timestamp__c`, `orgId__c`, `cloud__c` | — | Metadata |

## GenAIContentCategory__dlm

| Live field | Type | Purpose |
|---|---|---|
| `Id` | id | Primary key |
| `id__c` | string | Business key |
| `parent__c` | string | FK to ContentQuality.id |
| `category__c` | string | Category name (Toxicity, Hate, Violence, etc.) |
| `value__c` | string | **String-encoded score** — parse to Decimal in Apex |
| `detectorType__c` | string | Which safety model detected |
| `timestamp__c`, `orgId__c`, `cloud__c` | — | Metadata |

## Join Strategy (live, verified)

```
GenAIGatewayRequest__dlm
   .gatewayRequestId__c  ←→  GenAIGatewayResponse__dlm.generationRequestId__c
                                   .generationResponseId__c  ←→  GenAIGeneration__dlm.generationResponseId__c
                                                                     .generationId__c  ←→  GenAIFeedback__dlm.generationId__c
                                                                     .generationId__c  ←→  GenAIContentQuality__dlm.parent__c
                                                                                              .id__c  ←→  GenAIContentCategory__dlm.parent__c

GenAIFeedback__dlm.feedbackId__c  ←→  GenAIFeedbackDetail__dlm.parent__c
GenAIGatewayRequest__dlm.gatewayRequestId__c  ←→  GenAIGatewayRequestTag__dlm.parent__c
```

All joins use business-key string FKs. Do **not** try parent-child SOQL subqueries on DMOs — they use generated relationship names and will break across orgs.

## Verified Query Patterns

### Count by user (works)

```sql
SELECT userId__c, COUNT(Id) cnt
FROM GenAIGatewayRequest__dlm
WHERE timestamp__c >= LAST_N_DAYS:90
GROUP BY userId__c
LIMIT 5
```

### Gotchas

1. **Cannot `ORDER BY COUNT(Id)`** — error: "field 'Id' can not be sorted in a query call". **Sort in Apex after fetch.**
2. `ORDER BY` on non-aggregate fields works, but keep queries small and always date-filter.
3. `userId__c` contains the sentinel `"NOT_SET"` for system calls — treat as its own "System" bucket, don't resolve via User SOQL.
4. Token fields (`promptTokens__c`, `completionTokens__c`, `totalTokens__c`) are `double` — cast to `Long` or `Decimal` in Apex; null-coalesce for records that pre-date those fields.
5. Boolean-like fields (`isToxicityDetected__c`, `enablePiiMasking__c`) are returned as `string` — parse with `'true'.equalsIgnoreCase(value)`.
6. Safety category `value__c` is `string` — parse with `Decimal.valueOf(value)` inside try/catch.
