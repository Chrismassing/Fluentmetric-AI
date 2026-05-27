/**
 * Resolves the entitled-user denominator for FluentMetric AI adoption metrics.
 *
 * Configured entitlement sources come from
 * FluentMetric_Entitlement_PermissionSet__mdt. Each row pairs a developer name
 * with an Entitlement_Type__c picklist value; the resolver routes the name to
 * the appropriate query path:
 *   - PermissionSet      → PermissionSet.Name + PermissionSetAssignment
 *   - PermissionSetGroup → PermissionSetGroup.DeveloperName + PSA
 *                          (PSG membership is exposed directly on PSA, no
 *                          transitive walk required)
 *   - Profile            → Profile.Name + User.ProfileId
 *
 * Multiple types coexist freely — the entitled-user set is the union across
 * all enabled rows, deduplicated by user Id.
 *
 * Caching strategy: a single static cache lives for the duration of the
 * transaction. We deliberately avoid Platform Cache because PSA / Profile
 * writes have no event hook to invalidate the entry — short-lived staleness
 * within a single dashboard request is fine; cross-request staleness is not.
 *
 * Failure modes (all flip `entitledFallback = true` and switch the denominator
 * to total active org users):
 *   - CMT empty or all rows disabled
 *   - None of the configured names match an existing PS / PSG / Profile
 *   - Any of the resolution queries throw (FLS, missing object, etc.)
 *   - The total-user fallback query also throws (very rare; returns -1)
 */
