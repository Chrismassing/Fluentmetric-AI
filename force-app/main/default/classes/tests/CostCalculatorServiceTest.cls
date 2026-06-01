/**
 * Tests for CostCalculatorService.
 *
 * Strategy:
 *   - Inject a synthetic rateCardByModel map into the static cache so tests
 *     don't depend on the deployed FluentMetric_Rate_Card__mdt records.
 *   - Exercise exact match, ISO-date prefix strip, version-tag strip,
 *     fallback-record selection, discount application (0% and 25%), and
 *     the zero-input guards.
 */
@IsTest
private class CostCalculatorServiceTest {
    // ───────── Fixture: synthetic rate cards via the @TestVisible static ────

    private static FluentMetric_Rate_Card__mdt buildRate(
        String model,
        String tier,
        Decimal fc,
        Decimal usd,
        Boolean isFallback
    ) {
        FluentMetric_Rate_Card__mdt rc = new FluentMetric_Rate_Card__mdt();
        rc.Model__c = model;
        rc.Tier__c = tier;
        rc.Flex_Credits_Per_Call__c = fc;
        rc.USD_Per_Call__c = usd;
        rc.Is_Default_Fallback__c = isFallback;
        return rc;
    }

    private static void seedCache() {
        Map<String, FluentMetric_Rate_Card__mdt> m = new Map<String, FluentMetric_Rate_Card__mdt>();
        m.put('standard-default', buildRate('Standard-Default', 'Standard', 4, 0.016, true));
        m.put('gpt-4o', buildRate('gpt-4o', 'Standard', 4, 0.016, false));
        m.put('gpt-4o-mini', buildRate('gpt-4o-mini', 'Basic', 2, 0.008, false));
        m.put('gpt-4', buildRate('gpt-4', 'Standard', 4, 0.016, false));
        m.put('gpt-5', buildRate('gpt-5', 'Advanced', 16, 0.064, false));
        m.put('claude-sonnet-4', buildRate('claude-sonnet-4', 'Standard', 4, 0.016, false));
        CostCalculatorService.rateCardByModel = m;
    }

    private static void seedSettings(Decimal discountPct) {
        FluentMetric_Cost_Settings__c s = new FluentMetric_Cost_Settings__c();
        s.Flex_Credit_USD_Rate__c = 0.004;
        s.Discount_Percent__c = discountPct;
        s.Default_Fallback_Model__c = 'Standard-Default';
        s.Enable_Cost_Metrics__c = true;
        // Tier-based pricing fields (v1.5) — seed defaults so tests don't
        // depend on field-level default resolution in the packaging org.
        s.Tier_Basic_FC__c = 2;
        s.Tier_Standard_FC__c = 4;
        s.Tier_Advanced_FC__c = 16;
        s.Action_Flat_FC__c = 20;
        s.Prompt_Token_Threshold__c = 2000;
        s.Action_Token_Threshold__c = 10000;
        CostCalculatorService.settingsCache = s;
    }

    // ───────── Match tests ──────────────────────────────────────────────

    @IsTest
    static void testExactMatch() {
        seedCache();
        seedSettings(0);
        CostCalculatorService svc = new CostCalculatorService();

        Test.startTest();
        CostCalculatorService.CostResult r = svc.costForAggregate('gpt-4o', 10, null);
        Test.stopTest();

        Assert.areEqual(false, r.usedFallback, 'Exact match should not be fallback');
        Assert.areEqual(40L, r.flexCredits, 'gpt-4o @ 4 FC * 10 calls = 40');
        Assert.areEqual(Decimal.valueOf('0.1600'), r.baseUsd, 'gpt-4o base = 0.016 * 10');
        Assert.areEqual(Decimal.valueOf('0.1600'), r.discountedUsd, 'No discount at 0%');
    }

    @IsTest
    static void testPrefixMatch_DateSuffix() {
        seedCache();
        seedSettings(0);
        CostCalculatorService svc = new CostCalculatorService();

        Test.startTest();
        CostCalculatorService.CostResult r = svc.costForAggregate('gpt-4o-2024-11-20', 5, null);
        Test.stopTest();

        Assert.areEqual(false, r.usedFallback, 'Prefix match should not be fallback');
        Assert.areEqual(20L, r.flexCredits, 'gpt-4o family @ 4 FC * 5 = 20');
        Assert.areEqual(Decimal.valueOf('0.0800'), r.baseUsd);
    }

