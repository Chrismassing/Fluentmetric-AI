/**
 * Tests for AiWalletDAO.
 *
 * The Wallet DLO (TenantEnrichedUsageEvent__dll) is org-dependent: it exists
 * in Wallet-provisioned production orgs (e.g. cvk-dev) but not in scratch
 * orgs, sandboxes, or trial orgs. Tests must therefore work either way:
 *   - We pre-seed `availabilityCache` to bypass the live probe, so tests
 *     exercise the DAO's behaviour deterministically regardless of the
 *     org's actual Wallet state.
 *   - Where we DO call the live probe we only assert "no exception" + cache
 *     populated, never a specific Boolean value.
 *
 * Pure-Apex helpers (`toDecimal`, `resolveGroupField`, `aggregateTagRows`,
 * `mapAggregates`) are exercised directly via `@TestVisible` to push line
 * coverage into branches the live path may never reach.
 */
@IsTest
private class AiWalletDAOTest {
    private static void resetCache() {
        AiWalletDAO.availabilityCache = null;
    }

    // ───────── isWalletAvailable — probe runs and populates cache ────────

    @IsTest
    static void isWalletAvailable_populatesCacheEitherWay() {
        resetCache();
        AiWalletDAO dao = new AiWalletDAO();

        Test.startTest();
        Boolean first = dao.isWalletAvailable();
        Boolean second = dao.isWalletAvailable();
        Test.stopTest();

        // The actual value depends on whether the org has Wallet provisioned —
        // we only assert (a) no exception, (b) cache populated, (c) repeat
        // calls return the same answer.
        Assert.isNotNull(AiWalletDAO.availabilityCache, 'cache populated after first probe');
        Assert.areEqual(first, second, 'second call hits the cache, returns same value');
    }

    @IsTest
    static void isWalletAvailable_honorsPreSeededCacheTrue() {
        AiWalletDAO.availabilityCache = true;
        AiWalletDAO dao = new AiWalletDAO();
        Assert.isTrue(dao.isWalletAvailable(), 'pre-seeded cache wins — does not re-probe');
    }

    @IsTest
    static void isWalletAvailable_honorsPreSeededCacheFalse() {
        AiWalletDAO.availabilityCache = false;
        AiWalletDAO dao = new AiWalletDAO();
        Assert.isFalse(dao.isWalletAvailable(), 'pre-seeded false cache wins — does not re-probe');
    }

    // ───────── Public methods short-circuit when Wallet absent ───────────
    //
    // We *force* the no-Wallet path by seeding `availabilityCache = false`
    // before each call, regardless of the org's actual Wallet state. This
    // gives deterministic coverage of the early-return branches.

    @IsTest
    static void publicMethods_returnSafeDefaultsWhenWalletAbsent() {
        AiWalletDAO.availabilityCache = false;
        AiWalletDAO dao = new AiWalletDAO();
        DateTime startDt = DateTime.now().addDays(-7);
        DateTime endDt = DateTime.now();

        Test.startTest();
        Decimal total = dao.getTotalFlexCredits(startDt, endDt);
        List<WalletAggregateDTO> agg = dao.getFlexCreditAggregates(startDt, endDt, AiWalletDAO.GROUP_BY_FEATURE);
        List<WalletAggregateDTO> byPrompt = dao.getFlexCreditByPrompt(startDt, endDt);
        List<WalletAggregateDTO> byUser = dao.getFlexCreditByUser(startDt, endDt);
        List<WalletAggregateDTO> byTag = dao.getFlexCreditByCustomTag(startDt, endDt);
        Test.stopTest();

        Assert.isNull(total, 'getTotalFlexCredits returns null when DLO missing');
        Assert.areEqual(0, agg.size(), 'aggregates empty');
        Assert.areEqual(0, byPrompt.size(), 'byPrompt empty');
        Assert.areEqual(0, byUser.size(), 'byUser empty');
        Assert.areEqual(0, byTag.size(), 'byCustomTag empty');
    }

