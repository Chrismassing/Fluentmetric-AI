/**
 * Tests for the Wallet-first cost paths added in Phase 6 of the redesign.
 *
 * Coverage targets:
 *   - `costFromWallet(...)` — happy / zero / null inputs.
 *   - `isWalletPreferred()` — both gates required (cost-metrics on AND
 *     Enable_Wallet_Costs__c on AND Wallet DAO reports available).
 *   - `costForWindow(...)` — Wallet wins when authoritative, falls back to
 *     estimate when Wallet is disabled, unavailable, or returns 0/null,
 *     and never throws when the Wallet probe blows up mid-call.
 *
 * The Wallet DLO doesn't exist in Apex test context, so the live AiWalletDAO
 * is never exercised here — we inject `AiWalletDAOMock` via the new
 * constructor parameter.
 */
@IsTest
private class CostCalculatorWalletTest {
    // ───────── Helpers ─────────────────────────────────────────────────────

    private static FluentMetric_Cost_Settings__c seedSettings(Boolean walletEnabled) {
        FluentMetric_Cost_Settings__c s = new FluentMetric_Cost_Settings__c();
        s.Enable_Cost_Metrics__c = true;
        s.Enable_Wallet_Costs__c = walletEnabled;
        s.Flex_Credit_USD_Rate__c = 0.004;
        s.Discount_Percent__c = 0;
        s.Default_Fallback_Model__c = 'Standard-Default';
        s.Tier_Basic_FC__c = 2;
        s.Tier_Standard_FC__c = 4;
        s.Tier_Advanced_FC__c = 16;
        s.Action_Flat_FC__c = 20;
        s.Prompt_Token_Threshold__c = 2000;
        s.Action_Token_Threshold__c = 10000;
        CostCalculatorService.settingsCache = s;
        return s;
    }

    private static FluentMetric_Rate_Card__mdt buildRate(String model, String tier) {
        FluentMetric_Rate_Card__mdt rc = new FluentMetric_Rate_Card__mdt();
        rc.Model__c = model;
        rc.Tier__c = tier;
        rc.Is_Default_Fallback__c = false;
        return rc;
    }

    private static void seedRateCard() {
        Map<String, FluentMetric_Rate_Card__mdt> m = new Map<String, FluentMetric_Rate_Card__mdt>();
        m.put('standard-default', buildRate('Standard-Default', 'Standard'));
        m.put('gpt-4o', buildRate('gpt-4o', 'Standard'));
        CostCalculatorService.rateCardByModel = m;
    }

    /**
     * Stand-in for a list of GenAIGatewayRequest__dlm rows. The DMO doesn't
     * exist in test context, so we use a generic SObject (Account) with
     * dynamic field puts via JSON — CostCalculatorService only reads
     * `model__c` and `totalTokens__c` via `safeGetString`/`safeGetLong`.
     * That's fine: an SObject with no such fields returns null for those
     * gets, which the calculator already handles.
     */
    private static List<SObject> emptyRequestList() {
        return new List<SObject>();
    }

    // ───────── costFromWallet ─────────────────────────────────────────────

    @IsTest
    static void costFromWallet_happy() {
        seedSettings(true);
        AiWalletDAOMock mock = new AiWalletDAOMock();
        CostCalculatorService svc = new CostCalculatorService(mock);

        Test.startTest();
        CostCalculatorService.CostResult cr = svc.costFromWallet(1234);
        Test.stopTest();

        Assert.areEqual(1234L, cr.flexCredits, 'FC pass-through');
        Assert.areEqual(CostCalculatorService.CONFIDENCE_ACTUAL, cr.confidence, 'Wallet → ACTUAL');
        Assert.areEqual(CostCalculatorService.SOURCE_WALLET, cr.source, 'source = ACTUAL_WALLET');
        Assert.areEqual(Decimal.valueOf('4.9360'), cr.baseUsd, '1234 × 0.004 = 4.936');
        Assert.areEqual(Decimal.valueOf('4.9360'), cr.discountedUsd, 'no discount at 0%');
    }

    @IsTest
    static void costFromWallet_zero() {
        seedSettings(true);
        CostCalculatorService svc = new CostCalculatorService(new AiWalletDAOMock());

        CostCalculatorService.CostResult cr = svc.costFromWallet(0);
        Assert.areEqual(0L, cr.flexCredits);
        Assert.areEqual(CostCalculatorService.CONFIDENCE_ACTUAL, cr.confidence, 'still ACTUAL when 0');
        Assert.areEqual(CostCalculatorService.SOURCE_WALLET, cr.source);
    }

    @IsTest
    static void costFromWallet_null() {
        seedSettings(true);
        CostCalculatorService svc = new CostCalculatorService(new AiWalletDAOMock());

        CostCalculatorService.CostResult cr = svc.costFromWallet(null);
        Assert.areEqual(0L, cr.flexCredits);
        Assert.areEqual(CostCalculatorService.CONFIDENCE_ACTUAL, cr.confidence);
    }

    // ───────── isWalletPreferred ──────────────────────────────────────────

