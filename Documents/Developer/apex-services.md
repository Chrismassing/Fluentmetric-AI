# APEX-SERVICES.md — Apex Service Layer Design

## Class Structure

```
force-app/main/default/classes/
├── controllers/
│   └── AiInsightsController.cls          // @AuraEnabled methods for LWC
├── services/
│   ├── AiInsightsService.cls             // Business logic and orchestration
│   ├── UserResolverService.cls           // ID→Name resolution with caching
│   ├── CostCalculatorService.cls         // FC/USD with Wallet-actual override
│   ├── IEntitlementService.cls           // Entitled-denominator interface
│   ├── EntitlementService.cls            // PS/PSG/Profile resolver
│   └── EntitlementServiceMock.cls        // Deterministic test snapshot
├── dao/
│   ├── IAiInsightsDAO.cls                // DAO interface (mockable)
│   ├── AiInsightsDAO.cls                 // All DMO SOQL queries
│   ├── AiInsightsDAOMock.cls             // Hand-crafted SObject lists for tests
│   ├── IAiWalletDAO.cls                  // Wallet DAO interface
│   ├── AiWalletDAO.cls                   // TenantEnrichedUsageEvent__dll queries
│   └── AiWalletDAOMock.cls               // Wallet test double
├── dto/
│   ├── UsageOverviewDTO.cls              // Summary metrics + adoption fields
│   ├── UserUsageDTO.cls                  // Per-user usage data
│   ├── PromptUsageDTO.cls                // Per-prompt usage data
│   ├── PromptOutputDTO.cls               // Individual prompt outputs
│   ├── TokenConsumptionDTO.cls           // Token usage data
│   ├── ContentSafetyDTO.cls              // Safety/quality data
│   ├── OverviewTrendsDTO.cls             // Trend lines + weekly trend
│   ├── EntitlementSnapshotDTO.cls        // Adoption funnel data
│   ├── AdoptionCohortsDTO.cls            // Cohort retention matrix (≤26 wks)
│   ├── OrgAdoptionDeltasDTO.cls          // 8-week trailing WoW deltas
│   ├── PowerUserSegmentsDTO.cls          // Pareto buckets (top10%/top1%)
│   ├── FeatureAdoptionDTO.cls            // Per-feature breadth/depth
│   └── DateRangeFilter.cls               // Reusable date range input
└── tests/
    ├── AiInsightsControllerTest.cls
    ├── AiInsightsServiceTest.cls
    ├── AiInsightsDAOTest.cls
    ├── EntitlementServiceTest.cls
    ├── CostCalculatorServiceTest.cls
    └── UserResolverServiceTest.cls
```

## DTO Definitions

### DateRangeFilter

```apex
public class DateRangeFilter {
    @AuraEnabled public DateTime startDate;
    @AuraEnabled public DateTime endDate;

    public DateRangeFilter(DateTime startDate, DateTime endDate) {
        this.startDate = startDate;
        this.endDate = endDate;
    }

    // Convenience: last N days
    public static DateRangeFilter lastNDays(Integer n) {
        return new DateRangeFilter(
            DateTime.now().addDays(-n),
            DateTime.now()
        );
    }
}
```

### UsageOverviewDTO

```apex
public class UsageOverviewDTO {
    @AuraEnabled public Integer totalRequests;
    @AuraEnabled public Integer uniqueUsers;
    @AuraEnabled public Integer uniquePromptTemplates;
    @AuraEnabled public Decimal acceptanceRate;       // % of feedback = thumbs_up or accepted
    @AuraEnabled public Long totalInputTokens;
    @AuraEnabled public Long totalOutputTokens;
    @AuraEnabled public Integer toxicFlagCount;
    @AuraEnabled public Integer feedbackCount;
    @AuraEnabled public String dateRangeLabel;        // e.g., "Last 30 days"
    // Adoption (Phase 1) — populated by EntitlementService.getSnapshot()
    @AuraEnabled public Integer entitledUserCount;    // Users assigned to a configured PS / PSG / Profile
    @AuraEnabled public Integer totalActiveOrgUsers;  // Fallback denominator
    @AuraEnabled public Decimal adoptionRate;         // (active ∩ entitled) / entitled, [0, 1]
    @AuraEnabled public Boolean entitledFallback;     // true ⇒ denominator is "all active users"
    // WoW deltas
    @AuraEnabled public Decimal requestsWowPct;
    @AuraEnabled public Decimal usersWowPct;
    @AuraEnabled public Decimal tokensWowPct;
}
```

