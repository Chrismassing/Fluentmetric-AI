/**
 * Per-user adoption row. userName is resolved from the User object via
 * UserResolverService. userId may carry the sentinel "NOT_SET" for system calls.
 */
public with sharing class UserUsageDTO {
    @AuraEnabled
    public String userId;
    @AuraEnabled
    public String userName;
    @AuraEnabled
    public String profileName;
    @AuraEnabled
    public String department;
    @AuraEnabled
    public Integer requestCount;
    @AuraEnabled
    public DateTime firstUsed;
    @AuraEnabled
    public DateTime lastUsed;
    @AuraEnabled
    public Integer positiveFeedbackCount;
    @AuraEnabled
    public Integer negativeFeedbackCount;
    @AuraEnabled
    public Decimal feedbackRatio;
    @AuraEnabled
    public List<String> topPrompts;
    @AuraEnabled
    public Long totalTokens;

    // Cost analytics
    @AuraEnabled
    public Long estimatedFlexCredits;
    @AuraEnabled
    public Decimal estimatedUsd;
    @AuraEnabled
    public Boolean costUsedFallback;
    @AuraEnabled
    public String costConfidence;

    public UserUsageDTO() {
        this.topPrompts = new List<String>();
        this.requestCount = 0;
        this.positiveFeedbackCount = 0;
        this.negativeFeedbackCount = 0;
        this.totalTokens = 0L;
        this.estimatedFlexCredits = 0L;
        this.estimatedUsd = 0;
        this.costUsedFallback = false;
        this.costConfidence = 'HIGH';
    }
}
