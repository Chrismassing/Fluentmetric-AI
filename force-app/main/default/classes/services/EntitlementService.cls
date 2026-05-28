/**
 * Resolves the entitled-user denominator for FluentMetric AI adoption metrics.
 *
 * The "entitled population" is the set of users assigned to a single, well-known
 * permission set: FluentMetric_AI_Entitled_User. Admins assign that permset to
 * every user who is expected to use Einstein Generative AI features; the
 * Lightning dashboards and the Tableau Next adoption-rate metric both divide
 * active users by this set.
 *
 * Why a permset rather than a Custom Metadata Type: assignment is a single
 * one-click action in Setup (or a permset-license-style bulk script), it
 * surfaces in standard reports, it composes with PSGs the customer already
 * uses, and it doesn't require a deploy to change scope. Earlier versions of
 * this service used a custom-metadata mapping table that named several
 * permission sets / permission set groups / profiles as "entitled" — that
 * extra indirection was removed in favor of "membership of one PS = in scope".
 *
 * Caching strategy: a single static cache lives for the duration of the
 * transaction. We deliberately avoid Platform Cache because PSA writes have no
 * event hook to invalidate the entry — short-lived staleness within a single
 * dashboard request is fine; cross-request staleness is not.
 *
 * Failure modes (all flip `entitledFallback = true` and switch the denominator
 * to total active org users):
 *   - FluentMetric_AI_Entitled_User permset isn't deployed in this org
 *   - Nobody is assigned to it (zero PSA rows)
 *   - PermissionSet / PSA queries throw (FLS, schema absent, etc.)
 *   - The total-user fallback query itself throws (very rare; returns -1)
 */