    @IsTest
    static void getFlexCreditAggregates_unknownGroupReturnsEmpty() {
        AiWalletDAO.availabilityCache = true;
        AiWalletDAO dao = new AiWalletDAO();
        // groupBy = DATA_SPACE → resolveGroupField returns null → empty list
        List<WalletAggregateDTO> rows = dao.getFlexCreditAggregates(
            DateTime.now().addDays(-1),
            DateTime.now(),
            AiWalletDAO.GROUP_BY_DATA_SPACE
        );
        Assert.areEqual(0, rows.size(), 'DATA_SPACE has no direct group field');

        rows = dao.getFlexCreditAggregates(DateTime.now().addDays(-1), DateTime.now(), null);
        Assert.areEqual(0, rows.size(), 'null groupBy returns empty');

        rows = dao.getFlexCreditAggregates(DateTime.now().addDays(-1), DateTime.now(), 'BOGUS');
        Assert.areEqual(0, rows.size(), 'unknown groupBy returns empty');
    }

    // ───────── WalletAggregateDTO — constructor coverage ────────────────

    @IsTest
    static void walletAggregateDTO_defaultsFlexCreditsToZero() {
        WalletAggregateDTO dto = new WalletAggregateDTO();
        Assert.areEqual(0, dto.flexCredits, 'constructor zero-init');
        dto.groupKey = 'k';
        dto.groupLabel = 'L';
        dto.userId = 'u';
        dto.resourceIdOrApiName = 'r';
        dto.rootResourceIdOrApiName = 'rr';
        dto.resourceType = 'rt';
        dto.featureDeveloperName = 'f';
        dto.usageType = 'ut';
        dto.dataSpace = 'ds';
        dto.additionalInfoJson = '{}';
        dto.customTagKey = 'ck';
        dto.customTagValue = 'cv';
        Assert.areEqual('k', dto.groupKey);
    }

    // ───────── toDecimal — type-coercion branches ────────────────────────

    @IsTest
    static void toDecimal_handlesEveryNumericType() {
        Assert.areEqual(0, AiWalletDAO.toDecimal(null), 'null → 0');
        Assert.areEqual(Decimal.valueOf('1.5'), AiWalletDAO.toDecimal(Decimal.valueOf('1.5')), 'Decimal pass-through');
        Assert.areEqual(Decimal.valueOf(42), AiWalletDAO.toDecimal(42), 'Integer → Decimal');
        Assert.areEqual(Decimal.valueOf(7L), AiWalletDAO.toDecimal((Long) 7), 'Long → Decimal');
        // Doubles are coerced via Decimal.valueOf which preserves the underlying value;
        // we don't assert exact equality due to floating-point noise — just that it parses.
        Assert.areNotEqual(null, AiWalletDAO.toDecimal((Double) 3.14), 'Double parses');
        Assert.areEqual(Decimal.valueOf('99'), AiWalletDAO.toDecimal('99'), 'numeric String parses');
        Assert.areEqual(0, AiWalletDAO.toDecimal('not-a-number'), 'non-numeric String → 0 (fallback)');
    }

    // ───────── resolveGroupField — every branch ──────────────────────────

    @IsTest
    static void resolveGroupField_routesEveryGroupBy() {
        AiWalletDAO dao = new AiWalletDAO();
        Assert.areEqual(AiWalletDAO.F_RESOURCE_ID_OR_NAME, dao.resolveGroupField(AiWalletDAO.GROUP_BY_RESOURCE));
        Assert.areEqual(
            AiWalletDAO.F_ROOT_RESOURCE_ID_OR_NAME,
            dao.resolveGroupField(AiWalletDAO.GROUP_BY_ROOT_RESOURCE)
        );
        Assert.areEqual(AiWalletDAO.F_FEATURE_DEV_NAME, dao.resolveGroupField(AiWalletDAO.GROUP_BY_FEATURE));
        Assert.areEqual(AiWalletDAO.F_USAGE_TYPE, dao.resolveGroupField(AiWalletDAO.GROUP_BY_USAGE_TYPE));
        Assert.isNull(dao.resolveGroupField(AiWalletDAO.GROUP_BY_DATA_SPACE), 'data space is JSON-derived');
        Assert.isNull(dao.resolveGroupField(null));
        Assert.isNull(dao.resolveGroupField(''));
    }

    // ───────── aggregateTagRows — empty/null inputs ──────────────────────

    @IsTest
    static void aggregateTagRows_emptyAndNullInputs() {
        AiWalletDAO dao = new AiWalletDAO();
        Assert.areEqual(0, dao.aggregateTagRows(null).size(), 'null rows → empty');
        Assert.areEqual(0, dao.aggregateTagRows(new List<SObject>()).size(), 'empty rows → empty');
    }

    // ───────── mapAggregates — null / empty ────────────────────────────

