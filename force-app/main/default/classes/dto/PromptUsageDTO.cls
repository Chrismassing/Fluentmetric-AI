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

    public PromptUsageDTO() {
        this.invocationCount = 0;
        this.uniqueUserCount = 0;
        this.totalTokens = 0L;
        this.toxicFlagCount = 0;
        this.estimatedFlexCredits = 0L;
        this.estimatedUsd = 0;
        this.costUsedFallback = false;
        this.costConfidence = 'HIGH';
    }
}
