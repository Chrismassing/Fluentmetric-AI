@IsTest
private class FmTableauNextTest {
    private class StubService extends AiInsightsService {
        public Boolean shouldThrow = false;
        public UsageOverviewDTO overview;
        public List<UserUsageDTO> users = new List<UserUsageDTO>();
        public List<PromptUsageDTO> prompts = new List<PromptUsageDTO>();
        public EntitlementSnapshotDTO entitlement;
        public OrgAdoptionDeltasDTO deltas;
        public AdoptionCohortsDTO cohorts;
        public PowerUserSegmentsDTO power;
        public List<FeatureAdoptionDTO> features = new List<FeatureAdoptionDTO>();
        public ContentSafetyDTO safety;
        public List<TokenConsumptionDTO> tokenRows = new List<TokenConsumptionDTO>();
        public EntityDetailsDTO entityDetails;
        public List<PromptOutputDTO> promptOutputs = new List<PromptOutputDTO>();

        public override UsageOverviewDTO getOverview(DateRangeFilter f) {
            if (shouldThrow)
                throw new IllegalArgumentException('boom');
            return overview;
        }
        public override List<UserUsageDTO> getUsageByUser(DateRangeFilter f) {
            if (shouldThrow)
                throw new IllegalArgumentException('boom');
            return users;
        }
        public override List<PromptUsageDTO> getUsageByPrompt(DateRangeFilter f) {
            if (shouldThrow)
                throw new IllegalArgumentException('boom');
            return prompts;
        }
        public override EntitlementSnapshotDTO getEntitlementSnapshot(DateRangeFilter f) {
            if (shouldThrow)
                throw new IllegalArgumentException('boom');
            return entitlement;
        }
        public override OrgAdoptionDeltasDTO getOrgAdoptionDeltas(DateRangeFilter f) {
            if (shouldThrow)
                throw new IllegalArgumentException('boom');
            return deltas;
        }
        public override AdoptionCohortsDTO getAdoptionCohorts(DateRangeFilter f) {
            if (shouldThrow)
                throw new IllegalArgumentException('boom');
            return cohorts;
        }
        public override PowerUserSegmentsDTO getPowerUserSegments(DateRangeFilter f) {
            if (shouldThrow)
                throw new IllegalArgumentException('boom');
            return power;
        }
        public override List<FeatureAdoptionDTO> getFeatureAdoption(DateRangeFilter f) {
            if (shouldThrow)
                throw new IllegalArgumentException('boom');
            return features;
        }
        public override ContentSafetyDTO getSafetyOverview(DateRangeFilter f) {
            if (shouldThrow)
                throw new IllegalArgumentException('boom');
            return safety;
        }
        public override List<TokenConsumptionDTO> getTokenConsumption(DateRangeFilter f, String groupBy) {
            if (shouldThrow)
                throw new IllegalArgumentException('boom');
            return tokenRows;
        }
        public override EntityDetailsDTO getEntityDetails(
            String entityType,
            String entityKey,
            DateRangeFilter f,
            Integer recentLimit
        ) {
            if (shouldThrow)
                throw new IllegalArgumentException('boom');
            return entityDetails;
        }
        public override List<PromptOutputDTO> getPromptOutputs(
            String promptDevName,
            DateRangeFilter f,
            Integer limitCount
        ) {
            if (shouldThrow)
                throw new IllegalArgumentException('boom');
            return promptOutputs;
        }
    }

    private static UsageOverviewDTO sampleOverview() {
        UsageOverviewDTO d = new UsageOverviewDTO();
        d.totalRequests = 100;
        d.uniqueUsers = 12;
        d.acceptanceRate = 0.78;
        d.totalInputTokens = 500000;
        d.totalOutputTokens = 250000;
        d.topUserName = 'Alice';
        d.topPromptLabel = 'Summarize Case';
        d.topModelName = 'gpt-4o';
        d.dateRangeLabel = 'Last 30 days';
        return d;
    }

    @IsTest
    static void controllerKpiSummaryDelegatesToService() {
        StubService stub = new StubService();
        stub.overview = sampleOverview();
        FmTableauNextController.serviceOverride = stub;

        Test.startTest();
        UsageOverviewDTO dto = FmTableauNextController.getKpiSummary(null, null);
        Test.stopTest();

        System.assertEquals(100, dto.totalRequests);
        System.assertEquals('Alice', dto.topUserName);
    }