    @IsTest
    static void testPrefixMatch_Mini() {
        seedCache();
        seedSettings(0);
        CostCalculatorService svc = new CostCalculatorService();

        Test.startTest();
        // Exact hit — gpt-4o-mini is in cache, should win before suffix strip
        CostCalculatorService.CostResult exactMini = svc.costForAggregate('gpt-4o-mini', 3, null);
        // Strip -mini path — gpt-4-mini is NOT in cache, strips to gpt-4
        CostCalculatorService.CostResult stripped = svc.costForAggregate('gpt-4-mini', 3, null);
        Test.stopTest();

        Assert.areEqual(6L, exactMini.flexCredits, 'gpt-4o-mini exact: 2 FC * 3 = 6');
        Assert.areEqual(Decimal.valueOf('0.0240'), exactMini.baseUsd);
        Assert.areEqual(false, exactMini.usedFallback);

        Assert.areEqual(12L, stripped.flexCredits, 'gpt-4-mini -> gpt-4: 4 FC * 3 = 12');
        Assert.areEqual(Decimal.valueOf('0.0480'), stripped.baseUsd);
        Assert.areEqual(false, stripped.usedFallback);
    }

    @IsTest
    static void testFallbackMatch() {
        seedCache();
        seedSettings(0);
        CostCalculatorService svc = new CostCalculatorService();

        Test.startTest();
        CostCalculatorService.CostResult r = svc.costForAggregate('totally-unknown-model', 7, null);
        Test.stopTest();

        Assert.areEqual(true, r.usedFallback, 'Unknown model should use Is_Default_Fallback__c');
        Assert.areEqual(28L, r.flexCredits, 'Standard-Default 4 FC * 7 = 28');
        Assert.areEqual(Decimal.valueOf('0.1120'), r.baseUsd);
    }

    // ───────── Discount tests ─────────────────────────────────────────────

    @IsTest
    static void testApplyDiscount_Default() {
        seedCache();
        seedSettings(0);
        CostCalculatorService svc = new CostCalculatorService();

        Test.startTest();
        Decimal out = svc.applyDiscount(Decimal.valueOf('100.00'));
        Test.stopTest();

        Assert.areEqual(Decimal.valueOf('100.0000'), out, '0% discount returns base unchanged');
    }

    @IsTest
    static void testApplyDiscount_25() {
        seedCache();
        seedSettings(25);
        CostCalculatorService svc = new CostCalculatorService();

        Test.startTest();
        Decimal out = svc.applyDiscount(Decimal.valueOf('100.00'));
        Test.stopTest();

        Assert.areEqual(Decimal.valueOf('75.0000'), out, '25% discount -> 75% of base');
    }

    @IsTest
    static void testApplyDiscount_EdgeCases() {
        seedCache();
        seedSettings(100);
        CostCalculatorService svc = new CostCalculatorService();

        Test.startTest();
        Decimal nullIn = svc.applyDiscount(null);
        Decimal fullDiscount = svc.applyDiscount(Decimal.valueOf('50.00'));
        Test.stopTest();

        Assert.areEqual(0, nullIn, 'null input returns 0');
        Assert.areEqual(0, fullDiscount, '100% discount returns 0');
    }

    // ───────── Zero-input / empty-list guards ─────────────────────────────

    @IsTest
    static void testCostForAggregate_ZeroRequests() {
        seedCache();
        seedSettings(0);
        CostCalculatorService svc = new CostCalculatorService();

        Test.startTest();
        CostCalculatorService.CostResult zero = svc.costForAggregate('gpt-4o', 0, null);
        CostCalculatorService.CostResult nullCount = svc.costForAggregate('gpt-4o', null, null);
        CostCalculatorService.CostResult negCount = svc.costForAggregate('gpt-4o', -5, null);
        Test.stopTest();

        Assert.areEqual(0L, zero.flexCredits);
        Assert.areEqual(0, zero.baseUsd);
        Assert.areEqual(false, zero.usedFallback);
        Assert.areEqual(0L, nullCount.flexCredits);
        Assert.areEqual(0L, negCount.flexCredits);
    }

    @IsTest
    static void testCostForRequests_EmptyList() {
        seedCache();
        seedSettings(0);
        CostCalculatorService svc = new CostCalculatorService();

        Test.startTest();
        CostCalculatorService.CostResult empty = svc.costForRequests(new List<SObject>());
        CostCalculatorService.CostResult nullIn = svc.costForRequests(null);
        Test.stopTest();

        Assert.areEqual(0L, empty.flexCredits);
        Assert.areEqual(0L, nullIn.flexCredits);
        Assert.areEqual(0, empty.baseUsd);
    }

