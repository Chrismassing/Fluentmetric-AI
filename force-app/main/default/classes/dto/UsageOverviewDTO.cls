/**
 * High-level KPIs for the Overview dashboard card strip.
 * Populated by AiInsightsService.getOverview().
 */
public with sharing class UsageOverviewDTO {
    @AuraEnabled
    public Integer totalRequests;
    @AuraEnabled
    public Integer uniqueUsers;
    @AuraEnabled
    public Integer uniquePromptTemplates;
    @AuraEnabled
    public Decimal acceptanceRate;
    @AuraEnabled
    public Long totalInputTokens;
    @AuraEnabled
    public Long totalOutputTokens;
    @AuraEnabled
    public Integer toxicFlagCount;
    @AuraEnabled
    public Integer feedbackCount;
    @AuraEnabled
    public String dateRangeLabel;

    // Highlights — "who/what/where is winning this range"
    // Each highlight surfaces both a human label and a headline number.
    @AuraEnabled
    public String topUserName;
    @AuraEnabled
    public Integer topUserRequestCount;
    @AuraEnabled
    public String topPromptLabel;
    @AuraEnabled
    public Integer topPromptInvocations;
    @AuraEnabled
    public String topModelName;
    @AuraEnabled
    public Long topModelTotalTokens;
    @AuraEnabled
    public String topFeatureName;
    @AuraEnabled
    public Integer topFeatureRequestCount;

    // Cost analytics — populated by CostCalculatorService + STDM probe.
    // `costConfidence`: ACTUAL / HIGH / ESTIMATED / FALLBACK / NOT_COSTED.
    // `costSource`: ACTUAL_WALLET / ESTIMATED_TIER / NONE — distinguishes Wallet
    //   actuals from FluentMetric tier-rate estimates so the UI can render the
    //   correct label and disclaimer.
    // `agentforceActionCount`: non-zero only when STDM is available.
    // `agentforceFlexCredits`: action FC (flat 20 × invocations) separate from LLM FC.
    @AuraEnabled
    public Long estimatedFlexCredits;
    @AuraEnabled
    public Decimal estimatedBaseUsd;
    @AuraEnabled
    public Decimal estimatedUsdAfterDiscount;
    @AuraEnabled
    public String costConfidence;
    @AuraEnabled
    public String costSource;
    @AuraEnabled
    public Integer agentforceActionCount;
    @AuraEnabled
    public Long agentforceFlexCredits;
    @AuraEnabled
    public Decimal agentforceUsd;

    public UsageOverviewDTO() {
        this.totalRequests = 0;
        this.uniqueUsers = 0;
        this.uniquePromptTemplates = 0;
        this.acceptanceRate = 0;
        this.totalInputTokens = 0L;
        this.totalOutputTokens = 0L;
        this.toxicFlagCount = 0;
        this.feedbackCount = 0;
        this.estimatedFlexCredits = 0L;
        this.estimatedBaseUsd = 0;
        this.estimatedUsdAfterDiscount = 0;
        this.costConfidence = 'HIGH';
        this.costSource = 'ESTIMATED_TIER';
        this.agentforceActionCount = 0;
        this.agentforceFlexCredits = 0L;
        this.agentforceUsd = 0;
    }
}
