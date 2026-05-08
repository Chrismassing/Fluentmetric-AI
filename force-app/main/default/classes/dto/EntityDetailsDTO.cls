/**
 * Cross-cutting drill-in payload for the FluentMetric AI dashboards.
 *
 * Any row in any dashboard table (Users, Prompts, Tokens, Safety, Explorer)
 * can be expanded into a single `EntityDetailsDTO` that carries both the
 * aggregate header and the most recent raw requests for that entity. The
 * LWC layer renders this as a right-side drawer / expand-in-place panel.
 *
 * Field notes (see Documents/LIVE-SCHEMA.md):
 *   - `entityType` is one of: "User", "PromptTemplate", "Model", "Feature"
 *   - `entityKey` carries the raw identifier used for the drill-in:
 *       * User          → Salesforce user Id (or the `NOT_SET` sentinel)
 *       * PromptTemplate → quoted prompt dev name (e.g. `"topic_selector_prompt"`)
 *       * Model         → model string (e.g. `gpt-4.1-2025-04-14`)
 *       * Feature       → feature string (e.g. `plannerservice`)
 *   - `entityLabel` is the resolved human label; for Model/Feature it equals
 *     the raw key since no resolution exists
 *   - `uniqueUserCount` is left null for User drill-ins (trivially 1),
 *     `uniquePromptCount` is left null for PromptTemplate drill-ins
 *   - `acceptanceRate` is null when no feedback exists in scope so the LWC
 *     can render an em-dash instead of 0%
 *   - `recentRequests` reuses PromptOutputDTO — the list-view and full-text
 *     rendering contract is shared with the Prompts dashboard
 */
public with sharing class EntityDetailsDTO {
    @AuraEnabled
    public String entityType;
    @AuraEnabled
    public String entityKey;
    @AuraEnabled
    public String entityLabel;

    // Aggregate header over the date range
    @AuraEnabled
    public Integer requestCount;
    @AuraEnabled
    public Long totalInputTokens;
    @AuraEnabled
    public Long totalOutputTokens;
    @AuraEnabled
    public Long totalTokens;
    @AuraEnabled
    public Integer uniqueUserCount;
    @AuraEnabled
    public Integer uniquePromptCount;
    @AuraEnabled
    public Decimal avgTokensPerRequest;
    @AuraEnabled
    public DateTime firstUsed;
    @AuraEnabled
    public DateTime lastUsed;

    // Safety + feedback rollups (bounded to the recent generation set)
    @AuraEnabled
    public Integer toxicFlagCount;
    @AuraEnabled
    public Integer positiveFeedbackCount;
    @AuraEnabled
    public Integer negativeFeedbackCount;
    @AuraEnabled
    public Decimal acceptanceRate;

    // Recent rows (reuses the Output Viewer DTO so the LWC can swap in
    // its existing card / expand-modal renderer)
    @AuraEnabled
    public List<PromptOutputDTO> recentRequests;

    // Cost analytics (Phase 3.5)
    @AuraEnabled
    public Long estimatedFlexCredits;
    @AuraEnabled
    public Decimal estimatedUsd;
    @AuraEnabled
    public Boolean costUsedFallback;
    @AuraEnabled
    public String costConfidence;

    public EntityDetailsDTO() {
        this.requestCount = 0;
        this.totalInputTokens = 0L;
        this.totalOutputTokens = 0L;
        this.totalTokens = 0L;
        this.toxicFlagCount = 0;
        this.positiveFeedbackCount = 0;
        this.negativeFeedbackCount = 0;
        this.recentRequests = new List<PromptOutputDTO>();
        this.estimatedFlexCredits = 0L;
        this.estimatedUsd = 0;
        this.costUsedFallback = false;
        this.costConfidence = 'HIGH';
    }
}
