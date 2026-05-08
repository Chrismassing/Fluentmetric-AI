/**
 * One row of grouped token consumption. groupKey is the raw dimension value
 * (user ID, prompt dev name, day ISO string); groupLabel is the resolved label.
 */
public with sharing class TokenConsumptionDTO {
    @AuraEnabled
    public String groupKey;
    @AuraEnabled
    public String groupLabel;
    @AuraEnabled
    public Long inputTokens;
    @AuraEnabled
    public Long outputTokens;
    @AuraEnabled
    public Long totalTokens;
    @AuraEnabled
    public Integer requestCount;
    @AuraEnabled
    public Decimal avgTokensPerRequest;

    // Cost analytics (Phase 3.5)
    @AuraEnabled
    public Decimal estimatedUsd;
    @AuraEnabled
    public Boolean costUsedFallback;
    @AuraEnabled
    public String costConfidence;

    public TokenConsumptionDTO() {
        this.inputTokens = 0L;
        this.outputTokens = 0L;
        this.totalTokens = 0L;
        this.requestCount = 0;
        this.avgTokensPerRequest = 0;
        this.estimatedUsd = 0;
        this.costUsedFallback = false;
        this.costConfidence = 'HIGH';
    }
}
