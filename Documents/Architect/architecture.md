# ARCHITECTURE.md — System Architecture

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                    Lightning App                         │
│                  "AI Insights Hub"                       │
│                                                         │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌───────────┐  │
│  │ Overview  │ │  User    │ │  Prompt  │ │  Safety   │  │
│  │Dashboard  │ │Adoption  │ │Analytics │ │ & Trust   │  │
│  │  (LWC)   │ │  (LWC)   │ │  (LWC)   │ │  (LWC)    │  │
│  └────┬─────┘ └────┬─────┘ └────┬─────┘ └─────┬─────┘  │
│       │             │            │              │        │
│  ┌────▼─────────────▼────────────▼──────────────▼─────┐  │
│  │            AiInsightsController.cls                 │  │
│  │         (@AuraEnabled Apex Controller)              │  │
│  └────────────────────┬───────────────────────────────┘  │
│                       │                                  │
│  ┌────────────────────▼───────────────────────────────┐  │
│  │           AiInsightsService.cls                     │  │
│  │    (Business logic, aggregation, ID resolution)     │  │
│  └──┬───────────────┬─────────────────┬──────────────┬─┘  │
│     │               │                 │              │    │
│  ┌──▼─────────┐ ┌──▼──────────────┐ ┌▼────────────┐ ┌▼──────────────┐
│  │AiInsights  │ │UserResolver     │ │Cost         │ │Entitlement   │
│  │DAO.cls     │ │Service.cls      │ │Calculator   │ │Service.cls   │
│  │(DMO SOQL)  │ │(User + Prompt   │ │Service.cls  │ │(PSA/PSG/     │
│  │            │ │ name cache)     │ │(FC + Wallet)│ │ Profile      │
│  │            │ │                 │ │             │ │ resolver)    │
│  └──┬─────────┘ └─────────────────┘ └──┬──────────┘ └──┬───────────┘
│     │                                  │               │            │
└─────┼──────────────────────────────────┼───────────────┼────────────┘
      │                                  │               │
   ┌──▼────────────────┐  ┌──────────────▼────┐  ┌──────▼──────────────┐
   │   Data Cloud       │  │   Digital Wallet   │  │   Standard          │
   │   DMOs (__dlm)     │  │   DLO (__dll)      │  │   Salesforce        │
   │                    │  │                    │  │   Objects           │
   │ GenAIGateway       │  │ TenantEnriched     │  │ User                │
   │   Request          │  │   UsageEvent__dll  │  │ Profile             │
   │ GenAIGateway       │  │                    │  │ PermissionSet       │
   │   RequestTags      │  │                    │  │ PermissionSetGroup  │
   │ GenAIGateway       │  │                    │  │ PermissionSet       │
   │   Response         │  │                    │  │   Assignment        │
   │ GenAIGeneration    │  │                    │  │ GenAiPromptTemplate │
   │ GenAIContentQual   │  │                    │  │   (if accessible)   │
   │ GenAIContentCat    │  │                    │  │                     │
   │ GenAIFeedback      │  │                    │  │                     │
   │ GenAIFeedback      │  │                    │  │                     │
   │   Detail           │  │                    │  │                     │
   │ GenAIApp           │  │                    │  │                     │
   │   Generation       │  │                    │  │                     │
   └────────────────────┘  └────────────────────┘  └─────────────────────┘
