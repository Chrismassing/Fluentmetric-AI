/**
 * Tests for RateCardImportService.
 *
 * Strategy:
 *   - Inject a fake ILlmAdapter via adapterOverride so we never touch
 *     ConnectApi.EinsteinLLM (not available in test context).
 *   - Insert a real ContentVersion so loadContentVersion has something to
 *     fetch — its bytes don't need to be a real PDF since the adapter is
 *     mocked.
 *   - Cover: golden-path parse + apply, malformed JSON, missing
 *     multipliers, invalid revert, happy revert, listRecent.
 */
@IsTest
private class RateCardImportServiceTest {
    private static final String GOOD_JSON =
        '{"effective_date":"2025-10-24",' +
        '"multipliers":{' +
        '"standard_action":20,"custom_action":20,' +
        '"standard_voice_action":30,"custom_voice_action":30,' +
        '"starter_prompt":2,"basic_prompt":2,' +
        '"standard_prompt":4,"advanced_prompt":16}}';

    /** Test adapter — returns whatever JSON the test seeded. */
    private class StubAdapter implements RateCardImportService.ILlmAdapter {
        public String payload;
        public Boolean throwOnCall = false;

        public StubAdapter(String payload) {
            this.payload = payload;
        }

        public String extractRateCardJson(Blob pdfBlob, String fileName) {
            if (throwOnCall) {
                throw new CalloutException('Simulated Einstein outage');
            }
            return payload;
        }
    }

    private static Id insertContentVersion() {
        ContentVersion cv = new ContentVersion();
        cv.Title = 'Flex_Credits_Rate_Card.pdf';
        cv.PathOnClient = 'rate_card.pdf';
        cv.VersionData = Blob.valueOf('synthetic-rate-card-bytes');
        cv.IsMajorVersion = true;
        insert cv;
        return [SELECT Id FROM ContentVersion WHERE Id = :cv.Id LIMIT 1].Id;
    }

    @IsTest
    static void parseAndApplyHappyPath() {
        RateCardImportService.adapterOverride = new StubAdapter(GOOD_JSON);
        Id cvId = insertContentVersion();

        Test.startTest();
        RateCardImportService svc = new RateCardImportService();
        RateCardImportService.ParseResult parsed = svc.parseUpload(cvId);
        Id auditId = svc.applyParsedUpload(cvId, JSON.serialize(parsed.parsed), 'Q4 refresh');
        Test.stopTest();

        Assert.isNotNull(parsed, 'Parse should return a result');
        Assert.areEqual(8, parsed.parsed.multipliers.size(), 'All 8 multipliers should land');
        Assert.areEqual(8, parsed.diff.size(), 'Diff covers every parsed key');
        Assert.isNotNull(auditId, 'Apply returns the new audit Id');

        RateCardUpload__c row = [
            SELECT Status__c, Notes__c, ChangeSummary__c, EffectiveDate__c
            FROM RateCardUpload__c
            WHERE Id = :auditId
        ];
        Assert.areEqual('Applied', row.Status__c);
        Assert.areEqual('Q4 refresh', row.Notes__c);
        Assert.isNotNull(row.ChangeSummary__c);

        FluentMetric_Cost_Settings__c s = FluentMetric_Cost_Settings__c.getOrgDefaults();
        Assert.areEqual(20, s.Action_Flat_FC__c);
        Assert.areEqual(20, s.Custom_Action_FC__c);
        Assert.areEqual(30, s.Standard_Voice_Action_FC__c);
        Assert.areEqual(30, s.Custom_Voice_Action_FC__c);
        Assert.areEqual(2, s.Tier_Starter_FC__c);
        Assert.areEqual(2, s.Tier_Basic_FC__c);
        Assert.areEqual(4, s.Tier_Standard_FC__c);
        Assert.areEqual(16, s.Tier_Advanced_FC__c);
    }

