/**
 * Adoption-denominator contract.
 *
 * The "entitled population" is the set of users who *could* invoke Einstein
 * GenAI features — i.e. users assigned to the FluentMetric_AI_Entitled_User
 * permission set. Adoption metrics divide active users by this set rather than
 * by the entire org so the dashboard reflects who actually has the grant, not
 * just who happened to log in.
 *
 * When the permset isn't deployed, nobody is assigned to it, or the underlying
 * PermissionSetAssignment query fails, the snapshot's `entitledFallback` flips
 * to true and the denominator becomes "all active org users" so adoption math
 * still works.
 */
public interface IEntitlementService {
    Set<Id> getEntitledUserIds();
    EntitlementSnapshotDTO getSnapshot(Set<String> activeUserIdStrings);
    List<String> getConfiguredPermissionSets();
}