### EntitlementSnapshotDTO

```apex
public class EntitlementSnapshotDTO {
    @AuraEnabled public Integer entitledCount;
    @AuraEnabled public Integer activeCount;
    @AuraEnabled public Integer totalActiveOrgUsers;
    @AuraEnabled public Integer unmatchedActiveCount; // Active users not in entitled set
    @AuraEnabled public Decimal adoptionRate;         // (active ∩ entitled) / entitled
    @AuraEnabled public Boolean entitledFallback;
    @AuraEnabled public List<String> configuredPermissionSets;
}
```

### AdoptionCohortsDTO

```apex
public class AdoptionCohortsDTO {
    public static final Integer MAX_COHORT_WEEKS = 26;
    @AuraEnabled public List<CohortRow> rows;
    @AuraEnabled public Boolean truncated;            // true if 50k row cap was hit

    public class CohortRow {
        @AuraEnabled public String weekIsoLabel;      // e.g. "2026-W18"
        @AuraEnabled public Date weekStart;
        @AuraEnabled public Integer cohortSize;
        @AuraEnabled public Integer ageInWeeks;
        @AuraEnabled public List<Decimal> retentionByWeek; // [0..1] per age-week
    }
}
```

### OrgAdoptionDeltasDTO

```apex
public class OrgAdoptionDeltasDTO {
    @AuraEnabled public List<WeekDelta> weeks;        // 8 entries, oldest first
    @AuraEnabled public Decimal latestRequestsWowPct;
    @AuraEnabled public Decimal latestUsersWowPct;
    @AuraEnabled public Decimal latestTokensWowPct;

    public class WeekDelta {
        @AuraEnabled public Date weekStart;
        @AuraEnabled public String weekIsoLabel;
        @AuraEnabled public Integer requests;
        @AuraEnabled public Integer activeUsers;
        @AuraEnabled public Long tokens;
        @AuraEnabled public Decimal requestsWowPct;
        @AuraEnabled public Decimal usersWowPct;
        @AuraEnabled public Decimal tokensWowPct;
    }
}
```

### PowerUserSegmentsDTO

```apex
public class PowerUserSegmentsDTO {
    @AuraEnabled public Decimal top10PercentVolumeShare; // 0..1
    @AuraEnabled public Decimal top1PercentVolumeShare;
    @AuraEnabled public Integer top10PercentUserCount;
    @AuraEnabled public Integer top1PercentUserCount;
    @AuraEnabled public List<TopUser> topUsers;       // Top-10% slice for drill

    public class TopUser {
        @AuraEnabled public Id userId;
        @AuraEnabled public String userName;
        @AuraEnabled public Integer requestCount;
        @AuraEnabled public Long totalTokens;
        @AuraEnabled public String tier;              // 'TOP_1' | 'TOP_10'
    }
}
```

### FeatureAdoptionDTO

```apex
public class FeatureAdoptionDTO {
    @AuraEnabled public String featureName;
    @AuraEnabled public Integer uniqueUserCount;
    @AuraEnabled public Integer repeatUserCount;      // ≥2 invocations in range
    @AuraEnabled public Decimal breadthRate;          // uniqueUsers / entitledCount
    @AuraEnabled public Decimal depthMedian;          // median invocations / user
    @AuraEnabled public DateTime firstObservedInOrg;
    @AuraEnabled public DateTime firstObservedInRange;
}
```

### UserUsageDTO

```apex
public class UserUsageDTO {
    @AuraEnabled public String userId;
    @AuraEnabled public String userName;              // Resolved from User object
    @AuraEnabled public String profileName;           // User.Profile.Name
    @AuraEnabled public String department;            // User.Department
    @AuraEnabled public Integer requestCount;
    @AuraEnabled public DateTime firstUsed;
    @AuraEnabled public DateTime lastUsed;
    @AuraEnabled public Integer positiveFeedbackCount;
    @AuraEnabled public Integer negativeFeedbackCount;
    @AuraEnabled public Decimal feedbackRatio;        // positive / total feedback
    @AuraEnabled public List<String> topPrompts;      // Top 3 prompt template names used
    @AuraEnabled public Long totalTokens;             // Input + output tokens
}
```