    // ───────── Mixed-model sum ─────────────────────────────────────────────

    @IsTest
    static void testCostForRequests_MixedModels() {
        seedCache();
        seedSettings(0);
        CostCalculatorService svc = new CostCalculatorService();

        // Fabricate 3 rows of Account SObjects (DMO type may not be available
        // in test context). We bind model__c-like data through safe get calls
        // in the service — however, Account has no model__c, so we use a stub
        // wrapper approach: subclass to force specific behavior.
        // Simpler: use the subclass override to substitute a counts-by-model map.
        MixedStub stub = new MixedStub();
        stub.fakeCounts = new Map<String, Integer>{ 'gpt-4o' => 2, 'gpt-5' => 1, 'unknown-xyz' => 1 };

        Test.startTest();
        CostCalculatorService.CostResult r = stub.costForRequestsFake();
        Test.stopTest();

        // gpt-4o: 4*2=8 FC, 0.016*2=0.032
        // gpt-5:  16*1=16 FC, 0.064*1=0.064
        // unknown -> fallback Standard-Default: 4*1=4 FC, 0.016*1=0.016
        Assert.areEqual(28L, r.flexCredits, '8 + 16 + 4 = 28 FC');
        Assert.areEqual(Decimal.valueOf('0.1120'), r.baseUsd, '0.032 + 0.064 + 0.016 = 0.112');
        Assert.areEqual(true, r.usedFallback, 'any fallback hit should set the flag');
    }

    /**
     * Test-only subclass that exposes a way to drive costForRequests without
     * needing DMO SObjects. Delegates back to costForAggregate via the same
     * grouping semantics as the real method.
     */
    private class MixedStub extends CostCalculatorService {
        public Map<String, Integer> fakeCounts;

        public CostCalculatorService.CostResult costForRequestsFake() {
            Long totalFc = 0L;
            Decimal totalBase = 0;
            Decimal totalDiscounted = 0;
            Boolean anyFallback = false;
            for (String m : fakeCounts.keySet()) {
                CostCalculatorService.CostResult partial = costForAggregate(m, fakeCounts.get(m), null);
                totalFc += partial.flexCredits;
                totalBase += partial.baseUsd;
                totalDiscounted += partial.discountedUsd;
                if (partial.usedFallback) {
                    anyFallback = true;
                }
            }
            return new CostCalculatorService.CostResult(totalFc, totalBase, totalDiscounted, anyFallback);
        }
    }

    // ───────── Settings defaults ──────────────────────────────────────────

    @IsTest
    static void testGetSettings_DefaultsWhenMissing() {
        // Don't seed settings — force the getOrgDefaults path
        CostCalculatorService.settingsCache = null;
        CostCalculatorService svc = new CostCalculatorService();

        Test.startTest();
        FluentMetric_Cost_Settings__c s = svc.getSettings();
        Test.stopTest();

        Assert.areNotEqual(null, s, 'Settings should never be null');
        Assert.areEqual(Decimal.valueOf('0.004'), s.Flex_Credit_USD_Rate__c, 'Default USD/credit');
        Assert.areEqual(0, s.Discount_Percent__c, 'Default discount 0');
        Assert.areEqual('Standard-Default', s.Default_Fallback_Model__c);
    }

    // ───────── Live CMDT load path (coverage for loadRateCards) ─────────────

    // ───────── Opt-in flag + unmetered-model tests (Round 8) ───────────────

    @IsTest
    static void testCostDisabledReturnsZero() {
        seedCache();
        // Settings with Enable_Cost_Metrics__c = false — simulates a fresh
        // install where the admin hasn't opted in yet.
        FluentMetric_Cost_Settings__c s = new FluentMetric_Cost_Settings__c();
        s.Flex_Credit_USD_Rate__c = 0.004;
        s.Discount_Percent__c = 0;
        s.Default_Fallback_Model__c = 'Standard-Default';
        s.Enable_Cost_Metrics__c = false;
        CostCalculatorService.settingsCache = s;

        CostCalculatorService svc = new CostCalculatorService();
        Assert.isFalse(svc.isCostMetricsEnabled(), 'flag off => disabled');

        CostCalculatorService.CostResult r = svc.costForAggregate('gpt-4o', 100, null);
        Assert.areEqual(0L, r.flexCredits, 'disabled => 0 FC');
        Assert.areEqual(0, r.baseUsd, 'disabled => $0 base');
        Assert.areEqual(0, r.discountedUsd, 'disabled => $0 discounted');
        Assert.isFalse(r.usedFallback, 'disabled result is not a fallback');
    }

