# APEX-SERVICES.md — Apex Service Layer Design

## Class Structure

```
force-app/main/default/classes/
├── controllers/
│   └── AiInsightsController.cls          // @AuraEnabled methods for LWC
├── services/
│   ├── AiInsightsService.cls             // Business logic and orchestration
│   └── UserResolverService.cls           // ID→Name resolution with caching
├── dao/
│   └── AiInsightsDAO.cls                 // All DMO SOQL queries
├── dto/
│   ├── UsageOverviewDTO.cls              // Summary metrics
│   ├── UserUsageDTO.cls                  // Per-user usage data
│   ├── PromptUsageDTO.cls                // Per-prompt usage data
│   ├── PromptOutputDTO.cls               // Individual prompt outputs
│   ├── TokenConsumptionDTO.cls           // Token usage data
│   ├── ContentSafetyDTO.cls              // Safety/quality data
│   └── DateRangeFilter.cls               // Reusable date range input
└── tests/
    ├── AiInsightsControllerTest.cls
    ├── AiInsightsServiceTest.cls
    ├── AiInsightsDAOTest.cls
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