### PromptUsageDTO

```apex
public class PromptUsageDTO {
    @AuraEnabled public String promptDevName;
    @AuraEnabled public String promptLabel;           // Resolved from GenAiPromptTemplate or humanized dev name
    @AuraEnabled public String featureName;           // Feature that uses this prompt
    @AuraEnabled public Integer invocationCount;
    @AuraEnabled public Integer uniqueUserCount;
    @AuraEnabled public Decimal acceptanceRate;
    @AuraEnabled public Long avgInputTokens;
    @AuraEnabled public Long avgOutputTokens;
    @AuraEnabled public Long totalTokens;
    @AuraEnabled public Integer toxicFlagCount;
    @AuraEnabled public DateTime firstUsed;
    @AuraEnabled public DateTime lastUsed;
    // Adoption (Phase 1) — populated when entitlement snapshot is available
    @AuraEnabled public Decimal breadthRate;          // uniqueUsers / entitledCount
    @AuraEnabled public Integer repeatUserCount;
    @AuraEnabled public Decimal medianInvocationsPerUser;
    @AuraEnabled public DateTime firstObservedInOrg;  // unbounded MIN(timestamp__c)
    @AuraEnabled public String acceptanceSource;      // 'EXACT' | 'SAMPLED' | 'CORRELATED' | null
}
```

### PromptOutputDTO

```apex
public class PromptOutputDTO {
    @AuraEnabled public String requestId;
    @AuraEnabled public String userName;
    @AuraEnabled public DateTime requestDate;
    @AuraEnabled public String inputPrompt;           // Truncated for list view
    @AuraEnabled public String generatedText;         // Truncated for list view
    @AuraEnabled public String feedbackValue;         // thumbs_up, thumbs_down, etc.
    @AuraEnabled public Boolean isToxic;
    @AuraEnabled public Integer inputTokens;
    @AuraEnabled public Integer outputTokens;
}
```

### TokenConsumptionDTO

```apex
public class TokenConsumptionDTO {
    @AuraEnabled public String groupKey;              // Prompt name, user name, or date bucket
    @AuraEnabled public String groupLabel;            // Human-readable label
    @AuraEnabled public Long inputTokens;
    @AuraEnabled public Long outputTokens;
    @AuraEnabled public Long totalTokens;
    @AuraEnabled public Integer requestCount;
    @AuraEnabled public Decimal avgTokensPerRequest;
}
```

### ContentSafetyDTO

```apex
public class ContentSafetyDTO {
    @AuraEnabled public Integer totalGenerations;
    @AuraEnabled public Integer toxicCount;
    @AuraEnabled public Decimal toxicRate;            // toxicCount / totalGenerations
    @AuraEnabled public Map<String, Decimal> avgCategoryScores;  // category → avg score
    @AuraEnabled public Map<String, Integer> flaggedByCategory;  // category → count above threshold
    @AuraEnabled public List<PromptOutputDTO> recentFlaggedOutputs; // Last 10 flagged items
}
```

## Controller Methods

```apex
public with sharing class AiInsightsController {

    // ── Overview Dashboard ──
    @AuraEnabled(cacheable=true)
    public static UsageOverviewDTO getOverview(DateTime startDate, DateTime endDate) {
        // Validates dates, delegates to AiInsightsService.getOverview(...)
    }

    // ── User Adoption ──
    @AuraEnabled(cacheable=true)
    public static List<UserUsageDTO> getUsageByUser(DateTime startDate, DateTime endDate) {
        // Returns all users with AI usage, sorted by requestCount DESC
    }

    @AuraEnabled(cacheable=true)
    public static UserUsageDTO getUserDetail(String userId, DateTime startDate, DateTime endDate) {
        // Deep dive on a single user
    }

    // ── Prompt Analytics ──
    @AuraEnabled(cacheable=true)
    public static List<PromptUsageDTO> getUsageByPrompt(DateTime startDate, DateTime endDate) {
        // Returns all prompt templates with usage stats
    }

    @AuraEnabled(cacheable=true)
    public static List<PromptOutputDTO> getPromptOutputs(
        String promptDevName, DateTime startDate, DateTime endDate, Integer limitCount
    ) {
        // Returns recent outputs for a specific prompt template
    }

    // ── Token Consumption ──
    @AuraEnabled(cacheable=true)
    public static List<TokenConsumptionDTO> getTokenConsumption(
        DateTime startDate, DateTime endDate, String groupBy  // 'user', 'prompt', 'day', 'week'
    ) {
        // Token usage grouped by the specified dimension
    }

    // ── Safety & Trust ──
    @AuraEnabled(cacheable=true)
    public static ContentSafetyDTO getSafetyOverview(DateTime startDate, DateTime endDate) {
        // Safety metrics and flagged content
    }

    // ── Preflight Check ──
    @AuraEnabled
    public static Map<String, Boolean> checkPrerequisites() {
        // Returns map of prerequisite → met/not met
        // Keys: 'dataCloudEnabled', 'auditFeedbackEnabled', 'hasData', 'hasDmoAccess'
    }
}
```

