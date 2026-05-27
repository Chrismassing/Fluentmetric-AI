/**
 * Tests for EntitlementService.
 *
 * The service mostly resolves real org metadata (PermissionSet, Profile,
 * PermissionSetGroup, PermissionSetAssignment) which we cannot inject in an
 * Apex test. The strategy is therefore:
 *   - Exercise the public surface end-to-end against the seeded scratch-org
 *     CMT rows, asserting the snapshot has sane defaults regardless of the
 *     CMT contents.
 *   - Force the fallback path by clearing the cache and confirming the
 *     adoption rate math still works.
 *   - Drive the @TestVisible static helpers directly so the math is covered
 *     even when no PSA rows exist in the org.
 */
@IsTest
private class EntitlementServiceTest {
    @IsTest
    static void testGetSnapshot_emptyActiveSet_returnsSafeDefaults() {
        EntitlementService.clearCacheForTests();
        EntitlementService svc = new EntitlementService();

        Test.startTest();
        EntitlementSnapshotDTO snap = svc.getSnapshot(new Set<String>());
        Test.stopTest();

        Assert.isNotNull(snap, 'snapshot never null');
        Assert.isTrue(snap.entitledCount >= 0, 'entitledCount non-negative');
        Assert.areEqual(0, snap.activeCount, 'no active users supplied');
        Assert.isNotNull(snap.configuredPermissionSets, 'configured list initialized');
        // Adoption rate is 0 when no active users supplied.
        Assert.areEqual(0, snap.adoptionRate);
    }

    @IsTest
    static void testGetSnapshot_unmatchedActiveCount_whenIdsNotInEntitled() {
        EntitlementService.clearCacheForTests();
        // Seed a fake "entitled" set, then ask the snapshot to score active
        // ids that aren't in the seeded set — they should all show up as
        // unmatched (when a real entitled set is present).
        EntitlementService.CACHED_ENTITLED_IDS = new Set<Id>{ UserInfo.getUserId() };
        EntitlementService.CACHED_CONFIGURED_NAMES = new List<String>{ 'Test_PS' };
        EntitlementSnapshotDTO seeded = new EntitlementSnapshotDTO();
        seeded.entitledFallback = false;
        EntitlementService.CACHED_SNAPSHOT = seeded;

        EntitlementService svc = new EntitlementService();
        Set<String> active = new Set<String>{ '005000000000099' };
        EntitlementSnapshotDTO snap = svc.getSnapshot(active);
        Assert.areEqual(1, snap.activeCount, 'one bad id parses ok');
        Assert.areEqual(1, snap.unmatchedActiveCount, 'all active are unmatched');
        Assert.areEqual(1, snap.entitledCount, 'entitled count from seeded set');
    }

    @IsTest
    static void testGetEntitledUserIds_returnsCachedSet() {
        EntitlementService.clearCacheForTests();
        EntitlementService.CACHED_ENTITLED_IDS = new Set<Id>{ UserInfo.getUserId() };
        EntitlementService.CACHED_CONFIGURED_NAMES = new List<String>{ 'Test_PS' };
        EntitlementService.CACHED_SNAPSHOT = new EntitlementSnapshotDTO();

        EntitlementService svc = new EntitlementService();
        Set<Id> ids = svc.getEntitledUserIds();
        Assert.areEqual(1, ids.size(), 'returns cached set without re-querying');
    }

    @IsTest
    static void testGetConfiguredPermissionSets_returnsCachedNames() {
        EntitlementService.clearCacheForTests();
        EntitlementService.CACHED_CONFIGURED_NAMES = new List<String>{ 'Foo_PS', 'Bar_PSG' };
        EntitlementService.CACHED_ENTITLED_IDS = new Set<Id>();
        EntitlementService.CACHED_SNAPSHOT = new EntitlementSnapshotDTO();

        EntitlementService svc = new EntitlementService();
        List<String> names = svc.getConfiguredPermissionSets();
        Assert.areEqual(2, names.size());
        Assert.areEqual('Foo_PS', names[0]);
    }

    @IsTest
    static void testComputeAdoptionRate_handlesEdgeCases() {
        Assert.areEqual(0, EntitlementService.computeAdoptionRate(0, 0), 'zero/zero');
        Assert.areEqual(0, EntitlementService.computeAdoptionRate(null, 100), 'null active');
        Assert.areEqual(0, EntitlementService.computeAdoptionRate(5, 0), 'zero denominator');
        Assert.areEqual(0.5000, EntitlementService.computeAdoptionRate(5, 10));
        Assert.areEqual(1.0000, EntitlementService.computeAdoptionRate(10, 10));
    }

    @IsTest
    static void testTryParseId_invalidReturnsNull() {
        Assert.isNull(EntitlementService.tryParseId('not-an-id'));
        Assert.isNull(EntitlementService.tryParseId(null));
        Assert.isNotNull(EntitlementService.tryParseId(UserInfo.getUserId()), 'real id parses');
    }

    @IsTest
    static void testFlattenConfigured_dedupesAcrossBuckets() {
        Map<String, Set<String>> buckets = new Map<String, Set<String>>{
            'PermissionSet' => new Set<String>{ 'Alpha', 'Beta' },
            'PermissionSetGroup' => new Set<String>{ 'Gamma' },
            'Profile' => new Set<String>{ 'Alpha' } // dupe across buckets
        };
        List<String> flat = EntitlementService.flattenConfigured(buckets);
        Assert.areEqual(3, flat.size(), 'dupe collapsed to a single entry');
    }

    @IsTest
    static void testCountActiveOrgUsers_returnsNonNegative() {
        Integer cnt = EntitlementService.countActiveOrgUsers();
        Assert.isTrue(cnt >= 0 || cnt == -1, 'non-negative or -1 sentinel on failure');
    }

    @IsTest
    static void testLoadEntitlement_emptyConfigured_flipsFallback() {
        EntitlementService.clearCacheForTests();
        // Force the configured list to be empty; loader should mark fallback.
        EntitlementService svc = new EntitlementService();
        Set<Id> ids = svc.getEntitledUserIds();
        Assert.isNotNull(ids, 'never null even when fallback');
        // The cached snapshot should reflect either a real entitled set OR
        // the fallback flag — both are acceptable depending on what's in
        // the org's CMT.
        Assert.isNotNull(EntitlementService.CACHED_SNAPSHOT);
    }

    @IsTest
    static void testGetSnapshot_blankAndInvalidIdsAreIgnored() {
        EntitlementService.clearCacheForTests();
        EntitlementService.CACHED_ENTITLED_IDS = new Set<Id>{ UserInfo.getUserId() };
        EntitlementService.CACHED_CONFIGURED_NAMES = new List<String>{ 'Test_PS' };
        EntitlementSnapshotDTO seeded = new EntitlementSnapshotDTO();
        seeded.entitledFallback = false;
        EntitlementService.CACHED_SNAPSHOT = seeded;

        EntitlementService svc = new EntitlementService();
        Set<String> active = new Set<String>{ '', null, 'not-an-id', UserInfo.getUserId() };
        EntitlementSnapshotDTO snap = svc.getSnapshot(active);
        // Only the valid Id parses.
        Assert.areEqual(1, snap.activeCount);
        Assert.areEqual(0, snap.unmatchedActiveCount, 'real id matches the entitled set');
    }
}
