# DATA-MODEL.md — DMO Schema Reference & Query Patterns

> ⚠️ **`live-schema.md` is authoritative.** This document captures the original design intent and query patterns. Verified field names from `cvk-dev` live at [../Developer/live-schema.md](../Developer/live-schema.md). Where this file uses PascalCase fields like `UserId__c` or `CreatedDate__c`, the live schema uses camelCase (`userId__c`, `timestamp__c`). Trust the live schema for query authoring; trust this doc for design rationale.

## Naming Conventions

Data Cloud DMOs follow specific naming rules:
- **DMO names** are appended with `__dlm` (e.g., `GenAIGatewayRequest__dlm`)
- **Field names** are appended with `__c` (e.g., `UserId__c`, `InputPrompt__c`)
- When querying via SOQL in Apex, use these full suffixed names
- When querying via Data Cloud SQL (Query Editor), the same suffixes apply

## DMO Relationship Map

```
GenAIGatewayRequest__dlm (1)
├──► GenAIGatewayRequestTags__dlm (N)    [parent → request ID]
│    └── Contains: prompt_template_dev_name, feature name, org settings
│
├──► GenAIGatewayResponse__dlm (1)       [request → response]
│    └──► GenAIGeneration__dlm (1..N)    [response → generations]
│         │
│         ├──► GenAIContentQuality__dlm (0..1)  [generation → quality summary]
│         │    └──► GenAIContentCategory__dlm (1..8) [quality → category scores]
│         │
│         ├──► GenAIFeedback__dlm (0..N)        [generation → feedback]
│         │    └──► GenAIFeedbackDetail__dlm (0..N) [feedback → details]
│         │
│         └──► GenAIAppGeneration__dlm (0..N)   [generation → app transforms]
```

## DMO Field Reference

### GenAIGatewayRequest__dlm (Core Request)

| Field | Type | Description | Use For |
|---|---|---|---|
| `Id` | ID | Primary key | Joining to responses, tags |
| `UserId__c` | String | Salesforce User ID of requester | User adoption analysis, resolve to User.Name |
| `InputPrompt__c` | Text | The prompt text sent to LLM | Prompt analysis, output inspection |
| `ModelName__c` | String | LLM model used (e.g., gpt-4) | Model usage breakdown |
| `Feature__c` | String | Feature that triggered request | Feature-level analytics |
| `CreatedDate__c` | DateTime | When request was made | Date range filtering, trend analysis |
| `InputTokenCount__c` | Number | Tokens in input | Token consumption tracking |
| `Status__c` | String | Request status | Error rate calculation |

### GenAIGatewayRequestTags__dlm (Request Metadata Tags)

| Field | Type | Description | Use For |
|---|---|---|---|
| `Id` | ID | Primary key | — |
| `Parent__c` | Reference | FK to GenAIGatewayRequest | Joining tags to requests |
| `TagName__c` | String | Tag key name | Filtering by tag type |
| `TagValue__c` | String | Tag value | Extracting prompt template names, feature flags |

**Important tag keys to filter on:**
- `prompt_template_dev_name` — Developer name of the Prompt Builder template
- `org_has_ai_trust_pii_masking_enabled` — Whether PII masking is on
- `org_has_ai_trust_perms` — Whether trust permissions are configured

### GenAIGatewayResponse__dlm (LLM Response)

| Field | Type | Description | Use For |
|---|---|---|---|
| `Id` | ID | Primary key | — |
| `RequestId__c` | Reference | FK to GenAIGatewayRequest | Joining response to request |
| `OutputTokenCount__c` | Number | Tokens in output | Token consumption tracking |
| `ResponseTimestamp__c` | DateTime | When response was received | Latency calculation |

### GenAIGeneration__dlm (Generated Output)

| Field | Type | Description | Use For |
|---|---|---|---|
| `Id` | ID | Primary key | Joining to feedback, content quality |
| `ResponseId__c` | Reference | FK to GenAIGatewayResponse | — |
| `GeneratedText__c` | LongText | The actual LLM output text | Output inspection, prompt QA |
| `GenerationIndex__c` | Number | Index if multiple generations | Multi-generation analysis |

### GenAIContentQuality__dlm (Safety Summary)

| Field | Type | Description | Use For |
|---|---|---|---|
| `Id` | ID | Primary key | — |
| `GenerationId__c` | Reference | FK to GenAIGeneration | — |
| `IsToxic__c` | Boolean | Overall toxicity flag | Safety overview dashboard |

### GenAIContentCategory__dlm (Detailed Safety Scores)

| Field | Type | Description | Use For |
|---|---|---|---|
| `Id` | ID | Primary key | — |
| `ContentQualityId__c` | Reference | FK to GenAIContentQuality | — |
| `CategoryName__c` | String | Safety category name | Category-level safety analysis |
| `Score__c` | Number(3,2) | Score 0.0–1.0 (higher = more likely) | Threshold-based alerting |

**8 Safety Categories:** Toxicity, Hate, Identity, Violence, Physical, Sexual, Profanity, Biased

### GenAIFeedback__dlm (User Feedback)

| Field | Type | Description | Use For |
|---|---|---|---|
| `Id` | ID | Primary key | — |
| `GenerationId__c` | Reference | FK to GenAIGeneration | — |
| `FeedbackType__c` | String | Type: explicit or implicit | Feedback analysis |
| `FeedbackValue__c` | String | E.g., thumbs_up, thumbs_down, accepted, edited, rejected | Acceptance rate, satisfaction |
| `FeedbackTimestamp__c` | DateTime | When feedback was given | Feedback latency |
| `UserId__c` | String | User who gave feedback | May differ from requester |

