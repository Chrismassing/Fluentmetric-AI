/**
 * Test double for IEntitlementService — returns a deterministic snapshot so
 * AiInsightsService tests don't have to seed PermissionSetAssignments.
 */
@IsTest
public with sharing class EntitlementServiceMock implements IEntitlementService {
    public Set<Id> entitledIdsToReturn = new Set<Id>();
    public List<String> configuredNamesToReturn = new List<String>();
    public EntitlementSnapshotDTO snapshotToReturn;

    public Set<Id> getEntitledUserIds() {
        return entitledIdsToReturn == null ? new Set<Id>() : entitledIdsToReturn;
    }

    public List<String> getConfiguredPermissionSets() {
        return configuredNamesToReturn == null ? new List<String>() : configuredNamesToReturn;
    }

    public EntitlementSnapshotDTO getSnapshot(Set<String> activeUserIdStrings) {
        if (snapshotToReturn != null) {
            return snapshotToReturn;
        }
        EntitlementSnapshotDTO snap = new EntitlementSnapshotDTO();
        Integer entitled = entitledIdsToReturn == null ? 0 : entitledIdsToReturn.size();
        Integer active = activeUserIdStrings == null ? 0 : activeUserIdStrings.size();
        snap.entitledCount = entitled;
        snap.activeCount = active;
        snap.totalActiveOrgUsers = entitled == 0 ? active : entitled;
        snap.unmatchedActiveCount = 0;
        snap.entitledFallback = (entitled == 0);
        snap.configuredPermissionSets = configuredNamesToReturn == null
            ? new List<String>()
            : new List<String>(configuredNamesToReturn);
        // Mirror live service math: numerator is active-AND-entitled when an
        // entitled set is present, else just active.
        Integer numerator = (entitledIdsToReturn == null || entitledIdsToReturn.isEmpty())
            ? active
            : Math.min(active, entitled);
        if (snap.entitledCount > 0 && numerator > 0) {
            snap.adoptionRate = ((Decimal) numerator / (Decimal) snap.entitledCount).setScale(4);
        } else {
            snap.adoptionRate = 0;
        }
        return snap;
    }
}
