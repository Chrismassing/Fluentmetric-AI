/**
 * Per prompt-template metrics. promptDevName comes from the live
 * GenAIGatewayRequest__dlm.promptTemplateDevName__c column.
 */
public with sharing class PromptUsageDTO {
    @AuraEnabled
    public String promptDevName;
    @AuraEnabled
    public String promptLabel;
    @AuraEnabled
    public String featureName;
    @AuraEnabled
    public Integer invocationCount;
    @AuraEnabled
    public Integer uniqueUserCount;
    @AuraEnabled
    public Decimal acceptanceRate;
    @AuraEnabled
    public Long avgInputTokens;
    @AuraEnabled
    public Long avgOutputTokens;
    @AuraEnabled
    public Long totalTokens;
    @AuraEnabled
    public Integer toxicFlagCount;
    @AuraEnabled
    public DateTime firstUsed;
    @AuraEnabled
    public DateTime lastUsed;

    // Cost analytics
    @AuraEnabled
    public Long estimatedFlexCredits;
    @AuraEnabled
    public Decimal estimatedUsd;
    @AuraEnabled
    public Boolean costUsedFallback;
    @AuraEnabled
    public String costConfidence;

    // Adoption analytics (Phase 1.4) — populated by Phase 3 service work.
    // `breadthRate` = uniqueUserCount / entitled-denominator.
    // `repeatUserCount` = users with >= 2 invocations in the window.
    // `medianInvocationsPerUser` = depth indicator.
    // `firstObservedInOrg` may predate the active date filter.
    // `acceptanceSource`: 'EXACT' | 'SAMPLED' | 'CORRELATED' | null — tells the
    //   LWC how to render the confidence badge on the acceptance column.
    @AuraEnabled
    public Decimal breadthRate;
    @AuraEnabled
    public Integer repeatUserCount;
    @AuraEnabled
    public Decimal medianInvocationsPerUser;
    @AuraEnabled
    public DateTime firstObservedInOrg;
    @AuraEnabled
    public String acceptanceSource;

    public PromptUsageDTO() {
        this.invocationCount = 0;
        this.uniqueUserCount = 0;
        this.totalTokens = 0L;
        this.toxicFlagCount = 0;
        this.estimatedFlexCredits = 0L;
        this.estimatedUsd = 0;
        this.costUsedFallback = false;
        this.costConfidence = 'HIGH';
        this.breadthRate = 0;
        this.repeatUserCount = 0;
        this.medianInvocationsPerUser = 0;
    }
}