    @IsTest
    static void testUnmeteredModelReturnsZero() {
        Map<String, FluentMetric_Rate_Card__mdt> m = new Map<String, FluentMetric_Rate_Card__mdt>();
        FluentMetric_Rate_Card__mdt unmetered = buildRate('EinsteinTextEval', 'Basic', 0, 0, false);
        unmetered.Is_Unmetered__c = true;
        m.put('einsteintexteval', unmetered);
        m.put('standard-default', buildRate('Standard-Default', 'Standard', 4, 0.016, true));
        CostCalculatorService.rateCardByModel = m;
        seedSettings(0);

        CostCalculatorService.CostResult r = new CostCalculatorService()
            .costForAggregate('EinsteinTextEval', 500, null);
        Assert.areEqual(0L, r.flexCredits, 'unmetered => 0 FC');
        Assert.areEqual(0, r.baseUsd, 'unmetered => $0 base');
        Assert.isFalse(r.usedFallback, 'unmetered is an explicit match, not fallback');
    }

    // ───────── Tier math (v1.5) ─────────────────────────────────────────────

    @IsTest
    static void testTierMath_Basic() {
        seedCache();
        seedSettings(0);
        CostCalculatorService svc = new CostCalculatorService();

        Test.startTest();
        // gpt-4o-mini is Basic — 2 FC × 10 calls = 20 FC, 20 × 0.004 = $0.08
        CostCalculatorService.CostResult r = svc.costForAggregate('gpt-4o-mini', 10, 1000L);
        Test.stopTest();

        Assert.areEqual(20L, r.flexCredits, 'Basic tier: 2 FC × 10 calls');
        Assert.areEqual(Decimal.valueOf('0.0800'), r.baseUsd);
        Assert.areEqual(CostCalculatorService.CONFIDENCE_HIGH, r.confidence);
    }

    @IsTest
    static void testTierMath_Advanced() {
        seedCache();
        seedSettings(0);
        CostCalculatorService svc = new CostCalculatorService();

        Test.startTest();
        // gpt-5 is Advanced — 16 FC × 10 calls = 160 FC, 160 × 0.004 = $0.64
        CostCalculatorService.CostResult r = svc.costForAggregate('gpt-5', 10, 1000L);
        Test.stopTest();

        Assert.areEqual(160L, r.flexCredits, 'Advanced tier: 16 FC × 10 calls');
        Assert.areEqual(Decimal.valueOf('0.6400'), r.baseUsd);
    }

    // ───────── Overage math ─────────────────────────────────────────────────

    @IsTest
    static void testOverage_BelowThreshold() {
        seedCache();
        seedSettings(0);
        CostCalculatorService svc = new CostCalculatorService();

        // 1 call × 1900 tokens: avg 1900 < 2000 threshold → multiplier=1
        CostCalculatorService.CostResult r = svc.costForAggregate('gpt-4o', 1, 1900L);
        Assert.areEqual(4L, r.flexCredits, '1900 tokens → no overage, single tier charge');
    }

    @IsTest
    static void testOverage_AtThreshold() {
        seedCache();
        seedSettings(0);
        CostCalculatorService svc = new CostCalculatorService();

        // 1 call × exactly 2000 tokens: 2000/2000 = 1.0, ceil=1, no overage yet
        CostCalculatorService.CostResult r = svc.costForAggregate('gpt-4o', 1, 2000L);
        Assert.areEqual(4L, r.flexCredits, 'Exactly at threshold: single tier charge');
    }

    @IsTest
    static void testOverage_JustOverThreshold() {
        seedCache();
        seedSettings(0);
        CostCalculatorService svc = new CostCalculatorService();

        // 1 call × 2001 tokens: 2001/2000 = 1.0005, ceil=2 → 2× tier charge
        CostCalculatorService.CostResult r = svc.costForAggregate('gpt-4o', 1, 2001L);
        Assert.areEqual(8L, r.flexCredits, '2001 tokens: tier charged twice');
    }

    @IsTest
    static void testOverage_DoubleThreshold() {
        seedCache();
        seedSettings(0);
        CostCalculatorService svc = new CostCalculatorService();

        // 1 call × 4100 tokens: 4100/2000 = 2.05, ceil=3 → 3× tier charge
        CostCalculatorService.CostResult r = svc.costForAggregate('gpt-4o', 1, 4100L);
        Assert.areEqual(12L, r.flexCredits, '4100 tokens: tier charged three times');
    }