### GenAIFeedbackDetail__dlm (Feedback Details)

| Field | Type | Description | Use For |
|---|---|---|---|
| `Id` | ID | Primary key | — |
| `FeedbackId__c` | Reference | FK to GenAIFeedback | — |
| `ActionType__c` | String | What the user did (edit, copy, etc.) | Detailed behavior analysis |
| `Notes__c` | Text | Free-text feedback notes | Qualitative analysis |

### GenAIAppGeneration__dlm (App-Level Transforms)

| Field | Type | Description | Use For |
|---|---|---|---|
| `Id` | ID | Primary key | — |
| `GenerationId__c` | Reference | FK to GenAIGeneration | — |
| `GenerationUpdateId__c` | String | ID of the transformed version | — |
| `GenerationUpdate__c` | LongText | The transformed text | Comparing raw vs. transformed output |

## Standard Salesforce Objects Used

### User (for ID resolution)

| Field | Use |
|---|---|
| `Id` | Match to `UserId__c` from DMOs |
| `Name` | Display name in dashboards |
| `Profile.Name` | Optional: group usage by profile |
| `UserRole.Name` | Optional: group usage by role |
| `Department` | Optional: group usage by department |
| `IsActive` | Filter out deactivated users |

### GenAiPromptTemplate (if accessible via SOQL)

| Field | Use |
|---|---|
| `DeveloperName` | Match to `prompt_template_dev_name` tag value |
| `MasterLabel` | Human-readable prompt template name |
| `Description` | Optional: show in prompt detail view |

**Note:** GenAiPromptTemplate may not be queryable via standard SOQL in all orgs. Fallback: use the developer name from the tag as-is (it's often readable enough, e.g., `Generate_Sales_Email`).

## Core Query Patterns

### Pattern 1: Usage by User (with name resolution)

```sql
-- Step 1: Get requests grouped by user
SELECT UserId__c, COUNT(Id) requestCount, 
       MIN(CreatedDate__c) firstUse, MAX(CreatedDate__c) lastUse
FROM GenAIGatewayRequest__dlm
WHERE CreatedDate__c >= :startDate AND CreatedDate__c <= :endDate
GROUP BY UserId__c
ORDER BY COUNT(Id) DESC

-- Step 2: Resolve user IDs (standard SOQL)
SELECT Id, Name, Profile.Name, Department
FROM User
WHERE Id IN :userIds
```

### Pattern 2: Usage by Prompt Template

```sql
-- Step 1: Get prompt template names from tags
SELECT Parent__c, TagValue__c
FROM GenAIGatewayRequestTags__dlm
WHERE TagName__c LIKE 'prompt_template_dev_name'

-- Step 2: Group requests by template, join with feedback
-- (done in Apex after retrieving both datasets)
```

### Pattern 3: Token Consumption

```sql
-- Requests with token counts
SELECT Id, UserId__c, InputTokenCount__c, CreatedDate__c
FROM GenAIGatewayRequest__dlm
WHERE CreatedDate__c >= :startDate AND CreatedDate__c <= :endDate

-- Responses with output token counts
SELECT RequestId__c, OutputTokenCount__c
FROM GenAIGatewayResponse__dlm
WHERE RequestId__c IN :requestIds
```

### Pattern 4: Feedback Analysis

```sql
-- Get feedback for a date range (join through generation → response → request)
SELECT Id, GenerationId__c, FeedbackType__c, FeedbackValue__c, UserId__c
FROM GenAIFeedback__dlm
WHERE FeedbackTimestamp__c >= :startDate AND FeedbackTimestamp__c <= :endDate
```

### Pattern 5: Safety/Content Quality

```sql
-- Toxic content flags
SELECT GenerationId__c, IsToxic__c
FROM GenAIContentQuality__dlm
WHERE IsToxic__c = true

-- Detailed category scores above threshold
SELECT ContentQualityId__c, CategoryName__c, Score__c
FROM GenAIContentCategory__dlm
WHERE Score__c > 0.7
```

## SOQL-on-DMO Considerations

Known limitations when querying Data Cloud DMOs via Apex SOQL:

1. **Aggregate queries** — `GROUP BY` and aggregate functions may have limitations on DMOs. Test early. If blocked, aggregate in Apex code instead.
2. **Relationship queries** — Parent-child subqueries (e.g., `SELECT Id, (SELECT ... FROM ...)`) may not work on DMOs. Use separate queries and join in Apex.
3. **LIKE operator** — Use `LIKE` instead of `=` for text comparisons on DMO fields (per Salesforce recommendation).
4. **Query limits** — Standard SOQL governor limits apply. DMO queries also have Data Cloud-specific limits.
5. **Date filtering** — Always filter by date to avoid scanning the full dataset. Data is retained per org's retention policy.

## Fallback: Data Cloud Connect REST API

If SOQL on DMOs proves too limited for a specific query, use the Data Cloud Connect REST API from Apex:

```
POST /services/data/v62.0/ssot/queryV2
Content-Type: application/json

{
  "sql": "SELECT ... FROM GenAIGatewayRequest__dlm WHERE ..."
}
```

This supports full ANSI SQL including complex joins, aggregations, and subqueries. The tradeoff is it counts as an HTTP callout and has different governor limits.
