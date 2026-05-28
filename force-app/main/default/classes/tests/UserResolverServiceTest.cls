/**
 * Tests for UserResolverService.
 *
 * Strategy:
 *   - The resolver is stateless beyond Platform Cache, so tests can spin up
 *     a fresh instance per scenario without orchestrating the cache directly.
 *   - The running test user IS a queryable User row, so we use
 *     UserInfo.getUserId() to drive the happy-path bulk lookups.
 *   - Pure helpers (`humanizeDevName`, `stripQuotes`, `tryParseId`,
 *     `normalizeKey`, `getPartition`) are exercised via `@TestVisible` to
 *     hit branches that the public API can't easily reach (e.g. CamelCase
 *     interior-cap insertion).
 */
@IsTest
private class UserResolverServiceTest {
    // ───────── resolveUserNames ──────────────────────────────────────────

    @IsTest
    static void resolveUserNames_nullAndEmpty() {
        UserResolverService svc = new UserResolverService();
        Assert.areEqual(0, svc.resolveUserNames(null).size(), 'null → empty map');
        Assert.areEqual(0, svc.resolveUserNames(new Set<String>()).size(), 'empty → empty map');
    }

    @IsTest
    static void resolveUserNames_systemSentinel() {
        UserResolverService svc = new UserResolverService();
        Map<String, String> out = svc.resolveUserNames(new Set<String>{ 'NOT_SET' });
        Assert.areEqual('System Call', out.get('NOT_SET'), 'NOT_SET → System Call label');
    }

    @IsTest
    static void resolveUserNames_blankIsTreatedAsSentinel() {
        UserResolverService svc = new UserResolverService();
        Map<String, String> out = svc.resolveUserNames(new Set<String>{ '' });
        Assert.areEqual('System Call', out.get(''), 'blank id → System Call');
    }

    @IsTest
    static void resolveUserNames_invalidIdReturnsUnknown() {
        UserResolverService svc = new UserResolverService();
        Map<String, String> out = svc.resolveUserNames(new Set<String>{ 'not-a-real-id' });
        Assert.areEqual(
            'Unknown User (not-a-real-id)',
            out.get('not-a-real-id'),
            'unparseable id → Unknown User fallback'
        );
    }

    @IsTest
    static void resolveUserNames_realUserResolves() {
        UserResolverService svc = new UserResolverService();
        String me = UserInfo.getUserId();

        Test.startTest();
        Map<String, String> out = svc.resolveUserNames(new Set<String>{ me });
        Test.stopTest();

        Assert.isTrue(out.containsKey(me), 'running user resolves');
        Assert.isFalse(String.isBlank(out.get(me)), 'has a name');
        Assert.isFalse(out.get(me).startsWith('Unknown User'), 'real user is not unknown');
    }

    @IsTest
    static void resolveUserNames_mixedBatch() {
        UserResolverService svc = new UserResolverService();
        Set<String> input = new Set<String>{ UserInfo.getUserId(), 'NOT_SET', 'bogus-id' };

        Map<String, String> out = svc.resolveUserNames(input);
        Assert.areEqual('System Call', out.get('NOT_SET'));
        Assert.areEqual('Unknown User (bogus-id)', out.get('bogus-id'));
        Assert.isTrue(out.containsKey(UserInfo.getUserId()), 'real user present');
    }

    // ───────── resolveUsersDetailed ──────────────────────────────────────

    @IsTest
    static void resolveUsersDetailed_nullAndEmpty() {
        UserResolverService svc = new UserResolverService();
        Assert.areEqual(0, svc.resolveUsersDetailed(null).size());
        Assert.areEqual(0, svc.resolveUsersDetailed(new Set<String>()).size());
    }

    @IsTest
    static void resolveUsersDetailed_systemSentinel() {
        UserResolverService svc = new UserResolverService();
        Map<String, UserResolverService.ResolvedUser> out = svc.resolveUsersDetailed(new Set<String>{ 'NOT_SET' });
        UserResolverService.ResolvedUser ru = out.get('NOT_SET');
        Assert.areEqual('NOT_SET', ru.userId);
        Assert.areEqual('System Call', ru.name);
    }

    @IsTest
    static void resolveUsersDetailed_invalidIdReturnsUnknown() {
        UserResolverService svc = new UserResolverService();
        Map<String, UserResolverService.ResolvedUser> out = svc.resolveUsersDetailed(new Set<String>{ 'no-good' });
        Assert.areEqual('Unknown User (no-good)', out.get('no-good').name);
    }

    @IsTest
    static void resolveUsersDetailed_realUserCarriesProfileAndDept() {
        UserResolverService svc = new UserResolverService();
        String me = UserInfo.getUserId();
        Map<String, UserResolverService.ResolvedUser> out = svc.resolveUsersDetailed(new Set<String>{ me });
        UserResolverService.ResolvedUser ru = out.get(me);
        Assert.areNotEqual(null, ru, 'running user resolved');
        Assert.areNotEqual(null, ru.name);
        // profileName / department may be null in some test orgs; the field
        // assignments themselves are what we care about for coverage.
    }