    @IsTest
    static void mapAggregates_handlesNullAndEmpty() {
        AiWalletDAO dao = new AiWalletDAO();
        Assert.areEqual(0, dao.mapAggregates(null, AiWalletDAO.GROUP_BY_FEATURE).size());
        Assert.areEqual(0, dao.mapAggregates(new List<AggregateResult>(), AiWalletDAO.GROUP_BY_FEATURE).size());
    }

    // ───────── Live SOQL paths — drive the try-blocks regardless of org ─
    //
    // Pre-seeding `availabilityCache = true` lets the DAO skip the live
    // probe and execute the SOQL try blocks. In Wallet-enabled orgs the
    // queries succeed and return real rows; in scratch orgs they throw
    // and the catch returns null/empty. Either path is valid coverage —
    // we only assert "no exception" and that the return type is sane.

    @IsTest
    static void allPublicMethods_executeSoqlBranchesWhenCacheTrue() {
        AiWalletDAO.availabilityCache = true;
        AiWalletDAO dao = new AiWalletDAO();
        DateTime startDt = DateTime.now().addDays(-1);
        DateTime endDt = DateTime.now();

        Test.startTest();
        // getTotalFlexCredits — succeeds (Decimal) or fails (null). Either is fine.
        dao.getTotalFlexCredits(startDt, endDt);

        // Every valid groupBy reaches the SOQL try block.
        for (
            String g : new List<String>{
                AiWalletDAO.GROUP_BY_RESOURCE,
                AiWalletDAO.GROUP_BY_ROOT_RESOURCE,
                AiWalletDAO.GROUP_BY_FEATURE,
                AiWalletDAO.GROUP_BY_USAGE_TYPE
            }
        ) {
            List<WalletAggregateDTO> rows = dao.getFlexCreditAggregates(startDt, endDt, g);
            Assert.isNotNull(rows, g + ' returns a list (possibly empty)');
        }
        Assert.isNotNull(dao.getFlexCreditByPrompt(startDt, endDt));
        Assert.isNotNull(dao.getFlexCreditByUser(startDt, endDt));
        Assert.isNotNull(dao.getFlexCreditByCustomTag(startDt, endDt));
        Test.stopTest();
    }

    // ───────── Forced-failure path — drives every catch branch ──────────
    //
    // `forceFailForTests` makes every Wallet SOQL call throw, regardless of
    // whether the org has the DLO. That covers (a) the probe's catch branch
    // (cache := false, no-DLO path) and (b) every public method's catch
    // branch (returns null/empty). Together these are the lines that the
    // happy-path queries in cvk-dev never touch.

    @IsTest
    static void probe_catchBranchFlipsCacheFalse() {
        resetCache();
        AiWalletDAO.forceFailForTests = true;
        try {
            AiWalletDAO dao = new AiWalletDAO();
            Boolean avail = dao.isWalletAvailable();
            Assert.isFalse(avail, 'forced failure → probe lands in catch → cache=false');
            Assert.areEqual(false, AiWalletDAO.availabilityCache, 'cache populated false');
        } finally {
            AiWalletDAO.forceFailForTests = false;
            resetCache();
        }
    }

    @IsTest
    static void allPublicMethods_returnSafeDefaultsWhenSoqlThrows() {
        AiWalletDAO.availabilityCache = true; // bypass the probe
        AiWalletDAO.forceFailForTests = true;
        try {
            AiWalletDAO dao = new AiWalletDAO();
            DateTime startDt = DateTime.now().addDays(-1);
            DateTime endDt = DateTime.now();

            Test.startTest();
            Assert.isNull(dao.getTotalFlexCredits(startDt, endDt), 'forced throw → null');
            Assert.areEqual(
                0,
                dao.getFlexCreditAggregates(startDt, endDt, AiWalletDAO.GROUP_BY_FEATURE).size(),
                'aggregates → empty'
            );
            Assert.areEqual(0, dao.getFlexCreditByPrompt(startDt, endDt).size(), 'byPrompt → empty');
            Assert.areEqual(0, dao.getFlexCreditByUser(startDt, endDt).size(), 'byUser → empty');
            Assert.areEqual(0, dao.getFlexCreditByCustomTag(startDt, endDt).size(), 'byTag → empty');
            Test.stopTest();
        } finally {
            AiWalletDAO.forceFailForTests = false;
        }
    }
}