    @IsTest
    static void controllerKpiWrapsServiceErrors() {
        StubService stub = new StubService();
        stub.shouldThrow = true;
        FmTableauNextController.serviceOverride = stub;

        Test.startTest();
        try {
            FmTableauNextController.getKpiSummary(null, null);
            System.assert(false, 'Should have thrown.');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        Test.stopTest();
    }

    @IsTest
    static void controllerLauncherTargetReadsLabels() {
        Test.startTest();
        Map<String, String> target = FmTableauNextController.getLauncherTarget();
        Test.stopTest();

        System.assertNotEquals(null, target.get('workspaceLabel'));
        System.assertNotEquals(null, target.get('workspacePath'));
        System.assert(
            target.get('workspacePath').startsWith('/lightning'),
            'Default launcher path should be a Lightning navigation path.'
        );
    }

    @IsTest
    static void getUsageOverviewActionFlattensDto() {
        StubService stub = new StubService();
        stub.overview = sampleOverview();
        GetUsageOverviewAction.serviceOverride = stub;
        GetUsageOverviewAction.Request r = new GetUsageOverviewAction.Request();

        Test.startTest();
        List<GetUsageOverviewAction.Response> out = GetUsageOverviewAction.run(
            new List<GetUsageOverviewAction.Request>{ r }
        );
        Test.stopTest();

        System.assertEquals(100, out[0].totalRequests);
        System.assertEquals('Alice', out[0].topUserName);
        System.assertEquals('gpt-4o', out[0].topModelName);
        System.assertEquals('78%', out[0].acceptanceRateLabel);
    }

    @IsTest
    static void getUsageOverviewActionEmitsErrorLabelOnFailure() {
        StubService stub = new StubService();
        stub.shouldThrow = true;
        GetUsageOverviewAction.serviceOverride = stub;
        GetUsageOverviewAction.Request r = new GetUsageOverviewAction.Request();

        Test.startTest();
        List<GetUsageOverviewAction.Response> out = GetUsageOverviewAction.run(
            new List<GetUsageOverviewAction.Request>{ r }
        );
        Test.stopTest();

        System.assert(out[0].dateRangeLabel.startsWith('Error'));
    }

    @IsTest
    static void getUsageByUserActionRespectsTopN() {
        StubService stub = new StubService();
        for (Integer i = 0; i < 25; i++) {
            UserUsageDTO u = new UserUsageDTO();
            u.userName = 'User ' + i;
            u.requestCount = 100 - i;
            stub.users.add(u);
        }
        GetUsageByUserAction.serviceOverride = stub;
        GetUsageByUserAction.Request r = new GetUsageByUserAction.Request();
        r.topN = 5;

        Test.startTest();
        List<GetUsageByUserAction.Response> out = GetUsageByUserAction.run(new List<GetUsageByUserAction.Request>{ r });
        Test.stopTest();

        System.assertEquals(5, out[0].rowCount, 'topN should trim the result list.');
    }

    @IsTest
    static void getUsageByUserActionEmitsErrorEnvelopeOnFailure() {
        StubService stub = new StubService();
        stub.shouldThrow = true;
        GetUsageByUserAction.serviceOverride = stub;

        Test.startTest();
        List<GetUsageByUserAction.Response> out = GetUsageByUserAction.run(
            new List<GetUsageByUserAction.Request>{ new GetUsageByUserAction.Request() }
        );
        Test.stopTest();

        System.assert(out[0].usersJson.contains('"error":true'));
        System.assertEquals(0, out[0].rowCount);
    }

    @IsTest
    static void getUsageByPromptActionDefaultsTopN() {
        StubService stub = new StubService();
        for (Integer i = 0; i < 3; i++) {
            PromptUsageDTO p = new PromptUsageDTO();
            p.promptLabel = 'Prompt ' + i;
            p.invocationCount = 50 - i;
            stub.prompts.add(p);
        }
        GetUsageByPromptAction.serviceOverride = stub;

        Test.startTest();
        List<GetUsageByPromptAction.Response> out = GetUsageByPromptAction.run(
            new List<GetUsageByPromptAction.Request>{ new GetUsageByPromptAction.Request() }
        );
        Test.stopTest();

        System.assertEquals(3, out[0].rowCount);
        System.assert(out[0].promptsJson.contains('Prompt 0'));
    }

    @IsTest
    static void getUsageByPromptActionEmitsErrorEnvelopeOnFailure() {
        StubService stub = new StubService();
        stub.shouldThrow = true;
        GetUsageByPromptAction.serviceOverride = stub;

        Test.startTest();
        List<GetUsageByPromptAction.Response> out = GetUsageByPromptAction.run(
            new List<GetUsageByPromptAction.Request>{ new GetUsageByPromptAction.Request() }
        );
        Test.stopTest();

        System.assert(out[0].promptsJson.contains('"error":true'));
    }

    // ─────────────────── Phase 1 — adoption/safety/drilldown actions ───────────

    @IsTest
    static void getEntitlementSnapshotActionFlattensDto() {
        StubService stub = new StubService();
        EntitlementSnapshotDTO dto = new EntitlementSnapshotDTO();
        dto.entitledCount = 80;
        dto.activeCount = 40;
        dto.adoptionRate = 0.5;
        dto.entitledFallback = false;
        dto.unmatchedActiveCount = 2;
        dto.configuredPermissionSets = new List<String>{ 'Einstein_Generative_AI_User' };
        stub.entitlement = dto;
        GetEntitlementSnapshotAction.serviceOverride = stub;

        Test.startTest();
        List<GetEntitlementSnapshotAction.Response> out = GetEntitlementSnapshotAction.run(
            new List<GetEntitlementSnapshotAction.Request>{ new GetEntitlementSnapshotAction.Request() }
        );
        Test.stopTest();

        System.assertEquals(80, out[0].entitledCount);
        System.assertEquals(40, out[0].activeCount);
        System.assertEquals('50%', out[0].adoptionRateLabel);
        System.assertEquals(false, out[0].entitledFallback);
        System.assertEquals('Einstein_Generative_AI_User', out[0].configuredPermissionSetsLabel);
    }

    @IsTest
    static void getEntitlementSnapshotActionEmitsErrorOnFailure() {
        StubService stub = new StubService();
        stub.shouldThrow = true;
        GetEntitlementSnapshotAction.serviceOverride = stub;

        Test.startTest();
        List<GetEntitlementSnapshotAction.Response> out = GetEntitlementSnapshotAction.run(
            new List<GetEntitlementSnapshotAction.Request>{ new GetEntitlementSnapshotAction.Request() }
        );
        Test.stopTest();

        System.assert(out[0].adoptionRateLabel.startsWith('Error'));
    }

    @IsTest
    static void getAdoptionDeltasActionLabelsLatestWow() {
        StubService stub = new StubService();
        OrgAdoptionDeltasDTO dto = new OrgAdoptionDeltasDTO();
        dto.latestRequestsWowPct = 12.5;
        dto.latestUsersWowPct = -3;
        dto.latestTokensWowPct = 0;
        OrgAdoptionDeltasDTO.WeekDelta w1 = new OrgAdoptionDeltasDTO.WeekDelta();
        w1.weekIsoLabel = '2026-W21';
        OrgAdoptionDeltasDTO.WeekDelta w2 = new OrgAdoptionDeltasDTO.WeekDelta();
        w2.weekIsoLabel = '2026-W22';
        dto.weeks = new List<OrgAdoptionDeltasDTO.WeekDelta>{ w1, w2 };
        stub.deltas = dto;
        GetAdoptionDeltasAction.serviceOverride = stub;

        Test.startTest();
        List<GetAdoptionDeltasAction.Response> out = GetAdoptionDeltasAction.run(
            new List<GetAdoptionDeltasAction.Request>{ new GetAdoptionDeltasAction.Request() }
        );
        Test.stopTest();

        System.assertEquals('+12.5%', out[0].latestRequestsWowPctLabel);
        System.assertEquals('-3.0%', out[0].latestUsersWowPctLabel);
        System.assertEquals('2026-W22', out[0].latestWeekIsoLabel);
        System.assertEquals('2026-W21', out[0].priorWeekIsoLabel);
        System.assert(out[0].weeksJson.contains('2026-W22'));
    }

    @IsTest
    static void getAdoptionDeltasActionEmitsErrorEnvelope() {
        StubService stub = new StubService();
        stub.shouldThrow = true;
        GetAdoptionDeltasAction.serviceOverride = stub;

        Test.startTest();
        List<GetAdoptionDeltasAction.Response> out = GetAdoptionDeltasAction.run(
            new List<GetAdoptionDeltasAction.Request>{ new GetAdoptionDeltasAction.Request() }
        );
        Test.stopTest();

        System.assert(out[0].weeksJson.contains('"error":true'));
    }

    @IsTest
    static void getAdoptionCohortsActionSerializesPayload() {
        StubService stub = new StubService();
        AdoptionCohortsDTO dto = new AdoptionCohortsDTO();
        dto.totalUsersObserved = 42;
        dto.truncated = false;
        dto.cohorts = new List<AdoptionCohortsDTO.CohortRow>();
        AdoptionCohortsDTO.CohortRow row = new AdoptionCohortsDTO.CohortRow();
        row.weekIsoLabel = '2026-W14';
        row.cohortSize = 7;
        row.retentionByWeek = new List<Decimal>{ 1.0, 0.8, 0.6 };
        dto.cohorts.add(row);
        stub.cohorts = dto;
        GetAdoptionCohortsAction.serviceOverride = stub;

        Test.startTest();
        List<GetAdoptionCohortsAction.Response> out = GetAdoptionCohortsAction.run(
            new List<GetAdoptionCohortsAction.Request>{ new GetAdoptionCohortsAction.Request() }
        );
        Test.stopTest();

        System.assertEquals(42, out[0].totalUsersObserved);
        System.assertEquals(false, out[0].truncated);
        System.assert(out[0].cohortsJson.contains('2026-W14'));
    }

    @IsTest
    static void getAdoptionCohortsActionEmitsErrorEnvelope() {
        StubService stub = new StubService();
        stub.shouldThrow = true;
        GetAdoptionCohortsAction.serviceOverride = stub;

        Test.startTest();
        List<GetAdoptionCohortsAction.Response> out = GetAdoptionCohortsAction.run(
            new List<GetAdoptionCohortsAction.Request>{ new GetAdoptionCohortsAction.Request() }
        );
        Test.stopTest();

        System.assert(out[0].cohortsJson.contains('"error":true'));
    }

    @IsTest
    static void getPowerUserSegmentsActionLabelsShares() {
        StubService stub = new StubService();
        PowerUserSegmentsDTO dto = new PowerUserSegmentsDTO();
        dto.top1PercentVolumeShare = 0.38;
        dto.top10PercentVolumeShare = 0.72;
        dto.top1PercentUserCount = 3;
        dto.top10PercentUserCount = 25;
        dto.topUsers = new List<PowerUserSegmentsDTO.TopUser>();
        PowerUserSegmentsDTO.TopUser t = new PowerUserSegmentsDTO.TopUser();
        t.userId = '005000000000001';
        t.userName = 'Power Pat';
        t.requestCount = 220;
        dto.topUsers.add(t);
        stub.power = dto;
        GetPowerUserSegmentsAction.serviceOverride = stub;

        Test.startTest();
        List<GetPowerUserSegmentsAction.Response> out = GetPowerUserSegmentsAction.run(
            new List<GetPowerUserSegmentsAction.Request>{ new GetPowerUserSegmentsAction.Request() }
        );
        Test.stopTest();

        System.assertEquals('38%', out[0].top1PercentVolumeShareLabel);
        System.assertEquals('72%', out[0].top10PercentVolumeShareLabel);
        System.assertEquals(3, out[0].top1PercentUserCount);
        System.assert(out[0].topUsersJson.contains('Power Pat'));
    }

    @IsTest
    static void getPowerUserSegmentsActionEmitsErrorEnvelope() {
        StubService stub = new StubService();
        stub.shouldThrow = true;
        GetPowerUserSegmentsAction.serviceOverride = stub;

        Test.startTest();
        List<GetPowerUserSegmentsAction.Response> out = GetPowerUserSegmentsAction.run(
            new List<GetPowerUserSegmentsAction.Request>{ new GetPowerUserSegmentsAction.Request() }
        );
        Test.stopTest();

        System.assert(out[0].topUsersJson.contains('"error":true'));
    }

    @IsTest
    static void getFeatureAdoptionActionReportsRowCount() {
        StubService stub = new StubService();
        for (Integer i = 0; i < 4; i++) {
            FeatureAdoptionDTO f = new FeatureAdoptionDTO();
            f.featureName = 'feature_' + i;
            f.entitledFallback = (i == 0);
            stub.features.add(f);
        }
        GetFeatureAdoptionAction.serviceOverride = stub;

        Test.startTest();
        List<GetFeatureAdoptionAction.Response> out = GetFeatureAdoptionAction.run(
            new List<GetFeatureAdoptionAction.Request>{ new GetFeatureAdoptionAction.Request() }
        );
        Test.stopTest();

        System.assertEquals(4, out[0].rowCount);
        System.assertEquals(true, out[0].entitledFallback);
        System.assert(out[0].featuresJson.contains('feature_0'));
    }

    @IsTest
    static void getFeatureAdoptionActionEmitsErrorEnvelope() {
        StubService stub = new StubService();
        stub.shouldThrow = true;
        GetFeatureAdoptionAction.serviceOverride = stub;

        Test.startTest();
        List<GetFeatureAdoptionAction.Response> out = GetFeatureAdoptionAction.run(
            new List<GetFeatureAdoptionAction.Request>{ new GetFeatureAdoptionAction.Request() }
        );
        Test.stopTest();

        System.assert(out[0].featuresJson.contains('"error":true'));
    }

    @IsTest
    static void getSafetyOverviewActionFlattensDto() {
        StubService stub = new StubService();
        ContentSafetyDTO dto = new ContentSafetyDTO();
        dto.totalGenerations = 1000;
        dto.toxicCount = 8;
        dto.toxicRate = 0.008;
        dto.avgCategoryScores = new Map<String, Decimal>{ 'hate' => 0.42, 'violence' => 0.10 };
        dto.recentFlaggedOutputs = new List<PromptOutputDTO>();
        for (Integer i = 0; i < 12; i++) {
            PromptOutputDTO po = new PromptOutputDTO();
            po.requestId = 'req-' + i;
            po.userName = 'User ' + i;
            po.inputPrompt = 'short prompt';
            po.inputPromptFull = 'full prompt that should be stripped from JSON';
            po.generatedText = 'short text';
            po.generatedTextFull = 'full text that should be stripped from JSON';
            dto.recentFlaggedOutputs.add(po);
        }
        stub.safety = dto;
        GetSafetyOverviewAction.serviceOverride = stub;

        Test.startTest();
        List<GetSafetyOverviewAction.Response> out = GetSafetyOverviewAction.run(
            new List<GetSafetyOverviewAction.Request>{ new GetSafetyOverviewAction.Request() }
        );
        Test.stopTest();

        System.assertEquals(1000, out[0].totalGenerations);
        System.assertEquals(8, out[0].toxicCount);
        System.assertEquals('hate', out[0].topCategoryName);
        System.assert(out[0].toxicRateLabel.endsWith('%'));
        System.assert(!out[0].recentFlaggedJson.contains('full prompt that should be stripped'));
        System.assert(out[0].recentFlaggedJson.contains('"requestId":"req-0"'));
    }

    @IsTest
    static void getSafetyOverviewActionEmitsErrorEnvelope() {
        StubService stub = new StubService();
        stub.shouldThrow = true;
        GetSafetyOverviewAction.serviceOverride = stub;

        Test.startTest();
        List<GetSafetyOverviewAction.Response> out = GetSafetyOverviewAction.run(
            new List<GetSafetyOverviewAction.Request>{ new GetSafetyOverviewAction.Request() }
        );
        Test.stopTest();

        System.assert(out[0].recentFlaggedJson.contains('"error":true'));
    }

    @IsTest
    static void getTokenConsumptionActionTopGroupAndRowCount() {
        StubService stub = new StubService();
        TokenConsumptionDTO a = new TokenConsumptionDTO();
        a.groupKey = 'gpt-4o';
        a.groupLabel = 'gpt-4o';
        a.totalTokens = 900000L;
        TokenConsumptionDTO b = new TokenConsumptionDTO();
        b.groupKey = 'gpt-3.5';
        b.groupLabel = 'gpt-3.5';
        b.totalTokens = 250000L;
        stub.tokenRows = new List<TokenConsumptionDTO>{ a, b };
        GetTokenConsumptionAction.serviceOverride = stub;
        GetTokenConsumptionAction.Request r = new GetTokenConsumptionAction.Request();
        r.groupBy = 'model';

        Test.startTest();
        List<GetTokenConsumptionAction.Response> out = GetTokenConsumptionAction.run(
            new List<GetTokenConsumptionAction.Request>{ r }
        );
        Test.stopTest();

        System.assertEquals(2, out[0].rowCount);
        System.assertEquals('gpt-4o', out[0].topGroupKey);
        System.assertEquals(900000L, out[0].topGroupTokens);
        System.assertEquals('model', out[0].groupBy);
        System.assert(out[0].rowsJson.contains('gpt-3.5'));
    }

    @IsTest
    static void getTokenConsumptionActionEmitsErrorEnvelope() {
        StubService stub = new StubService();
        stub.shouldThrow = true;
        GetTokenConsumptionAction.serviceOverride = stub;

        Test.startTest();
        List<GetTokenConsumptionAction.Response> out = GetTokenConsumptionAction.run(
            new List<GetTokenConsumptionAction.Request>{ new GetTokenConsumptionAction.Request() }
        );
        Test.stopTest();

        System.assert(out[0].rowsJson.contains('"error":true'));
    }

    @IsTest
    static void getEntityDetailsActionStripsFullText() {
        StubService stub = new StubService();
        EntityDetailsDTO dto = new EntityDetailsDTO();
        dto.entityLabel = 'Alice Adams';
        dto.requestCount = 240;
        dto.totalTokens = 400000L;
        dto.acceptanceRate = 0.78;
        dto.uniqueUserCount = 1;
        dto.uniquePromptCount = 12;
        dto.recentRequests = new List<PromptOutputDTO>();
        PromptOutputDTO po = new PromptOutputDTO();
        po.requestId = 'req-1';
        po.inputPrompt = 'short';
        po.inputPromptFull = 'full prompt — must be stripped';
        po.generatedText = 'short out';
        po.generatedTextFull = 'full text — must be stripped';
        dto.recentRequests.add(po);
        stub.entityDetails = dto;
        GetEntityDetailsAction.serviceOverride = stub;
        GetEntityDetailsAction.Request r = new GetEntityDetailsAction.Request();
        r.entityType = 'User';
        r.entityKey = '005000000000001';

        Test.startTest();
        List<GetEntityDetailsAction.Response> out = GetEntityDetailsAction.run(
            new List<GetEntityDetailsAction.Request>{ r }
        );
        Test.stopTest();

        System.assertEquals('Alice Adams', out[0].entityLabel);
        System.assertEquals(240, out[0].requestCount);
        System.assertEquals('78%', out[0].acceptanceRateLabel);
        System.assert(!out[0].recentRequestsJson.contains('must be stripped'));
        System.assert(out[0].recentRequestsJson.contains('"requestId":"req-1"'));
    }

    @IsTest
    static void getEntityDetailsActionRequiresEntityType() {
        StubService stub = new StubService();
        GetEntityDetailsAction.serviceOverride = stub;
        GetEntityDetailsAction.Request r = new GetEntityDetailsAction.Request();
        r.entityKey = 'abc';

        Test.startTest();
        List<GetEntityDetailsAction.Response> out = GetEntityDetailsAction.run(
            new List<GetEntityDetailsAction.Request>{ r }
        );
        Test.stopTest();

        System.assert(out[0].recentRequestsJson.contains('"error":true'));
    }

    @IsTest
    static void getPromptOutputsActionStripsFullText() {
        StubService stub = new StubService();
        for (Integer i = 0; i < 5; i++) {
            PromptOutputDTO po = new PromptOutputDTO();
            po.requestId = 'req-' + i;
            po.userName = 'User ' + i;
            po.inputPrompt = 'short';
            po.inputPromptFull = 'full prompt — must be stripped';
            po.generatedText = 'short out';
            po.generatedTextFull = 'full text — must be stripped';
            stub.promptOutputs.add(po);
        }
        GetPromptOutputsAction.serviceOverride = stub;
        GetPromptOutputsAction.Request r = new GetPromptOutputsAction.Request();
        r.promptDevName = 'Foo_Bar';

        Test.startTest();
        List<GetPromptOutputsAction.Response> out = GetPromptOutputsAction.run(
            new List<GetPromptOutputsAction.Request>{ r }
        );
        Test.stopTest();

        System.assertEquals(5, out[0].rowCount);
        System.assert(!out[0].outputsJson.contains('must be stripped'));
        System.assert(out[0].outputsJson.contains('"requestId":"req-0"'));
    }

    @IsTest
    static void getPromptOutputsActionRequiresPromptDevName() {
        StubService stub = new StubService();
        GetPromptOutputsAction.serviceOverride = stub;

        Test.startTest();
        List<GetPromptOutputsAction.Response> out = GetPromptOutputsAction.run(
            new List<GetPromptOutputsAction.Request>{ new GetPromptOutputsAction.Request() }
        );
        Test.stopTest();

        System.assert(out[0].outputsJson.contains('"error":true'));
        System.assertEquals(0, out[0].rowCount);
    }
}