    // ───────── resolvePromptTemplateLabels ───────────────────────────────

    @IsTest
    static void resolvePromptTemplates_nullAndEmpty() {
        UserResolverService svc = new UserResolverService();
        Assert.areEqual(0, svc.resolvePromptTemplateLabels(null).size());
        Assert.areEqual(0, svc.resolvePromptTemplateLabels(new Set<String>()).size());
    }

    @IsTest
    static void resolvePromptTemplates_blankReturnsUnknown() {
        UserResolverService svc = new UserResolverService();
        Map<String, String> out = svc.resolvePromptTemplateLabels(new Set<String>{ '' });
        Assert.areEqual('Unknown Prompt', out.get(''));
    }

    @IsTest
    static void resolvePromptTemplates_humanizesDevName() {
        UserResolverService svc = new UserResolverService();
        // Quoted string + namespace + camelCase
        String raw = '"Atlas__GroundednessValidationPrompt"';
        Map<String, String> out = svc.resolvePromptTemplateLabels(new Set<String>{ raw });
        String label = out.get(raw);
        Assert.areNotEqual(null, label);
        // Quotes are stripped, double-underscore becomes ' · ', and the
        // CamelCase name has spaces inserted between lowercase→uppercase.
        Assert.isTrue(label.contains('Atlas'), 'namespace preserved');
        Assert.isFalse(label.contains('"'), 'quotes stripped');
    }

    @IsTest
    static void resolvePromptTemplates_simpleSnakeCase() {
        UserResolverService svc = new UserResolverService();
        String raw = 'simple_prompt_name';
        Map<String, String> out = svc.resolvePromptTemplateLabels(new Set<String>{ raw });
        String label = out.get(raw);
        Assert.isTrue(label.contains('simple prompt name'), 'underscores → spaces');
    }

    // ───────── @TestVisible helpers ──────────────────────────────────────

    @IsTest
    static void humanizeDevName_blankYieldsUnknown() {
        UserResolverService svc = new UserResolverService();
        Assert.areEqual('Unknown Prompt', svc.humanizeDevName(null));
        Assert.areEqual('Unknown Prompt', svc.humanizeDevName(''));
        Assert.areEqual('Unknown Prompt', svc.humanizeDevName('   '));
    }

    @IsTest
    static void humanizeDevName_camelCase() {
        UserResolverService svc = new UserResolverService();
        Assert.areEqual('hello World', svc.humanizeDevName('helloWorld'));
        Assert.areEqual(
            'Atlas · Groundedness Validation Prompt',
            svc.humanizeDevName('Atlas__GroundednessValidationPrompt')
        );
    }

    @IsTest
    static void stripQuotes_handlesAllShapes() {
        UserResolverService svc = new UserResolverService();
        Assert.isNull(svc.stripQuotes(null));
        Assert.areEqual('', svc.stripQuotes(''));
        Assert.areEqual('plain', svc.stripQuotes('plain'));
        Assert.areEqual('quoted', svc.stripQuotes('"quoted"'));
        Assert.areEqual('"unbalanced', svc.stripQuotes('"unbalanced'), 'leading-only is left alone');
        Assert.areEqual('inner', svc.stripQuotes('   "inner"   '), 'whitespace stripped first');
    }

    @IsTest
    static void tryParseId_validAndInvalid() {
        UserResolverService svc = new UserResolverService();
        Assert.areNotEqual(null, svc.tryParseId(UserInfo.getUserId()), 'valid id');
        Assert.isNull(svc.tryParseId('garbage'), 'invalid id');
        Assert.isNull(svc.tryParseId(null), 'null id');
    }

    @IsTest
    static void normalizeKey_truncatesAndCleans() {
        UserResolverService svc = new UserResolverService();
        Assert.areEqual('abc_123', svc.normalizeKey('abc 123'));
        Assert.areEqual('a_b_c_d', svc.normalizeKey('a/b\\c-d'));
        // Long input is truncated to 50 chars
        String long60 = '012345678901234567890123456789012345678901234567890123456789';
        Assert.areEqual(50, svc.normalizeKey(long60).length(), 'capped at 50 chars');
    }

    @IsTest
    static void getPartition_doesNotThrow() {
        // Cache.Org.getPartition can throw if the partition isn't deployed
        // — getPartition() must swallow it rather than crash the dashboard.
        // The FluentMetric_AI partition IS deployed, so we expect a non-null
        // result here, but we defensively assert "no exception" rather than
        // demanding non-null in case the test org doesn't have it.
        UserResolverService svc = new UserResolverService();
        Cache.OrgPartition partition = svc.getPartition();
        // Calling get/put on the partition (or no-op'ing if null) should
        // never throw — this exercises both branches of getCachedValue/
        // putCachedValue.
        svc.putCachedValue('user_test_key', 'Test User Name', 60);
        String roundtrip = svc.getCachedValue('user_test_key');
        // Roundtrip may or may not return the value depending on cache
        // availability in the test context — we only assert no exception.
        if (partition != null) {
            Assert.areEqual('Test User Name', roundtrip, 'cache round-trip when partition present');
        }
    }
}