public with sharing class EntitlementService implements IEntitlementService {
    /**
     * The single permission set that defines the entitled-user scope. Customers
     * assign this to every user who *should* be using Einstein GenAI; assignees
     * become the adoption-rate denominator.
     */
    public static final String ENTITLEMENT_PERMSET_NAME = 'FluentMetric_AI_Entitled_User';

    @TestVisible
    private static EntitlementSnapshotDTO CACHED_SNAPSHOT;
    @TestVisible
    private static Set<Id> CACHED_ENTITLED_IDS;

    public Set<Id> getEntitledUserIds() {
        if (CACHED_ENTITLED_IDS != null) {
            return CACHED_ENTITLED_IDS;
        }
        loadEntitlement();
        return CACHED_ENTITLED_IDS == null ? new Set<Id>() : CACHED_ENTITLED_IDS;
    }

    /**
     * Returns the configured permset name(s) so UIs can render "Adoption is
     * computed against assignees of {names}" hints. With the post-CMT model
     * this is always a single-element list, but the interface keeps List
     * shape to avoid breaking the agent action's existing label join.
     */
    public List<String> getConfiguredPermissionSets() {
        return new List<String>{ ENTITLEMENT_PERMSET_NAME };
    }

    public EntitlementSnapshotDTO getSnapshot(Set<String> activeUserIdStrings) {
        loadEntitlement();
        EntitlementSnapshotDTO snap = new EntitlementSnapshotDTO();
        snap.configuredPermissionSets = new List<String>{ ENTITLEMENT_PERMSET_NAME };
        snap.totalActiveOrgUsers = countActiveOrgUsers();
        snap.entitledFallback = (CACHED_SNAPSHOT == null || CACHED_SNAPSHOT.entitledFallback);

        Integer entitled = (CACHED_ENTITLED_IDS == null) ? 0 : CACHED_ENTITLED_IDS.size();
        if (snap.entitledFallback || entitled == 0) {
            // Fallback denominator: all active org users.
            snap.entitledCount = snap.totalActiveOrgUsers;
            snap.entitledFallback = true;
        } else {
            snap.entitledCount = entitled;
        }

        Set<Id> entitledIds = (CACHED_ENTITLED_IDS == null) ? new Set<Id>() : CACHED_ENTITLED_IDS;
        Integer active = 0;
        Integer unmatched = 0;
        if (activeUserIdStrings != null) {
            for (String uid : activeUserIdStrings) {
                if (String.isBlank(uid)) {
                    continue;
                }
                Id asId = tryParseId(uid);
                if (asId == null) {
                    continue;
                }
                active++;
                if (!entitledIds.isEmpty() && !entitledIds.contains(asId)) {
                    unmatched++;
                }
            }
        }
        snap.activeCount = active;
        snap.unmatchedActiveCount = entitledIds.isEmpty() ? 0 : unmatched;
        // Adoption rate is "of the people who could use AI, how many did".
        // When we have a real entitled set, the numerator is active-AND-entitled
        // (i.e. active minus the active users who weren't in the entitled set);
        // otherwise the denominator is total active users and the numerator is
        // simply active count.
        Integer numerator = entitledIds.isEmpty() ? active : (active - unmatched);
        if (numerator < 0) {
            numerator = 0;
        }
        snap.adoptionRate = computeAdoptionRate(numerator, snap.entitledCount);
        return snap;
    }

    @TestVisible
    private static void loadEntitlement() {
        if (CACHED_ENTITLED_IDS != null) {
            return;
        }
        CACHED_ENTITLED_IDS = new Set<Id>();
        CACHED_SNAPSHOT = new EntitlementSnapshotDTO();

        try {
            Set<Id> psIds = resolvePermissionSetIds(new Set<String>{ ENTITLEMENT_PERMSET_NAME });
            if (psIds.isEmpty()) {
                // Permset not deployed in this org → fallback.
                CACHED_SNAPSHOT.entitledFallback = true;
                return;
            }

            CACHED_ENTITLED_IDS.addAll(queryEntitledUsersByPsa(psIds));
            CACHED_SNAPSHOT.entitledCount = CACHED_ENTITLED_IDS.size();
            CACHED_SNAPSHOT.entitledFallback = CACHED_ENTITLED_IDS.isEmpty();
        } catch (Exception e) {
            // PermissionSet / PSA inaccessible to the running user, or schema
            // absent — gracefully fall back to "all active users".
            CACHED_ENTITLED_IDS = new Set<Id>();
            CACHED_SNAPSHOT.entitledFallback = true;
        }
    }

    @TestVisible
    private static Set<Id> resolvePermissionSetIds(Set<String> names) {
        Set<Id> out = new Set<Id>();
        for (PermissionSet ps : [
            SELECT Id, Name
            FROM PermissionSet
            WHERE Name IN :names
            WITH USER_MODE
        ]) {
            out.add(ps.Id);
        }
        return out;
    }

    @TestVisible
    private static Set<Id> queryEntitledUsersByPsa(Set<Id> psIds) {
        Set<Id> out = new Set<Id>();
        Date today = Date.today();
        for (PermissionSetAssignment psa : [
            SELECT AssigneeId
            FROM PermissionSetAssignment
            WHERE
                PermissionSetId IN :psIds
                AND (ExpirationDate = NULL
                OR ExpirationDate >= :today)
                AND Assignee.IsActive = TRUE
            WITH USER_MODE
            LIMIT 50000
        ]) {
            out.add(psa.AssigneeId);
        }
        return out;
    }

    @TestVisible
    private static Integer countActiveOrgUsers() {
        try {
            return [SELECT COUNT() FROM User WHERE IsActive = TRUE WITH USER_MODE LIMIT 50000];
        } catch (Exception e) {
            return -1;
        }
    }

    @TestVisible
    private static Decimal computeAdoptionRate(Integer active, Integer denominator) {
        if (denominator == null || denominator <= 0 || active == null || active <= 0) {
            return 0;
        }
        return ((Decimal) active / (Decimal) denominator).setScale(4);
    }

    @TestVisible
    private static Id tryParseId(String raw) {
        try {
            return Id.valueOf(raw);
        } catch (Exception e) {
            return null;
        }
    }

    @TestVisible
    public static void clearCacheForTests() {
        CACHED_SNAPSHOT = null;
        CACHED_ENTITLED_IDS = null;
    }
}