    @IsTest
    static void revertRestoresPriorValues() {
        // Seed a known starting state so we can verify revert moves back.
        FluentMetric_Cost_Settings__c seed = FluentMetric_Cost_Settings__c.getOrgDefaults();
        if (seed == null) {
            seed = new FluentMetric_Cost_Settings__c(SetupOwnerId = UserInfo.getOrganizationId());
        }
        seed.Tier_Basic_FC__c = 99;
        seed.Tier_Advanced_FC__c = 99;
        upsert seed;

        RateCardImportService.adapterOverride = new StubAdapter(GOOD_JSON);
        Id cvId = insertContentVersion();
        RateCardImportService svc = new RateCardImportService();
        RateCardImportService.ParseResult parsed = svc.parseUpload(cvId);
        Id auditId = svc.applyParsedUpload(cvId, JSON.serialize(parsed.parsed), null);

        // Sanity: after apply, basic FC is now 2 (from the JSON).
        FluentMetric_Cost_Settings__c afterApply = FluentMetric_Cost_Settings__c.getOrgDefaults();
        Assert.areEqual(2, afterApply.Tier_Basic_FC__c);

        Test.startTest();
        Id reverted = svc.revert(auditId);
        Test.stopTest();

        Assert.areEqual(auditId, reverted);
        FluentMetric_Cost_Settings__c afterRevert = FluentMetric_Cost_Settings__c.getOrgDefaults();
        Assert.areEqual(99, afterRevert.Tier_Basic_FC__c, 'Revert should restore prior basic FC');
        Assert.areEqual(99, afterRevert.Tier_Advanced_FC__c, 'Revert should restore prior advanced FC');

        RateCardUpload__c row = [SELECT Status__c FROM RateCardUpload__c WHERE Id = :auditId];
        Assert.areEqual('Reverted', row.Status__c);
    }

    @IsTest
    static void parseRejectsInvalidJson() {
        RateCardImportService.adapterOverride = new StubAdapter('{"garbage": true');
        Id cvId = insertContentVersion();

        Test.startTest();
        Boolean threw = false;
        try {
            new RateCardImportService().parseUpload(cvId);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        Assert.isTrue(threw, 'Invalid JSON must surface as AuraHandledException');
    }

    @IsTest
    static void parseRejectsMissingMultipliers() {
        RateCardImportService.adapterOverride = new StubAdapter('{"effective_date":"2025-10-24"}');
        Id cvId = insertContentVersion();

        Test.startTest();
        Boolean threw = false;
        try {
            new RateCardImportService().parseUpload(cvId);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        Assert.isTrue(threw, 'Empty multipliers must surface as AuraHandledException');
    }

    @IsTest
    static void applyRejectsBlankPayload() {
        Test.startTest();
        Boolean threw = false;
        try {
            new RateCardImportService().applyParsedUpload(null, null, null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        Assert.isTrue(threw);
    }

    @IsTest
    static void revertRejectsUnknownId() {
        Test.startTest();
        Boolean threw = false;
        try {
            new RateCardImportService().revert(null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        Assert.isTrue(threw);
    }

    @IsTest
    static void listRecentReturnsOrderedRows() {
        RateCardImportService.adapterOverride = new StubAdapter(GOOD_JSON);
        Id cvId = insertContentVersion();
        RateCardImportService svc = new RateCardImportService();
        RateCardImportService.ParseResult parsed = svc.parseUpload(cvId);
        svc.applyParsedUpload(cvId, JSON.serialize(parsed.parsed), 'first');

        Test.startTest();
        List<RateCardUpload__c> rows = svc.listRecent(5);
        Test.stopTest();

        Assert.areEqual(1, rows.size(), 'One uploaded so far');
        Assert.areEqual('Applied', rows[0].Status__c);
    }

    @IsTest
    static void einsteinAdapterErrorSurfacesFriendlyMessage() {
        StubAdapter stub = new StubAdapter(null);
        stub.throwOnCall = true;
        RateCardImportService.adapterOverride = stub;
        Id cvId = insertContentVersion();

        Test.startTest();
        Boolean threw = false;
        try {
            new RateCardImportService().parseUpload(cvId);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        Assert.isTrue(threw, 'Adapter exception must surface as AuraHandledException');
    }
}
