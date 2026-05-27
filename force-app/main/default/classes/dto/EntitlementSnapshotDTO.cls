/**
 * Adoption denominator snapshot returned by EntitlementService.getSnapshot().
 *
 * `entitledCount` is the count of users assigned to any configured Permission
 * Set (or PermissionSetGroup, since PSG membership surfaces directly on
 * PermissionSetAssignment). When the FluentMetric_Entitlement_PermissionSet__mdt
 * configuration yields zero matches — empty CMT, none of the named PSs exist in
 * the org, or the query fails — `entitledFallback` flips to true and
 * `entitledCount` is replaced by `totalActiveOrgUsers` so adoption percentages
 * still resolve to a sensible denominator.
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