## Service Layer — Key Methods

```apex
public with sharing class AiInsightsService {

    private static final AiInsightsDAO dao = new AiInsightsDAO();
    private static final UserResolverService resolver = new UserResolverService();

    public UsageOverviewDTO getOverview(DateRangeFilter filter) {
        // 1. Count requests in date range
        // 2. Count unique users
        // 3. Get feedback summary (positive/negative/total)
        // 4. Sum tokens
        // 5. Count toxic flags
        // 6. Assemble DTO
    }

    public List<UserUsageDTO> getUsageByUser(DateRangeFilter filter) {
        // 1. Query all requests in date range → group by UserId
        // 2. Query feedback for those requests → group by user
        // 3. Query tags to get top prompts per user
        // 4. Resolve all user IDs to names via UserResolverService
        // 5. Assemble DTOs, sort by requestCount DESC
    }

    public List<PromptUsageDTO> getUsageByPrompt(DateRangeFilter filter) {
        // 1. Query tags where TagName = 'prompt_template_dev_name'
        // 2. Group requests by prompt template
        // 3. Query feedback per prompt group
        // 4. Query token counts per prompt group
        // 5. Resolve prompt dev names to labels
        // 6. Assemble DTOs
    }

    public List<PromptOutputDTO> getPromptOutputs(
        String promptDevName, DateRangeFilter filter, Integer limitCount
    ) {
        // 1. Find request IDs where tag matches prompt dev name
        // 2. Query generations for those requests
        // 3. Query feedback for those generations
        // 4. Query content quality for those generations
        // 5. Resolve user names
        // 6. Assemble DTOs with truncated text
    }

    public List<TokenConsumptionDTO> getTokenConsumption(
        DateRangeFilter filter, String groupBy
    ) {
        // 1. Query requests with token counts
        // 2. Query responses with output token counts
        // 3. Group by specified dimension (user/prompt/date bucket)
        // 4. Resolve group keys to labels
        // 5. Calculate averages
    }

    public ContentSafetyDTO getSafetyOverview(DateRangeFilter filter) {
        // 1. Count total generations in date range
        // 2. Query content quality for toxic flags
        // 3. Query content categories for score averages
        // 4. Get recent flagged outputs (last 10)
        // 5. Assemble DTO
    }
}
```

## UserResolverService — Caching Strategy