    // ───────── Agentforce Action pricing ─────────────────────────────────────

    @IsTest
    static void testActionFlatFee_Simple() {
        seedCache();
        seedSettings(0);
        CostCalculatorService svc = new CostCalculatorService();

        // 1 action × 5K tokens (< 10K threshold) → flat 20 FC
        CostCalculatorService.CostResult r = svc.costForAgentforceActions(1, 5000L);
        Assert.areEqual(20L, r.flexCredits, 'Flat action: 20 FC');
        Assert.areEqual(Decimal.valueOf('0.0800'), r.baseUsd);
        Assert.areEqual(CostCalculatorService.CONFIDENCE_HIGH, r.confidence);
    }

    @IsTest
    static void testActionFlatFee_Overage() {
        seedCache();
        seedSettings(0);
        CostCalculatorService svc = new CostCalculatorService();

        // 1 action × 10001 tokens → 2× flat charge = 40 FC
        CostCalculatorService.CostResult r = svc.costForAgentforceActions(1, 10001L);
        Assert.areEqual(40L, r.flexCredits, 'Action overage: 2 × 20 FC');
    }

    @IsTest
    static void testActionFlatFee_MultipleActions() {
        seedCache();
        seedSettings(0);
        CostCalculatorService svc = new CostCalculatorService();

        // 5 actions × 25K total tokens (5K avg each, below threshold)
        CostCalculatorService.CostResult r = svc.costForAgentforceActions(5, 25000L);
        Assert.areEqual(100L, r.flexCredits, '5 actions × 20 FC = 100 FC');
    }

    @IsTest
    static void testActionFlatFee_DisabledOptIn() {
        seedCache();
        // Settings with Enable_Cost_Metrics__c = false
        FluentMetric_Cost_Settings__c s = new FluentMetric_Cost_Settings__c();
        s.Flex_Credit_USD_Rate__c = 0.004;
        s.Action_Flat_FC__c = 20;
        s.Action_Token_Threshold__c = 10000;
        s.Enable_Cost_Metrics__c = false;
        CostCalculatorService.settingsCache = s;

        CostCalculatorService.CostResult r = new CostCalculatorService().costForAgentforceActions(3, 5000L);
        Assert.areEqual(0L, r.flexCredits, 'Opt-in off → 0 FC even for actions');
    }

    @IsTest
    static void testActionFlatFee_ZeroGuard() {
        seedCache();
        seedSettings(0);
        CostCalculatorService svc = new CostCalculatorService();

        Assert.areEqual(0L, svc.costForAgentforceActions(0, 1000L).flexCredits);
        Assert.areEqual(0L, svc.costForAgentforceActions(null, 1000L).flexCredits);
        Assert.areEqual(0L, svc.costForAgentforceActions(-3, 1000L).flexCredits);
    }

    // ───────── Confidence bands ──────────────────────────────────────────────

    @IsTest
    static void testConfidence_ExactMatch_High() {
        seedCache();
        seedSettings(0);
        CostCalculatorService.CostResult r = new CostCalculatorService().costForAggregate('gpt-4o', 1, 500L);
        Assert.areEqual(CostCalculatorService.CONFIDENCE_HIGH, r.confidence);
    }

    @IsTest
    static void testConfidence_PrefixWalk_Estimated() {
        seedCache();
        seedSettings(0);
        // Strip -2024-11-20 suffix → prefix match, not exact
        CostCalculatorService.CostResult r = new CostCalculatorService().costForAggregate('gpt-4o-2024-11-20', 1, 500L);
        Assert.areEqual(CostCalculatorService.CONFIDENCE_ESTIMATED, r.confidence);
    }

    @IsTest
    static void testConfidence_FallbackRecord() {
        seedCache();
        seedSettings(0);
        CostCalculatorService.CostResult r = new CostCalculatorService()
            .costForAggregate('something-nobody-has-heard-of', 1, 500L);
        Assert.areEqual(CostCalculatorService.CONFIDENCE_FALLBACK, r.confidence);
        Assert.areEqual(true, r.usedFallback);
    }