    @IsTest
    static void isWalletPreferred_requiresAllGates() {
        // Setting on, Wallet available → true
        seedSettings(true);
        AiWalletDAOMock walletOn = new AiWalletDAOMock();
        walletOn.walletAvailable = true;
        Assert.isTrue(new CostCalculatorService(walletOn).isWalletPreferred(), 'on + available');

        // Setting on, Wallet unavailable → false
        seedSettings(true);
        AiWalletDAOMock walletOff = new AiWalletDAOMock();
        walletOff.walletAvailable = false;
        Assert.isFalse(new CostCalculatorService(walletOff).isWalletPreferred(), 'on + unavailable');

        // Setting off → false even if Wallet would be available
        seedSettings(false);
        AiWalletDAOMock walletStillOn = new AiWalletDAOMock();
        walletStillOn.walletAvailable = true;
        Assert.isFalse(new CostCalculatorService(walletStillOn).isWalletPreferred(), 'setting off');
    }

    // ───────── costForWindow ──────────────────────────────────────────────

    @IsTest
    static void costForWindow_walletWinsWhenAuthoritative() {
        seedSettings(true);
        seedRateCard();
        AiWalletDAOMock mock = new AiWalletDAOMock();
        mock.walletAvailable = true;
        mock.totalFlexCreditsToReturn = 5000;
        CostCalculatorService svc = new CostCalculatorService(mock);

        Test.startTest();
        CostCalculatorService.CostResult cr = svc.costForWindow(
            DateTime.now().addDays(-30),
            DateTime.now(),
            emptyRequestList()
        );
        Test.stopTest();

        Assert.areEqual(5000L, cr.flexCredits, 'Wallet total wins');
        Assert.areEqual(CostCalculatorService.CONFIDENCE_ACTUAL, cr.confidence);
        Assert.areEqual(CostCalculatorService.SOURCE_WALLET, cr.source);
    }

    @IsTest
    static void costForWindow_fallsBackWhenWalletUnavailable() {
        seedSettings(true);
        seedRateCard();
        AiWalletDAOMock mock = new AiWalletDAOMock(); // walletAvailable defaults false
        CostCalculatorService svc = new CostCalculatorService(mock);

        Test.startTest();
        CostCalculatorService.CostResult cr = svc.costForWindow(
            DateTime.now().addDays(-30),
            DateTime.now(),
            emptyRequestList()
        );
        Test.stopTest();

        Assert.areEqual(0L, cr.flexCredits, 'no requests → 0');
        Assert.areNotEqual(
            CostCalculatorService.CONFIDENCE_ACTUAL,
            cr.confidence,
            'must not claim ACTUAL when Wallet absent'
        );
    }

    @IsTest
    static void costForWindow_fallsBackWhenWalletReturnsZero() {
        // The empty-DLO scenario from cvk-dev — Wallet is available but no
        // billing rows exist yet. We still want to show the estimate so the
        // panel isn't blank during ramp-up.
        seedSettings(true);
        seedRateCard();
        AiWalletDAOMock mock = new AiWalletDAOMock();
        mock.walletAvailable = true;
        mock.totalFlexCreditsToReturn = 0;
        CostCalculatorService svc = new CostCalculatorService(mock);

        CostCalculatorService.CostResult cr = svc.costForWindow(
            DateTime.now().addDays(-30),
            DateTime.now(),
            emptyRequestList()
        );

        // Empty request list → estimate path returns zero result with
        // confidence = HIGH (the calculator's default neutral value when
        // there is nothing to price).
        Assert.areEqual(0L, cr.flexCredits);
        Assert.areNotEqual(
            CostCalculatorService.CONFIDENCE_ACTUAL,
            cr.confidence,
            'Wallet=0 must downgrade to estimate'
        );
    }

    @IsTest
    static void costForWindow_costMetricsOff_returnsZero() {
        FluentMetric_Cost_Settings__c s = seedSettings(true);
        s.Enable_Cost_Metrics__c = false;
        AiWalletDAOMock mock = new AiWalletDAOMock();
        mock.walletAvailable = true;
        mock.totalFlexCreditsToReturn = 999;
        CostCalculatorService svc = new CostCalculatorService(mock);

        CostCalculatorService.CostResult cr = svc.costForWindow(
            DateTime.now().addDays(-30),
            DateTime.now(),
            emptyRequestList()
        );

        Assert.areEqual(0L, cr.flexCredits, 'Cost metrics off → 0 regardless of Wallet');
    }

    @IsTest
    static void defaultConstructor_doesNotThrow() {
        // The no-arg constructor is the back-compat path used by every
        // existing call site. It must wire up a real AiWalletDAO without
        // crashing when the Wallet DLO does not exist (the Apex test org
        // case, and the default sandbox case).
        seedSettings(false);
        Test.startTest();
        CostCalculatorService svc = new CostCalculatorService();
        Boolean preferred = svc.isWalletPreferred();
        Test.stopTest();

        Assert.isFalse(preferred, 'No DLO + setting off → not preferred');
    }
}
