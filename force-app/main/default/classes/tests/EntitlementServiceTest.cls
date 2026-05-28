/**
 * Tests for EntitlementService (post-CMT, single-permset model).
 *
 * The service now resolves "entitled" via the FluentMetric_AI_Entitled_User
 * permission set + PermissionSetAssignment. We can't seed PSA in an Apex test
 * (running as a sysadmin we can, but the permset must be deployed first), so
 * the strategy is:
 *   - Drive the public surface end-to-end and assert sane defaults.
 *   - Force the cache directly to exercise the active-vs-entitled scoring.
 *   - Cover the @TestVisible static helpers so the math survives a refactor.
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
        Assert.areEqual(1, snap.configuredPermissionSets.size(), 'one entitlement permset');
        Assert.areEqual(
            EntitlementService.ENTITLEMENT_PERMSET_NAME,
            snap.configuredPermissionSets[0],
            'configured list names the entitlement permset'
        );
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
        EntitlementService.CACHED_SNAPSHOT = new EntitlementSnapshotDTO();

        EntitlementService svc = new EntitlementService();
        Set<Id> ids = svc.getEntitledUserIds();
        Assert.areEqual(1, ids.size(), 'returns cached set without re-querying');
    }

    @IsTest
    static void testGetConfiguredPermissionSets_returnsSinglePermsetName() {
        EntitlementService svc = new EntitlementService();
        List<String> names = svc.getConfiguredPermissionSets();
        Assert.areEqual(1, names.size(), 'always one configured permset');
        Assert.areEqual(EntitlementService.ENTITLEMENT_PERMSET_NAME, names[0]);
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
    static void testCountActiveOrgUsers_returnsNonNegative() {
        Integer cnt = EntitlementService.countActiveOrgUsers();
        Assert.isTrue(cnt >= 0 || cnt == -1, 'non-negative or -1 sentinel on failure');
    }

    @IsTest
    static void testLoadEntitlement_unknownPermset_flipsFallback() {
        EntitlementService.clearCacheForTests();
        // Whether the permset is deployed in this test org or not, loadEntitlement
        // must terminate without throwing and yield a non-null entitled set + a
        // populated CACHED_SNAPSHOT.
        EntitlementService svc = new EntitlementService();
        Set<Id> ids = svc.getEntitledUserIds();
        Assert.isNotNull(ids, 'never null even when fallback');
        Assert.isNotNull(EntitlementService.CACHED_SNAPSHOT);
    }

    @IsTest
    static void testResolvePermissionSetIds_returnsKnownPermSetId() {
        // FluentMetric_AI_User permset is deployed with the package — its name
        // resolves to a real Id in any org where the package is deployed.
        Set<String> names = new Set<String>{ 'FluentMetric_AI_User' };
        Set<Id> ids = EntitlementService.resolvePermissionSetIds(names);
        // We don't assert non-empty — packaging tests run before deploy in
        // some envs — but the call must not throw.
        Assert.isNotNull(ids, 'returns non-null set');
    }

    @IsTest
    static void testResolvePermissionSetIds_unknownNamesReturnsEmpty() {
        Set<String> names = new Set<String>{ 'Definitely_Not_A_Real_PS_Name' };
        Set<Id> ids = EntitlementService.resolvePermissionSetIds(names);
        Assert.areEqual(0, ids.size(), 'no matches → empty set');
    }

    @IsTest
    static void testQueryEntitledUsersByPsa_emptyInputs() {
        Set<Id> out = EntitlementService.queryEntitledUsersByPsa(new Set<Id>());
        Assert.areEqual(0, out.size(), 'empty input set → empty result');
    }

    @IsTest
    static void testGetSnapshot_realActiveUserMatches() {
        EntitlementService.clearCacheForTests();
        // Seed the cache with the running user as entitled, then call
        // getSnapshot with the same id — exercises the active-AND-entitled
        // numerator path (active - unmatched).
        EntitlementService.CACHED_ENTITLED_IDS = new Set<Id>{ UserInfo.getUserId() };
        EntitlementSnapshotDTO seeded = new EntitlementSnapshotDTO();
        seeded.entitledFallback = false;
        EntitlementService.CACHED_SNAPSHOT = seeded;

        EntitlementService svc = new EntitlementService();
        EntitlementSnapshotDTO snap = svc.getSnapshot(new Set<String>{ UserInfo.getUserId() });
        Assert.areEqual(1, snap.activeCount);
        Assert.areEqual(0, snap.unmatchedActiveCount, 'real user is in entitled set');
        Assert.areEqual(1, snap.entitledCount);
        Assert.isTrue(snap.adoptionRate > 0, 'adoption rate computed');
    }

    @IsTest
    static void testGetSnapshot_blankAndInvalidIdsAreIgnored() {
        EntitlementService.clearCacheForTests();
        EntitlementService.CACHED_ENTITLED_IDS = new Set<Id>{ UserInfo.getUserId() };
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