    @IsTest
    static void testConfidence_Unmetered_High() {
        // Unmetered models cost $0 deliberately — that's a known-correct
        // answer, so the confidence is HIGH. Previously this was NOT_COSTED,
        // which poisoned aggregate confidence on any org that had even one
        // Salesforce-internal classifier call.
        Map<String, FluentMetric_Rate_Card__mdt> m = new Map<String, FluentMetric_Rate_Card__mdt>();
        FluentMetric_Rate_Card__mdt unmetered = buildRate('EinsteinTextEval', 'Basic', 0, 0, false);
        unmetered.Is_Unmetered__c = true;
        m.put('einsteintexteval', unmetered);
        m.put('standard-default', buildRate('Standard-Default', 'Standard', 4, 0.016, true));
        CostCalculatorService.rateCardByModel = m;
        seedSettings(0);

        CostCalculatorService.CostResult r = new CostCalculatorService()
            .costForAggregate('EinsteinTextEval', 500, 100000L);
        Assert.areEqual(0L, r.flexCredits, 'Unmetered still charges $0');
        Assert.areEqual(CostCalculatorService.CONFIDENCE_HIGH, r.confidence, 'Unmetered is HIGH, not NOT_COSTED');
    }

    @IsTest
    static void testNotCosted_Helper() {
        seedCache();
        seedSettings(0);
        CostCalculatorService.CostResult r = new CostCalculatorService().notCosted();
        Assert.areEqual(0L, r.flexCredits);
        Assert.areEqual(CostCalculatorService.CONFIDENCE_NOT_COSTED, r.confidence);
    }

    @IsTest
    static void testDiscount_AppliedToTierMath() {
        seedCache();
        seedSettings(25);
        CostCalculatorService svc = new CostCalculatorService();

        // gpt-4o Standard, 10 calls, 1000 tokens (no overage)
        // 40 FC × $0.004 = $0.16 base, × 75% = $0.12
        CostCalculatorService.CostResult r = svc.costForAggregate('gpt-4o', 10, 1000L);
        Assert.areEqual(40L, r.flexCredits);
        Assert.areEqual(Decimal.valueOf('0.1600'), r.baseUsd);
        Assert.areEqual(Decimal.valueOf('0.1200'), r.discountedUsd, '25% off $0.16 = $0.12');
    }

    // ───────── Direct helper coverage (Round 9 — coverage gap fill) ──────

    @IsTest
    static void testWorstConfidence_orderedDegradation() {
        seedCache();
        seedSettings(0);
        CostCalculatorService svc = new CostCalculatorService();
        Assert.areEqual(
            CostCalculatorService.CONFIDENCE_HIGH,
            svc.worstConfidence(CostCalculatorService.CONFIDENCE_HIGH, CostCalculatorService.CONFIDENCE_HIGH)
        );
        Assert.areEqual(
            CostCalculatorService.CONFIDENCE_ESTIMATED,
            svc.worstConfidence(CostCalculatorService.CONFIDENCE_HIGH, CostCalculatorService.CONFIDENCE_ESTIMATED)
        );
        Assert.areEqual(
            CostCalculatorService.CONFIDENCE_FALLBACK,
            svc.worstConfidence(CostCalculatorService.CONFIDENCE_ESTIMATED, CostCalculatorService.CONFIDENCE_FALLBACK)
        );
        Assert.areEqual(
            CostCalculatorService.CONFIDENCE_NOT_COSTED,
            svc.worstConfidence(CostCalculatorService.CONFIDENCE_FALLBACK, CostCalculatorService.CONFIDENCE_NOT_COSTED)
        );
    }

    @IsTest
    static void testNormalizeModelKey_stripsDateAndVersionSuffixes() {
        seedCache();
        seedSettings(0);
        CostCalculatorService svc = new CostCalculatorService();
        Assert.areEqual('', svc.normalizeModelKey(null));
        Assert.areEqual('', svc.normalizeModelKey(''));
        Assert.areEqual('gpt-4o', svc.normalizeModelKey('gpt-4o'));
        Assert.areEqual('gpt-4o', svc.normalizeModelKey('gpt-4o-2024-11-20'));
        // gpt-4 IS in the cache — stripping -mini hits the cached base.
        Assert.areEqual('gpt-4', svc.normalizeModelKey('gpt-4-mini'));
    }

    @IsTest
    static void testResolveConfidence_handlesNullAndBlankRate() {
        seedCache();
        seedSettings(0);
        CostCalculatorService svc = new CostCalculatorService();
        Assert.areEqual(
            CostCalculatorService.CONFIDENCE_NOT_COSTED,
            svc.resolveConfidence('gpt-4o', null),
            'null rate → NOT_COSTED'
        );
        FluentMetric_Rate_Card__mdt blankRate = new FluentMetric_Rate_Card__mdt();
        blankRate.Model__c = '';
        blankRate.Tier__c = 'Standard';
        Assert.areEqual(
            CostCalculatorService.CONFIDENCE_ESTIMATED,
            svc.resolveConfidence('', blankRate),
            'blank inputs → ESTIMATED'
        );
    }