```apex
public with sharing class UserResolverService {

    private static final String CACHE_PARTITION = 'local.AiInsights';
    private static final Integer USER_CACHE_TTL = 3600;       // 1 hour
    private static final Integer PROMPT_CACHE_TTL = 14400;    // 4 hours

    /**
     * Resolves User IDs to display names.
     * Checks Platform Cache first, then queries User object for misses.
     * Caches results for subsequent calls.
     */
    public Map<Id, String> resolveUsers(Set<Id> userIds) {
        Map<Id, String> resolved = new Map<Id, String>();

        // Step 1: Check cache for each ID
        Set<Id> cacheMisses = new Set<Id>();
        for (Id uid : userIds) {
            String cached = getCachedUserName(uid);
            if (cached != null) {
                resolved.put(uid, cached);
            } else {
                cacheMisses.add(uid);
            }
        }

        // Step 2: Query User object for misses
        if (!cacheMisses.isEmpty()) {
            for (User u : [SELECT Id, Name FROM User WHERE Id IN :cacheMisses]) {
                resolved.put(u.Id, u.Name);
                cacheUserName(u.Id, u.Name);
            }
        }

        // Step 3: Handle IDs not found in User table
        for (Id uid : userIds) {
            if (!resolved.containsKey(uid)) {
                resolved.put(uid, 'Unknown (' + uid + ')');
            }
        }

        return resolved;
    }

    /**
     * Resolves prompt template developer names to human-readable labels.
     * Attempts GenAiPromptTemplate SOQL first, falls back to humanizing dev name.
     */
    public Map<String, String> resolvePromptTemplates(Set<String> devNames) {
        Map<String, String> resolved = new Map<String, String>();

        // Try querying GenAiPromptTemplate
        try {
            // Query may fail if object not accessible — that's OK
            for (SObject pt : Database.query(
                'SELECT DeveloperName, MasterLabel FROM GenAiPromptTemplate ' +
                'WHERE DeveloperName IN :devNames'
            )) {
                resolved.put((String)pt.get('DeveloperName'), (String)pt.get('MasterLabel'));
            }
        } catch (Exception e) {
            // GenAiPromptTemplate not accessible — fall through to humanization
        }

        // Humanize any unresolved dev names (Replace_Underscores_With_Spaces)
        for (String dn : devNames) {
            if (!resolved.containsKey(dn)) {
                resolved.put(dn, dn.replace('_', ' '));
            }
        }

        return resolved;
    }

    // ── Cache helpers (graceful degradation if cache unavailable) ──

    private String getCachedUserName(Id userId) {
        try {
            return (String) Cache.Org.get(CACHE_PARTITION + '.user_' + userId);
        } catch (Exception e) {
            return null;
        }
    }

    private void cacheUserName(Id userId, String name) {
        try {
            Cache.Org.put(CACHE_PARTITION + '.user_' + userId, name, USER_CACHE_TTL);
        } catch (Exception e) {
            // Cache unavailable — no-op
        }
    }
}
```

## EntitlementService — Adoption Denominator

```apex
public interface IEntitlementService {
    Set<Id> getEntitledUserIds();
    List<String> getConfiguredPermissionSets();
    EntitlementSnapshotDTO getSnapshot(Set<String> activeUserIdStrings);
}

public with sharing class EntitlementService implements IEntitlementService {
    // Buckets the configured CMT rows by Entitlement_Type__c
    // (PermissionSet / PermissionSetGroup / Profile) and routes each to
    // the right query path. Static transaction-scoped cache; no Platform
    // Cache (PSA writes have no event hook for invalidation).

    public Set<Id> getEntitledUserIds() { ... }
    public List<String> getConfiguredPermissionSets() { ... }
    public EntitlementSnapshotDTO getSnapshot(Set<String> activeUserIdStrings) {
        // 1. Load + bucket CMT rows
        // 2. Resolve names: PermissionSet.Name / PSG.DeveloperName / Profile.Name
        // 3. Query users:
        //      PSA WHERE PermissionSetId IN :psIds OR PermissionSetGroupId IN :psgIds
        //          AND Assignee.IsActive = TRUE
        //      User WHERE ProfileId IN :profileIds AND IsActive = TRUE
        // 4. Compute adoptionRate = (active ∩ entitled) / entitled, [0, 1.0]
        // 5. Any failure ⇒ entitledFallback = true, denominator = total active users
    }
}
```

**Configuration:** `FluentMetric_Entitlement_PermissionSet__mdt` rows.
Each row has `Permission_Set_Developer_Name__c` (the source dev name),
`Entitlement_Type__c` (`PermissionSet` / `PermissionSetGroup` / `Profile`),
and `Is_Enabled__c`. Rows with a blank or unknown type fold into the
`PermissionSet` bucket so package upgrades don't silently drop them.

**Tests** use `EntitlementServiceMock` for deterministic snapshots.
`AiInsightsService` accepts an `IEntitlementService` via constructor
injection so tests don't have to seed `PermissionSetAssignment` rows.

## DAO Layer — DMO Query Encapsulation