```

## Layer Responsibilities

### Layer 1: Lightning Web Components (Presentation)

Each LWC is a self-contained dashboard widget. They:
- Call `@AuraEnabled` methods on the controller
- Handle loading states, empty states, and errors
- Use SLDS (Salesforce Lightning Design System) for styling
- Are composable — the main App Page arranges them in a grid

LWC components do NOT contain business logic or query logic. They receive data and render it.

### Layer 2: AiInsightsController.cls (Apex Controller)

Thin controller layer that:
- Exposes `@AuraEnabled(cacheable=true)` methods for read operations
- Handles parameter validation and error wrapping
- Delegates all logic to the service layer
- Returns wrapper classes (inner classes or separate DTOs) not raw SObjects

### Layer 3: AiInsightsService.cls (Business Logic)

The core of the application. This layer:
- Orchestrates queries across the DAO and UserResolver
- Performs aggregation, grouping, and percentage calculations
- Merges DMO data with resolved names
- Handles date range filtering
- Contains all "intelligence" — what to count, how to calculate adoption rates, etc.

### Layer 4: AiInsightsDAO.cls (Data Access)

Pure data access — SOQL queries against Data Cloud DMOs. This layer:
- Encapsulates all `__dlm` and `__c` syntax
- Returns raw query results
- Handles SOQL-on-DMO quirks (field availability, query limitations)
- If a query hits DMO SOQL limitations, falls back to Data Cloud Connect REST API

### Layer 4c: AiWalletDAO.cls (Digital Wallet Data Access)

Sibling to `AiInsightsDAO`, isolated to Salesforce Digital Wallet's Consumption
Tagging objects (`TenantEnrichedUsageEvent__dll` and the Consumption Insights
DMO/SDM). This layer:
- Probes availability via `isWalletAvailable()` — every method short-circuits
  to empty/null when the DLO is missing (sandbox / scratch / non-Wallet org)
- Centralises every Wallet field name as a `@TestVisible private static final`
  constant so a future schema change touches one block
- Aggregates by user, prompt (resource), feature, usage type, and the
  JSON-encoded `resourcetags__c` custom-tag column
- Never throws — every Wallet query is wrapped in try/catch

`CostCalculatorService` uses this DAO via constructor injection; production
uses the live `AiWalletDAO`, tests inject `AiWalletDAOMock`. When
`Enable_Wallet_Costs__c` is true AND `isWalletAvailable() == true`, the
service treats Wallet as authoritative and renders headline cost figures with
the **`ACTUAL`** confidence badge. Otherwise it falls back to the existing
tier-rate estimate. See [../Developer/wallet-live-schema.md](../Developer/wallet-live-schema.md) for the verified
schema and the prod-only constraint disclaimer.

### Layer 4d: EntitlementService.cls (Adoption Denominator)

Resolves the **entitled-user denominator** for adoption analytics. Reads
enabled rows from `FluentMetric_Entitlement_PermissionSet__mdt`, buckets
them by `Entitlement_Type__c` (`PermissionSet` / `PermissionSetGroup` /
`Profile`), and routes each bucket to the right query path:

- **PermissionSet** → `PermissionSet.Name` + `PermissionSetAssignment.PermissionSetId`
- **PermissionSetGroup** → `PermissionSetGroup.DeveloperName` + `PermissionSetAssignment.PermissionSetGroupId` (PSA exposes PSG membership directly)
- **Profile** → `Profile.Name` + `User.ProfileId`

The entitled-user set is the union across all enabled rows, deduplicated by
user Id. Active-only filtering: PSA `(ExpirationDate = NULL OR >= TODAY)` +
`Assignee.IsActive = TRUE`; profile path filters `User.IsActive = TRUE`.

`getSnapshot(activeUserIds)` returns counts plus `adoptionRate = (active ∩
entitled) / entitled`, bounded to [0, 1.0]. Any failure mode (CMT empty,
zero matching names in org, query exception, FLS) flips
`entitledFallback = true` and the denominator silently switches to "all
active org users" so dashboards never break. Results are cached in static
transaction-scoped fields — Platform Cache is intentionally avoided because
PSA/Profile writes have no event hook to invalidate the entry.

`AiInsightsService` accepts an `IEntitlementService` via constructor
injection; tests use `EntitlementServiceMock` for deterministic snapshots.

### Layer 4b: UserResolverService.cls (Reference Data)

Resolves IDs and developer names to human-readable values:
- User ID → User.Name (via standard SOQL on User object)
- Prompt template developer name → label (via GenAiPromptTemplate or request tags)
- Uses Platform Cache (org partition) to avoid repeated lookups
- Cache TTL: 1 hour for user names, 4 hours for prompt template names

## Data Flow Example: "Show me usage by user"

```
1. User selects date range in LWC
2. LWC calls AiInsightsController.getUsageByUser(startDate, endDate)
3. Controller validates dates, calls AiInsightsService.getUsageByUser(...)
4. Service calls AiInsightsDAO.getRequestsByDateRange(startDate, endDate)
   → SOQL on GenAIGatewayRequest__dlm with date filter
   → Returns list of requests with UserId__c, timestamps
5. Service calls AiInsightsDAO.getFeedbackForRequests(requestIds)
   → SOQL on GenAIFeedback__dlm filtered by parent request IDs
6. Service extracts unique User IDs, calls UserResolverService.resolveUsers(userIds)
   → Checks Platform Cache first
   → Cache miss: SOQL on User WHERE Id IN :userIds
   → Caches results, returns Map<Id, String>
7. Service aggregates: group by user, count requests, calculate feedback ratios
8. Service returns List<UserUsageDTO> with resolved names
9. Controller returns to LWC
10. LWC renders sortable table
```

## Key Architectural Decisions

### Why not CRM Analytics / Tableau?

- Not all target orgs have CRM Analytics licenses
- CRM Analytics dashboards require their own learning curve to customize
- LWC gives us full control over UX and is universally available
- Package installation is simpler (no dataset/recipe/dashboard dependencies)

### Why Apex SOQL on DMOs instead of Data Cloud Connect REST API?

- SOQL is simpler, fewer moving parts, runs in same transaction context
- Respects org permissions and sharing automatically
- No HTTP callout limits to worry about for basic queries
- Fallback to REST API only where SOQL on DMOs has proven limitations

### Why Platform Cache for name resolution?

- User names and prompt template names change rarely
- Without cache, every dashboard load would trigger N+1 queries on User
- Org partition cache is available in all Enterprise+ orgs
- Graceful degradation: if cache is unavailable, queries still work (just slower)

### Why separate DAO from Service?

- Testability: DAO can be mocked in unit tests without needing Data Cloud
- If SOQL-on-DMO syntax changes, only DAO is affected
- Clean separation makes it easy to swap to REST API for specific queries
- Service tests focus on business logic, not query syntax

## Error Handling Strategy

Data Cloud DMOs may not be populated if Audit & Feedback is not enabled, or if the org has no AI usage yet. The app must handle:

| Scenario | Handling |
|---|---|
| DMO query returns empty | LWC shows friendly "No data yet" empty state with setup guidance |
| DMO query throws exception (permissions) | Controller catches, returns structured error, LWC shows "Check permissions" message |
| User ID not found in User object | UserResolver returns "Unknown User (ID)" as fallback |
| Data Cloud not enabled | Preflight check on app load; show setup instructions if missing |
| Platform Cache not available | Graceful fallback to uncached queries; log warning |

## Security Considerations

- All data access goes through Apex — enforced by Salesforce sharing and FLS
- Data Cloud DMOs enforce dataspace and governance rules based on running user context
- No client-side direct API calls to Data Cloud
- Permission Set controls who can access the Lightning App
- No sensitive data is cached — only User.Name and prompt template labels
