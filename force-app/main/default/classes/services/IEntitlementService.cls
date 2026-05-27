/**
 * Adoption-denominator contract.
 *
 * The "entitled population" is the set of users who *could* invoke Einstein
 * GenAI features — i.e. users assigned to one of the configured PermissionSets
 * (or PermissionSetGroups). Adoption metrics divide active users by this set
 * rather than by the entire org so the dashboard reflects who actually has the
 * grant, not just who happened to log in.
 *
 * The configured set lives in the FluentMetric_Entitlement_PermissionSet__mdt
 * Custom Metadata Type. When that table is empty, none of its names resolve
 * against the live org, or the underlying PermissionSetAssignment query fails,
 * the snapshot's `entitledFallback` flips to true and the denominator becomes
 * "all active org users" so adoption math still works.
 */
public interface IEntitlementService {
    Set<Id> getEntitledUserIds();
    EntitlementSnapshotDTO getSnapshot(Set<String> activeUserIdStrings);
    List<String> getConfiguredPermissionSets();
}