```apex
public with sharing class AiInsightsDAO {

    /**
     * Get requests in a date range.
     * Returns raw DMO records — caller handles aggregation.
     */
    public List<SObject> getRequestsByDateRange(DateTime startDate, DateTime endDate) {
        return Database.query(
            'SELECT Id, UserId__c, InputPrompt__c, ModelName__c, Feature__c, ' +
            '       InputTokenCount__c, CreatedDate__c, Status__c ' +
            'FROM GenAIGatewayRequest__dlm ' +
            'WHERE CreatedDate__c >= :startDate AND CreatedDate__c <= :endDate ' +
            'ORDER BY CreatedDate__c DESC'
        );
    }

    /**
     * Get request tags for a set of request IDs.
     */
    public List<SObject> getRequestTags(Set<String> requestIds) {
        return Database.query(
            'SELECT Id, Parent__c, TagName__c, TagValue__c ' +
            'FROM GenAIGatewayRequestTags__dlm ' +
            'WHERE Parent__c IN :requestIds'
        );
    }

    /**
     * Get request tags filtered to prompt template names only.
     */
    public List<SObject> getPromptTemplateTags(DateTime startDate, DateTime endDate) {
        return Database.query(
            'SELECT Id, Parent__c, TagValue__c ' +
            'FROM GenAIGatewayRequestTags__dlm ' +
            'WHERE TagName__c LIKE \'prompt_template_dev_name\''
        );
        // Note: may need additional date filtering via join to requests
    }

    /**
     * Get responses for a set of request IDs.
     */
    public List<SObject> getResponsesForRequests(Set<String> requestIds) {
        return Database.query(
            'SELECT Id, RequestId__c, OutputTokenCount__c, ResponseTimestamp__c ' +
            'FROM GenAIGatewayResponse__dlm ' +
            'WHERE RequestId__c IN :requestIds'
        );
    }

    /**
     * Get generations for a set of response IDs.
     */
    public List<SObject> getGenerationsForResponses(Set<String> responseIds) {
        return Database.query(
            'SELECT Id, ResponseId__c, GeneratedText__c, GenerationIndex__c ' +
            'FROM GenAIGeneration__dlm ' +
            'WHERE ResponseId__c IN :responseIds'
        );
    }

    /**
     * Get feedback for a set of generation IDs.
     */
    public List<SObject> getFeedbackForGenerations(Set<String> generationIds) {
        return Database.query(
            'SELECT Id, GenerationId__c, FeedbackType__c, FeedbackValue__c, UserId__c ' +
            'FROM GenAIFeedback__dlm ' +
            'WHERE GenerationId__c IN :generationIds'
        );
    }

    /**
     * Get content quality records for a set of generation IDs.
     */
    public List<SObject> getContentQualityForGenerations(Set<String> generationIds) {
        return Database.query(
            'SELECT Id, GenerationId__c, IsToxic__c ' +
            'FROM GenAIContentQuality__dlm ' +
            'WHERE GenerationId__c IN :generationIds'
        );
    }

    /**
     * Get content category scores for a set of content quality IDs.
     */
    public List<SObject> getContentCategories(Set<String> contentQualityIds) {
        return Database.query(
            'SELECT Id, ContentQualityId__c, CategoryName__c, Score__c ' +
            'FROM GenAIContentCategory__dlm ' +
            'WHERE ContentQualityId__c IN :contentQualityIds'
        );
    }
}
```

## Testing Strategy

DMO data will not exist in test context. Tests must use mocking:

1. **DAO layer** — Create a `AiInsightsDAOMock` class implementing an interface. The mock returns hand-crafted SObject lists that simulate DMO query results.
2. **Service layer** — Inject the mock DAO. Test business logic (aggregation, calculation, name resolution) with controlled data.
3. **Controller layer** — Test parameter validation and error handling. Mock the service.
4. **UserResolverService** — Can be tested directly since it queries the standard User object (test users exist in test context).

```apex
// Example: Interface for DAO mockability
public interface IAiInsightsDAO {
    List<SObject> getRequestsByDateRange(DateTime startDate, DateTime endDate);
    List<SObject> getRequestTags(Set<String> requestIds);
    // ... etc
}
```

**Note on DMO SOQL in tests:** Data Cloud DMO queries may not work in Apex test methods due to the Data Cloud layer. The DAO interface + mock pattern is essential. If DMO queries do work in test context with `@IsTest(SeeAllData=true)`, document that as an alternative — but don't rely on it for packaged tests.