public with sharing class EntitlementService implements IEntitlementService {
    @TestVisible
    private static EntitlementSnapshotDTO CACHED_SNAPSHOT;
    @TestVisible
    private static Set<Id> CACHED_ENTITLED_IDS;
    @TestVisible
    private static List<String> CACHED_CONFIGURED_NAMES;

    public Set<Id> getEntitledUserIds() {
        if (CACHED_ENTITLED_IDS != null) {
            return CACHED_ENTITLED_IDS;
        }
        loadEntitlement();
        return CACHED_ENTITLED_IDS == null ? new Set<Id>() : CACHED_ENTITLED_IDS;
    }

    public List<String> getConfiguredPermissionSets() {
        if (CACHED_CONFIGURED_NAMES != null) {
            return CACHED_CONFIGURED_NAMES;
        }
        loadEntitlement();
        return CACHED_CONFIGURED_NAMES == null ? new List<String>() : CACHED_CONFIGURED_NAMES;
    }

    public EntitlementSnapshotDTO getSnapshot(Set<String> activeUserIdStrings) {
        loadEntitlement();
        EntitlementSnapshotDTO snap = new EntitlementSnapshotDTO();
        snap.configuredPermissionSets = CACHED_CONFIGURED_NAMES == null
            ? new List<String>()
            : new List<String>(CACHED_CONFIGURED_NAMES);
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
    private static final String TYPE_PERMISSION_SET = 'PermissionSet';
    @TestVisible
    private static final String TYPE_PERMISSION_SET_GROUP = 'PermissionSetGroup';
    @TestVisible
    private static final String TYPE_PROFILE = 'Profile';

    @TestVisible
    private static void loadEntitlement() {
        if (CACHED_ENTITLED_IDS != null) {
            return;
        }
        CACHED_ENTITLED_IDS = new Set<Id>();
        CACHED_CONFIGURED_NAMES = new List<String>();
        CACHED_SNAPSHOT = new EntitlementSnapshotDTO();

        Map<String, Set<String>> namesByType = readConfiguredRows();
        CACHED_CONFIGURED_NAMES = flattenConfigured(namesByType);
        if (CACHED_CONFIGURED_NAMES.isEmpty()) {
            CACHED_SNAPSHOT.entitledFallback = true;
            return;
        }

        try {
            Set<String> psNames = namesByType.get(TYPE_PERMISSION_SET);
            Set<String> psgNames = namesByType.get(TYPE_PERMISSION_SET_GROUP);
            Set<String> profileNames = namesByType.get(TYPE_PROFILE);

            // Permission sets + permission set groups share the
            // PermissionSetAssignment-based path because PSA exposes both
            // PermissionSetId and PermissionSetGroupId directly.
            Set<Id> psIds = (psNames == null || psNames.isEmpty()) ? new Set<Id>() : resolvePermissionSetIds(psNames);
            Set<Id> psgIds = (psgNames == null || psgNames.isEmpty())
                ? new Set<Id>()
                : resolvePermissionSetGroupIds(psgNames);
            Set<Id> profileIds = (profileNames == null || profileNames.isEmpty())
                ? new Set<Id>()
                : resolveProfileIds(profileNames);

            if (psIds.isEmpty() && psgIds.isEmpty() && profileIds.isEmpty()) {
                // None of the configured names match anything in this org.
                CACHED_SNAPSHOT.entitledFallback = true;
                return;
            }

            if (!psIds.isEmpty() || !psgIds.isEmpty()) {
                CACHED_ENTITLED_IDS.addAll(queryEntitledUsersByPsa(psIds, psgIds));
            }
            if (!profileIds.isEmpty()) {
                CACHED_ENTITLED_IDS.addAll(queryEntitledUsersByProfile(profileIds));
            }

            CACHED_SNAPSHOT.entitledCount = CACHED_ENTITLED_IDS.size();
            CACHED_SNAPSHOT.entitledFallback = CACHED_ENTITLED_IDS.isEmpty();
        } catch (Exception e) {
            // PermissionSet / PSGroup / PSA / Profile / User inaccessible to the
            // running user, or schema absent — gracefully fall back to "all
            // active users".
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
    private static Set<Id> resolvePermissionSetGroupIds(Set<String> names) {
        Set<Id> out = new Set<Id>();
        for (PermissionSetGroup psg : [
            SELECT Id, DeveloperName
            FROM PermissionSetGroup
            WHERE DeveloperName IN :names
            WITH USER_MODE
        ]) {
            out.add(psg.Id);
        }
        return out;
    }

    @TestVisible
    private static Set<Id> resolveProfileIds(Set<String> names) {
        Set<Id> out = new Set<Id>();
        for (Profile p : [
            SELECT Id, Name
            FROM Profile
            WHERE Name IN :names
            WITH USER_MODE
        ]) {
            out.add(p.Id);
        }
        return out;
    }

    @TestVisible
    private static Set<Id> queryEntitledUsersByPsa(Set<Id> psIds, Set<Id> psgIds) {
        Set<Id> out = new Set<Id>();
        Date today = Date.today();
        for (PermissionSetAssignment psa : [
            SELECT AssigneeId
            FROM PermissionSetAssignment
            WHERE
                (PermissionSetId IN :psIds
                OR PermissionSetGroupId IN :psgIds)
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
    private static Set<Id> queryEntitledUsersByProfile(Set<Id> profileIds) {
        Set<Id> out = new Set<Id>();
        for (User u : [
            SELECT Id
            FROM User
            WHERE ProfileId IN :profileIds AND IsActive = TRUE
            WITH USER_MODE
            LIMIT 50000
        ]) {
            out.add(u.Id);
        }
        return out;
    }

    /**
     * Bucket enabled CMT rows by Entitlement_Type__c so each type can be routed
     * to the right resolution query. Rows with a blank or unknown type fall
     * back to PermissionSet for backwards compatibility with seed records
     * authored before the picklist was added.
     */
    @TestVisible
    private static Map<String, Set<String>> readConfiguredRows() {
        Map<String, Set<String>> out = new Map<String, Set<String>>{
            TYPE_PERMISSION_SET => new Set<String>(),
            TYPE_PERMISSION_SET_GROUP => new Set<String>(),
            TYPE_PROFILE => new Set<String>()
        };
        try {
            for (FluentMetric_Entitlement_PermissionSet__mdt row : [
                SELECT Permission_Set_Developer_Name__c, Entitlement_Type__c, Is_Enabled__c
                FROM FluentMetric_Entitlement_PermissionSet__mdt
                WHERE Is_Enabled__c = TRUE
            ]) {
                if (String.isBlank(row.Permission_Set_Developer_Name__c)) {
                    continue;
                }
                String t = String.isBlank(row.Entitlement_Type__c) ? TYPE_PERMISSION_SET : row.Entitlement_Type__c;
                Set<String> bucket = out.get(t);
                if (bucket == null) {
                    // Unknown type value — fold into PermissionSet so the row
                    // isn't silently dropped on package upgrade.
                    bucket = out.get(TYPE_PERMISSION_SET);
                }
                bucket.add(row.Permission_Set_Developer_Name__c);
            }
        } catch (Exception e) {
            // CMT unavailable — return empty buckets so caller drops to fallback.
        }
        return out;
    }

    @TestVisible
    private static List<String> flattenConfigured(Map<String, Set<String>> namesByType) {
        List<String> out = new List<String>();
        if (namesByType == null) {
            return out;
        }
        Set<String> seen = new Set<String>();
        for (Set<String> bucket : namesByType.values()) {
            if (bucket == null) {
                continue;
            }
            for (String n : bucket) {
                if (String.isNotBlank(n) && !seen.contains(n)) {
                    seen.add(n);
                    out.add(n);
                }
            }
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
        CACHED_CONFIGURED_NAMES = null;
    }
}
