/**
 * Adoption denominator snapshot returned by EntitlementService.getSnapshot().
 *
 * `entitledCount` is the count of users assigned to the
 * FluentMetric_AI_Entitled_User permission set. When that permset isn't
 * deployed, has zero assignees, or the PSA query fails, `entitledFallback`
 * flips to true and `entitledCount` is replaced by `totalActiveOrgUsers` so
 * adoption percentages still resolve to a sensible denominator.
 *
 * `configuredPermissionSets` is a one-element list naming the entitlement
 * permset; kept as a list so the agent action's existing label join continues
 * to work without per-call type changes.
 */
public with sharing class EntitlementSnapshotDTO {
    @AuraEnabled
    public Integer entitledCount;
    @AuraEnabled
    public Integer activeCount;
    @AuraEnabled
    public Integer totalActiveOrgUsers;
    @AuraEnabled
    public Integer unmatchedActiveCount;
    @AuraEnabled
    public Decimal adoptionRate;
    @AuraEnabled
    public Boolean entitledFallback;
    @AuraEnabled
    public List<String> configuredPermissionSets;

    public EntitlementSnapshotDTO() {
        this.entitledCount = 0;
        this.activeCount = 0;
        this.totalActiveOrgUsers = 0;
        this.unmatchedActiveCount = 0;
        this.adoptionRate = 0;
        this.entitledFallback = true;
        this.configuredPermissionSets = new List<String>();
    }
}