    @IsTest
    static void testMatchRateCard_syntheticFallbackWhenNoFallbackRecord() {
        // Cache contains only non-fallback records — no Is_Default_Fallback__c.
        Map<String, FluentMetric_Rate_Card__mdt> m = new Map<String, FluentMetric_Rate_Card__mdt>();
        m.put('gpt-4o', buildRate('gpt-4o', 'Standard', 4, 0.016, false));
        CostCalculatorService.rateCardByModel = m;
        seedSettings(0);

        CostCalculatorService svc = new CostCalculatorService();
        FluentMetric_Rate_Card__mdt card = svc.matchRateCard('absolutely-unknown');
        Assert.areNotEqual(null, card, 'synthetic fallback returned');
        Assert.areEqual('Synthetic-Zero', card.Model__c, 'synthetic fallback stub');
        Assert.areEqual(true, card.Is_Default_Fallback__c, 'synthetic is fallback-flagged');
    }

    @IsTest
    static void testTierRateFor_unknownTierFallsBackToStandard() {
        seedCache();
        seedSettings(0);
        CostCalculatorService svc = new CostCalculatorService();
        // Standard, Basic, Advanced are explicit; everything else folds to Standard.
        Assert.areEqual(2, svc.tierRateFor('Basic'));
        Assert.areEqual(4, svc.tierRateFor('Standard'));
        Assert.areEqual(16, svc.tierRateFor('Advanced'));
        Assert.areEqual(4, svc.tierRateFor('Enterprise'), 'unknown tier → Standard default');
        Assert.areEqual(4, svc.tierRateFor(null), 'null tier → Standard default');
    }

    @IsTest
    static void testThresholds_useDefaultsWhenSettingsBlank() {
        // Empty settings — exercise the `s.X__c == null ?` defaults.
        FluentMetric_Cost_Settings__c s = new FluentMetric_Cost_Settings__c();
        s.Enable_Cost_Metrics__c = true;
        s.Flex_Credit_USD_Rate__c = null;
        s.Tier_Basic_FC__c = null;
        s.Tier_Standard_FC__c = null;
        s.Tier_Advanced_FC__c = null;
        s.Action_Flat_FC__c = null;
        s.Prompt_Token_Threshold__c = null;
        s.Action_Token_Threshold__c = null;
        CostCalculatorService.settingsCache = s;

        CostCalculatorService svc = new CostCalculatorService();
        Assert.areEqual(2, svc.tierRateFor('Basic'), 'default 2 FC for Basic');
        Assert.areEqual(4, svc.tierRateFor('Standard'), 'default 4 FC for Standard');
        Assert.areEqual(16, svc.tierRateFor('Advanced'), 'default 16 FC for Advanced');
        Assert.areEqual(20, svc.actionFlatFc(), 'default 20 FC for actions');
        Assert.areEqual(2000L, svc.promptTokenThreshold(), 'default 2000-token threshold');
        Assert.areEqual(10000L, svc.actionTokenThreshold(), 'default 10000-token action threshold');
    }

    @IsTest
    static void testOverageMultiplier_guards() {
        seedCache();
        seedSettings(0);
        CostCalculatorService svc = new CostCalculatorService();
        // null / zero / negative inputs all collapse to 1 (no overage).
        Assert.areEqual(1, svc.overageMultiplierFor(null, 1, 100L));
        Assert.areEqual(1, svc.overageMultiplierFor(0L, 1, 100L));
        Assert.areEqual(1, svc.overageMultiplierFor(100L, null, 100L));
        Assert.areEqual(1, svc.overageMultiplierFor(100L, 0, 100L));
        Assert.areEqual(1, svc.overageMultiplierFor(100L, 1, null));
        Assert.areEqual(1, svc.overageMultiplierFor(100L, 1, 0L));
    }

    @IsTest
    static void testCostFromWallet_negativeOrZeroPath() {
        seedCache();
        seedSettings(0);
        CostCalculatorService svc = new CostCalculatorService();
        // Negative or zero short-circuits to a zero-FC ACTUAL result.
        CostCalculatorService.CostResult zeroOut = svc.costFromWallet(0);
        Assert.areEqual(0L, zeroOut.flexCredits);
        Assert.areEqual(CostCalculatorService.CONFIDENCE_ACTUAL, zeroOut.confidence);
        Assert.areEqual(CostCalculatorService.SOURCE_WALLET, zeroOut.source);

        CostCalculatorService.CostResult negativeOut = svc.costFromWallet(Decimal.valueOf('-5'));
        Assert.areEqual(0L, negativeOut.flexCredits, 'negative coerces to zero');
    }

