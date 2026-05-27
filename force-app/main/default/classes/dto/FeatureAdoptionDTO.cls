/**
 * Per-feature adoption row for the Activity tab feature-adoption table.
 *
 * `breadthRate` is uniqueUserCount / entitledDenominator (entitled-user count
 * when the EntitlementService has resolved a non-empty set; falls back to
 * total active org users when entitledFallback=true on the snapshot).
 *
 * `depthMedian` is the median number of invocations per active user — gives
 * a sense of how engaged the people who *do* use the feature actually are.
 *
 * `repeatUserCount` is users with >= 2 invocations in the window.
 *
 * `firstObservedInOrg` predates the active date filter so the LWC can show
 * "first seen 2025-08-15" even on a 30-day Overview view; `firstObservedInRange`
 * is the in-window minimum (null when zero rows match).
 */
public with sharing class FeatureAdoptionDTO {
    @AuraEnabled
    public String featureName;
    @AuraEnabled
    public Integer uniqueUserCount;
    @AuraEnabled
    public Integer repeatUserCount;
    @AuraEnabled
    public Integer invocationCount;
    @AuraEnabled
    public Long totalTokens;
    @AuraEnabled
    public Decimal breadthRate;
    @AuraEnabled
    public Decimal depthMedian;
    @AuraEnabled
    public DateTime firstObservedInOrg;
    @AuraEnabled
    public DateTime firstObservedInRange;
    @AuraEnabled
    public DateTime lastObservedInRange;
    @AuraEnabled
    public Boolean entitledFallback;

    public FeatureAdoptionDTO() {
        this.uniqueUserCount = 0;
        this.repeatUserCount = 0;
        this.invocationCount = 0;
        this.totalTokens = 0L;
        this.breadthRate = 0;
        this.depthMedian = 0;
        this.entitledFallback = false;
    }
}