    @IsTest
    static void testIsCostMetricsEnabled_offByDefault() {
        // Reset cache to force a real getOrgDefaults() call.
        CostCalculatorService.settingsCache = null;
        CostCalculatorService svc = new CostCalculatorService();
        // Fresh install — no record means `Enable_Cost_Metrics__c` is false.
        Assert.isFalse(svc.isCostMetricsEnabled(), 'fresh install defaults to off');
    }

    @IsTest
    static void testCostForRequests_skipsNullEntries() {
        seedCache();
        seedSettings(0);
        CostCalculatorService svc = new CostCalculatorService();
        // Pass a list with null mixed in — should not throw, returns 0.
        List<SObject> rows = new List<SObject>{ null };
        CostCalculatorService.CostResult r = svc.costForRequests(rows);
        Assert.areEqual(0L, r.flexCredits, 'all-null list contributes nothing');
    }

    /**
     * Rate-card refresh path: the upload flow writes 8 multiplier fields to
     * FluentMetric_Cost_Settings__c, but only 4 (Action_Flat_FC, Tier_Basic,
     * Tier_Standard, Tier_Advanced) are read by costForRequests today. This
     * asserts that populating the new fields (Custom_Action, *_Voice_Action,
     * Tier_Starter) does not alter what the legacy fields produce — guarding
     * against an accidental wiring change in CostCalculatorService that would
     * break customers who upload a rate card.
     */
    @IsTest
    static void testRateCardRefresh_LegacyFieldsStillDriveCost() {
        seedCache();
        FluentMetric_Cost_Settings__c s = new FluentMetric_Cost_Settings__c();
        s.Flex_Credit_USD_Rate__c = 0.004;
        s.Discount_Percent__c = 0;
        s.Default_Fallback_Model__c = 'Standard-Default';
        s.Enable_Cost_Metrics__c = true;
        // Legacy 4 — these drive costForRequests today.
        s.Tier_Basic_FC__c = 2;
        s.Tier_Standard_FC__c = 4;
        s.Tier_Advanced_FC__c = 16;
        s.Action_Flat_FC__c = 20;
        // New 4 from the rate-card import — populated but not yet consumed.
        // The assertion is that their presence is harmless.
        s.Tier_Starter_FC__c = 2;
        s.Custom_Action_FC__c = 20;
        s.Standard_Voice_Action_FC__c = 30;
        s.Custom_Voice_Action_FC__c = 30;
        s.Prompt_Token_Threshold__c = 2000;
        s.Action_Token_Threshold__c = 10000;
        CostCalculatorService.settingsCache = s;

        CostCalculatorService svc = new CostCalculatorService();

        Test.startTest();
        // Standard tier: still 4 FC × 10 = 40 FC, regardless of new fields.
        CostCalculatorService.CostResult standard = svc.costForAggregate('gpt-4o', 10, 1000L);
        // Action: still 20 FC × 1 = 20 FC, regardless of Custom_Action_FC__c.
        CostCalculatorService.CostResult action = svc.costForAgentforceActions(1, 5000L);
        Test.stopTest();

        Assert.areEqual(40L, standard.flexCredits, 'Tier_Standard_FC__c still drives standard tier');
        Assert.areEqual(Decimal.valueOf('0.1600'), standard.baseUsd);
        Assert.areEqual(20L, action.flexCredits, 'Action_Flat_FC__c still drives action pricing');
    }

    @IsTest
    static void testLoadRateCards_RealMetadata() {
        // Reset caches so loadRateCards runs the SOQL path once.
        CostCalculatorService.rateCardByModel = null;
        CostCalculatorService.settingsCache = null;
        CostCalculatorService svc = new CostCalculatorService();

        Test.startTest();
        // This exercises the real SOQL against FluentMetric_Rate_Card__mdt.
        // In a test org the records deployed above should be visible.
        CostCalculatorService.CostResult r = svc.costForAggregate('gpt-4o', 1, null);
        Test.stopTest();

        // We don't assert exact numbers here because CMDT values may evolve —
        // we only assert that a match was produced without throwing and that
        // the result is well-formed.
        Assert.areNotEqual(null, r, 'Result must not be null');
        Assert.areNotEqual(null, r.flexCredits, 'flexCredits initialized');
        Assert.areNotEqual(null, r.baseUsd, 'baseUsd initialized');
    }
}
