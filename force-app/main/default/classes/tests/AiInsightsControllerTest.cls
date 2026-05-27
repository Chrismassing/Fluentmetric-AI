/**
 * Tests for AiInsightsController.
 *
 * Because AiInsightsController is just a thin facade, these tests focus on:
 *   - Input validation (null dates, inverted ranges, blank identifiers)
 *   - Exception wrapping into AuraHandledException
 *   - Successful delegation using a service injected via `serviceOverride`
 *
 * A lightweight stub service subclass provides deterministic return values.
 */
@IsTest
private class AiInsightsControllerTest {
    /** Test stub: overrides every service method with canned data. */
    @TestVisible
    private class StubService extends AiInsightsService {
        public Integer overviewCalls = 0;
        public Integer usageByUserCalls = 0;
        public Integer usageByPromptCalls = 0;
        public Integer promptOutputsCalls = 0;
        public Integer tokenCalls = 0;
        public Integer safetyCalls = 0;
        public Integer explorerCalls = 0;
        public Integer prereqCalls = 0;
        public Integer entityDetailsCalls = 0;
        public Integer facetsCalls = 0;
        public Integer searchUsersCalls = 0;
        public String lastEntityType;
        public String lastEntityKey;
        public ExplorerRequest lastExplorerRequest;

        public StubService() {
            super(new AiInsightsDAOMock(), new UserResolverService());
        }

        public override UsageOverviewDTO getOverview(DateRangeFilter f) {
            overviewCalls++;
            UsageOverviewDTO dto = new UsageOverviewDTO();
            dto.totalRequests = 42;
            return dto;
        }

        public Integer overviewTrendsCalls = 0;
        public override OverviewTrendsDTO getOverviewTrends(DateRangeFilter f) {
            overviewTrendsCalls++;
            OverviewTrendsDTO dto = new OverviewTrendsDTO();
            dto.previousTotalRequests = 30;
            dto.daysInWindow = 3;
            dto.dailyRequests = new List<Integer>{ 4, 5, 6 };
            return dto;
        }

        public override List<UserUsageDTO> getUsageByUser(DateRangeFilter f) {
            usageByUserCalls++;
            UserUsageDTO a = new UserUsageDTO();
            a.userId = 'u1';
            a.userName = 'Alice';
            a.requestCount = 5;
            UserUsageDTO b = new UserUsageDTO();
            b.userId = 'u2';
            b.userName = 'Bob';
            b.requestCount = 3;
            return new List<UserUsageDTO>{ a, b };
        }

        public override List<PromptUsageDTO> getUsageByPrompt(DateRangeFilter f) {
            usageByPromptCalls++;
            return new List<PromptUsageDTO>{ new PromptUsageDTO() };
        }

        public override List<PromptOutputDTO> getPromptOutputs(String name, DateRangeFilter f, Integer l) {
            promptOutputsCalls++;
            return new List<PromptOutputDTO>{ new PromptOutputDTO() };
        }

        public override List<TokenConsumptionDTO> getTokenConsumption(DateRangeFilter f, String groupBy) {
            tokenCalls++;
            return new List<TokenConsumptionDTO>{ new TokenConsumptionDTO() };
        }

        public override ContentSafetyDTO getSafetyOverview(DateRangeFilter f) {
            safetyCalls++;
            return new ContentSafetyDTO();
        }

        public override List<ExplorerResultDTO> runExplorer(ExplorerRequest r) {
            explorerCalls++;
            lastExplorerRequest = r;
            return new List<ExplorerResultDTO>{ new ExplorerResultDTO('k', 'label', 1) };
        }

        public override FilterFacetsDTO getFilterFacets(DateRangeFilter f, Integer topUserLimit) {
            facetsCalls++;
            return new FilterFacetsDTO();
        }

        public override List<FilterFacetsDTO.FacetOption> searchUsersInRange(
            String term,
            DateRangeFilter f,
            Integer maxRows
        ) {
            searchUsersCalls++;
            return new List<FilterFacetsDTO.FacetOption>();
        }

        public override EntityDetailsDTO getEntityDetails(
            String entityType,
            String entityKey,
            DateRangeFilter f,
            Integer recentLimit,
            FilterCriteria criteria
        ) {
            entityDetailsCalls++;
            lastEntityType = entityType;
            lastEntityKey = entityKey;
            EntityDetailsDTO dto = new EntityDetailsDTO();
            dto.entityType = entityType;
            dto.entityKey = entityKey;
            dto.entityLabel = 'resolved-' + entityKey;
            dto.requestCount = 7;
            return dto;
        }

        public override Map<String, Boolean> checkPrerequisites() {
            prereqCalls++;
            return new Map<String, Boolean>{
                'dataCloudEnabled' => true,
                'hasDmoAccess' => true,
                'hasData' => true,
                'cacheAvailable' => true
            };
        }

        // ── Phase 3 — adoption analytics overrides ──────────────────
        public Integer entitlementSnapshotCalls = 0;
        public Integer adoptionCohortsCalls = 0;
        public Integer orgAdoptionDeltasCalls = 0;
        public Integer powerUserSegmentsCalls = 0;
        public Integer featureAdoptionCalls = 0;

        public override EntitlementSnapshotDTO getEntitlementSnapshot(DateRangeFilter f) {
            entitlementSnapshotCalls++;
            EntitlementSnapshotDTO dto = new EntitlementSnapshotDTO();
            dto.entitledCount = 11;
            dto.activeCount = 5;
            dto.adoptionRate = 0.4545;
            dto.entitledFallback = false;
            return dto;
        }

        public override AdoptionCohortsDTO getAdoptionCohorts(DateRangeFilter f) {
            adoptionCohortsCalls++;
            AdoptionCohortsDTO dto = new AdoptionCohortsDTO();
            dto.totalUsersObserved = 7;
            return dto;
        }

        public override OrgAdoptionDeltasDTO getOrgAdoptionDeltas(DateRangeFilter f) {
            orgAdoptionDeltasCalls++;
            OrgAdoptionDeltasDTO dto = new OrgAdoptionDeltasDTO();
            dto.latestRequestsWowPct = 12.50;
            return dto;
        }

        public override PowerUserSegmentsDTO getPowerUserSegments(DateRangeFilter f) {
            powerUserSegmentsCalls++;
            PowerUserSegmentsDTO dto = new PowerUserSegmentsDTO();
            dto.totalActiveUsers = 13;
            dto.top10PercentVolumeShare = 0.78;
            return dto;
        }

        public override List<FeatureAdoptionDTO> getFeatureAdoption(DateRangeFilter f) {
            featureAdoptionCalls++;
            FeatureAdoptionDTO row = new FeatureAdoptionDTO();
            row.featureName = 'Stub Feature';
            row.uniqueUserCount = 4;
            return new List<FeatureAdoptionDTO>{ row };
        }
    }

    private static StubService installStub() {
        StubService stub = new StubService();
        AiInsightsController.serviceOverride = stub;
        return stub;
    }

    // ───────── Happy-path delegation ─────────────────────────────

    @IsTest
    static void testGetOverview_delegates() {
        StubService stub = installStub();
        UsageOverviewDTO out = AiInsightsController.getOverview(DateTime.now().addDays(-7), DateTime.now());
        Assert.areEqual(1, stub.overviewCalls);
        Assert.areEqual(42, out.totalRequests);
    }

    @IsTest
    static void testGetOverviewTrends_delegates() {
        StubService stub = installStub();
        OverviewTrendsDTO out = AiInsightsController.getOverviewTrends(DateTime.now().addDays(-2), DateTime.now());
        Assert.areEqual(1, stub.overviewTrendsCalls);
        Assert.areEqual(30, out.previousTotalRequests);
        Assert.areEqual(3, out.dailyRequests.size());
    }

    @IsTest
    static void testGetOverviewTrends_invalidRangeWraps() {
        installStub();
        Boolean threw = false;
        try {
            // end before start -> controller should wrap in AuraHandledException
            AiInsightsController.getOverviewTrends(DateTime.now(), DateTime.now().addDays(-1));
        } catch (AuraHandledException e) {
            threw = true;
        }
        Assert.isTrue(threw, 'invalid range should raise AuraHandledException');
    }

    @IsTest
    static void testGetUsageByUser_delegates() {
        StubService stub = installStub();
        List<UserUsageDTO> rows = AiInsightsController.getUsageByUser(DateTime.now().addDays(-7), DateTime.now());
        Assert.areEqual(1, stub.usageByUserCalls);
        Assert.areEqual(2, rows.size());
    }

    @IsTest
    static void testGetUserDetail_finds() {
        installStub();
        UserUsageDTO dto = AiInsightsController.getUserDetail('u1', DateTime.now().addDays(-7), DateTime.now());
        Assert.isNotNull(dto);
        Assert.areEqual('u1', dto.userId);
    }

    @IsTest
    static void testGetUserDetail_missing() {
        installStub();
        UserUsageDTO dto = AiInsightsController.getUserDetail('nobody', DateTime.now().addDays(-7), DateTime.now());
        Assert.isNull(dto);
    }

    @IsTest
    static void testGetUserDetail_requiresId() {
        installStub();
        Boolean threw = false;
        try {
            AiInsightsController.getUserDetail(null, DateTime.now().addDays(-1), DateTime.now());
        } catch (AuraHandledException e) {
            threw = true;
        }
        Assert.isTrue(threw);
    }

    @IsTest
    static void testGetUsageByPrompt_delegates() {
        StubService stub = installStub();
        AiInsightsController.getUsageByPrompt(DateTime.now().addDays(-1), DateTime.now());
        Assert.areEqual(1, stub.usageByPromptCalls);
    }

    @IsTest
    static void testGetPromptOutputs_delegates() {
        StubService stub = installStub();
        List<PromptOutputDTO> out = AiInsightsController.getPromptOutputs(
            'Atlas__Foo',
            DateTime.now().addDays(-1),
            DateTime.now(),
            10
        );
        Assert.areEqual(1, stub.promptOutputsCalls);
        Assert.areEqual(1, out.size());
    }

    @IsTest
    static void testGetPromptOutputs_requiresName() {
        installStub();
        Boolean threw = false;
        try {
            AiInsightsController.getPromptOutputs(null, DateTime.now().addDays(-1), DateTime.now(), 10);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Assert.isTrue(threw);
    }

    @IsTest
    static void testGetTokenConsumption_delegates() {
        StubService stub = installStub();
        AiInsightsController.getTokenConsumption(DateTime.now().addDays(-1), DateTime.now(), 'user');
        Assert.areEqual(1, stub.tokenCalls);
    }

    @IsTest
    static void testGetTokenConsumption_requiresGroupBy() {
        installStub();
        Boolean threw = false;
        try {
            AiInsightsController.getTokenConsumption(DateTime.now().addDays(-1), DateTime.now(), null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Assert.isTrue(threw);
    }

    @IsTest
    static void testGetSafetyOverview_delegates() {
        StubService stub = installStub();
        AiInsightsController.getSafetyOverview(DateTime.now().addDays(-1), DateTime.now());
        Assert.areEqual(1, stub.safetyCalls);
    }

    @IsTest
    static void testRunExplorerQuery_delegates() {
        StubService stub = installStub();
        DateTime start = DateTime.now().addDays(-1);
        DateTime ending = DateTime.now();
        List<ExplorerResultDTO> rows = AiInsightsController.runExplorerQuery(
            start,
            ending,
            'User',
            'RequestCount',
            null,
            null,
            25
        );
        Assert.areEqual(1, stub.explorerCalls);
        Assert.areEqual(1, rows.size());
    }

    @IsTest
    static void testRunExplorerQuery_withFilters() {
        StubService stub = installStub();
        DateTime start = DateTime.now().addDays(-1);
        DateTime ending = DateTime.now();
        String filtersJson = '{"feedbackValue":"thumbs_down","model":"gpt-4"}';
        List<ExplorerResultDTO> rows = AiInsightsController.runExplorerQuery(
            start,
            ending,
            'Model',
            'TotalTokens',
            filtersJson,
            null,
            10
        );
        Assert.areEqual(1, stub.explorerCalls);
        Assert.isNotNull(rows);
    }

    @IsTest
    static void testRunExplorerQuery_withCriteriaJson() {
        // New rail path: multi-select criteria arrives as JSON. Verify the
        // controller decodes it and hands a populated FilterCriteria to the
        // service.
        StubService stub = installStub();
        DateTime start = DateTime.now().addDays(-1);
        DateTime ending = DateTime.now();
        String criteriaJson = '{"models":["gpt-4o","gpt-5"],"features":["Agentforce"],"userIds":["005000000000001"]}';
        List<ExplorerResultDTO> rows = AiInsightsController.runExplorerQuery(
            start,
            ending,
            'User',
            'RequestCount',
            null,
            criteriaJson,
            25
        );
        Assert.areEqual(1, stub.explorerCalls);
        Assert.isNotNull(stub.lastExplorerRequest, 'request was captured');
        FilterCriteria c = stub.lastExplorerRequest.criteria;
        Assert.isNotNull(c, 'criteria decoded onto ExplorerRequest');
        Assert.areEqual(2, c.models.size());
        Assert.areEqual('gpt-4o', c.models[0]);
        Assert.areEqual(1, c.features.size());
        Assert.areEqual('Agentforce', c.features[0]);
        Assert.areEqual(1, c.userIds.size());
        Assert.areEqual('005000000000001', c.userIds[0]);
        Assert.isNotNull(rows);
    }

    @IsTest
    static void testRunExplorerQuery_toleratesBadFilterJson() {
        StubService stub = installStub();
        DateTime start = DateTime.now().addDays(-1);
        DateTime ending = DateTime.now();
        List<ExplorerResultDTO> rows = AiInsightsController.runExplorerQuery(
            start,
            ending,
            'User',
            'RequestCount',
            'not-valid-json',
            'also-not-json',
            null
        );
        // Bad JSON on either payload falls through to no filters rather than throwing
        Assert.areEqual(1, stub.explorerCalls);
        Assert.isNotNull(rows);
    }

    @IsTest
    static void testGetFilterFacets_delegates() {
        StubService stub = installStub();
        FilterFacetsDTO out = AiInsightsController.getFilterFacets(DateTime.now().addDays(-7), DateTime.now(), 50);
        Assert.areEqual(1, stub.facetsCalls);
        Assert.isNotNull(out);
        Assert.isNotNull(out.models);
    }

    @IsTest
    static void testGetFilterFacets_invalidRangeWraps() {
        installStub();
        Boolean threw = false;
        try {
            AiInsightsController.getFilterFacets(DateTime.now(), DateTime.now().addDays(-1), 50);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Assert.isTrue(threw, 'invalid range must surface as AuraHandledException');
    }

    @IsTest
    static void testSearchUsersInRange_delegates() {
        StubService stub = installStub();
        List<FilterFacetsDTO.FacetOption> out = AiInsightsController.searchUsersInRange(
            'alice',
            DateTime.now().addDays(-7),
            DateTime.now(),
            25
        );
        Assert.areEqual(1, stub.searchUsersCalls);
        Assert.isNotNull(out);
    }

    @IsTest
    static void testCheckPrerequisites_delegates() {
        StubService stub = installStub();
        Map<String, Boolean> flags = AiInsightsController.checkPrerequisites();
        Assert.areEqual(1, stub.prereqCalls);
        Assert.areEqual(true, flags.get('hasData'));
    }

    // ───────── Entity details ────────────────────────────────────

    @IsTest
    static void testGetEntityDetails_user_delegates() {
        StubService stub = installStub();
        EntityDetailsDTO out = AiInsightsController.getEntityDetails(
            'User',
            '005Hn00000JWnX4IAL',
            DateTime.now().addDays(-7),
            DateTime.now(),
            20,
            null
        );
        Assert.areEqual(1, stub.entityDetailsCalls);
        Assert.areEqual('User', stub.lastEntityType);
        Assert.areEqual('005Hn00000JWnX4IAL', stub.lastEntityKey);
        Assert.areEqual('User', out.entityType);
        Assert.areEqual(7, out.requestCount);
    }

    @IsTest
    static void testGetEntityDetails_promptTemplate_delegates() {
        StubService stub = installStub();
        EntityDetailsDTO out = AiInsightsController.getEntityDetails(
            'PromptTemplate',
            '"topic_selector_prompt"',
            DateTime.now().addDays(-7),
            DateTime.now(),
            10,
            null
        );
        Assert.areEqual(1, stub.entityDetailsCalls);
        Assert.areEqual('"topic_selector_prompt"', stub.lastEntityKey);
        Assert.isNotNull(out.entityLabel);
    }

    @IsTest
    static void testGetEntityDetails_model_delegates() {
        StubService stub = installStub();
        AiInsightsController.getEntityDetails(
            'Model',
            'gpt-4.1-2025-04-14',
            DateTime.now().addDays(-7),
            DateTime.now(),
            5,
            null
        );
        Assert.areEqual(1, stub.entityDetailsCalls);
        Assert.areEqual('Model', stub.lastEntityType);
    }

    @IsTest
    static void testGetEntityDetails_feature_delegates() {
        StubService stub = installStub();
        AiInsightsController.getEntityDetails(
            'Feature',
            'plannerservice',
            DateTime.now().addDays(-7),
            DateTime.now(),
            null,
            null
        );
        Assert.areEqual(1, stub.entityDetailsCalls);
        Assert.areEqual('Feature', stub.lastEntityType);
    }

    @IsTest
    static void testGetEntityDetails_requiresEntityType() {
        installStub();
        Boolean threw = false;
        try {
            AiInsightsController.getEntityDetails(null, 'x', DateTime.now().addDays(-1), DateTime.now(), 20, null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Assert.isTrue(threw, 'missing entityType throws AuraHandledException');
    }

    @IsTest
    static void testGetEntityDetails_requiresEntityKey() {
        installStub();
        Boolean threw = false;
        try {
            AiInsightsController.getEntityDetails('User', '', DateTime.now().addDays(-1), DateTime.now(), 20, null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Assert.isTrue(threw, 'blank entityKey throws AuraHandledException');
    }

    // ───────── Input validation ──────────────────────────────────

    @IsTest
    static void testGetOverview_invalidRange() {
        installStub();
        Boolean threw = false;
        try {
            AiInsightsController.getOverview(DateTime.now(), DateTime.now().addDays(-1));
        } catch (AuraHandledException e) {
            threw = true;
        }
        Assert.isTrue(threw, 'inverted range throws AuraHandledException');
    }

    @IsTest
    static void testGetOverview_nullDates() {
        installStub();
        Boolean threw = false;
        try {
            AiInsightsController.getOverview(null, null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Assert.isTrue(threw, 'null dates throw AuraHandledException');
    }

    // ───────── Live-service fallback (zero-arg path) ─────────────

    // ───────── getEntityBreakdown — pivot drill ──────────────────

    @IsTest
    static void testGetEntityBreakdown_userToPromptTemplate() {
        StubService stub = installStub();
        DateTime start = DateTime.now().addDays(-7);
        DateTime ending = DateTime.now();
        List<ExplorerResultDTO> rows = AiInsightsController.getEntityBreakdown(
            'User',
            '005000000000001',
            'PromptTemplate',
            start,
            ending,
            null,
            null,
            null
        );
        Assert.areEqual(1, stub.explorerCalls, 'service runExplorer was invoked');
        Assert.isNotNull(rows);
        ExplorerRequest req = stub.lastExplorerRequest;
        Assert.areEqual('PromptTemplate', req.groupBy, 'breakdownBy becomes groupBy');
        Assert.areEqual('RequestCount', req.metric, 'metric defaults to RequestCount');
        Assert.areEqual(10, req.resultLimit, 'resultLimit defaults to 10');
        Assert.isNotNull(req.criteria, 'criteria is built');
        Assert.areEqual(1, req.criteria.userIds.size(), 'source User injected as single-element list');
        Assert.areEqual('005000000000001', req.criteria.userIds[0]);
        Assert.isNull(req.criteria.promptTemplateDevNames, 'no prompt filter on a User source');
    }

    @IsTest
    static void testGetEntityBreakdown_promptToUser() {
        StubService stub = installStub();
        AiInsightsController.getEntityBreakdown(
            'PromptTemplate',
            '"Email_Draft"',
            'User',
            DateTime.now().addDays(-7),
            DateTime.now(),
            'TotalTokens',
            5,
            null
        );
        ExplorerRequest req = stub.lastExplorerRequest;
        Assert.areEqual('User', req.groupBy);
        Assert.areEqual('TotalTokens', req.metric, 'metric override is honoured');
        Assert.areEqual(5, req.resultLimit, 'resultLimit override is honoured');
        Assert.areEqual(1, req.criteria.promptTemplateDevNames.size());
        Assert.areEqual('"Email_Draft"', req.criteria.promptTemplateDevNames[0]);
        Assert.isNull(req.criteria.userIds);
    }

    @IsTest
    static void testGetEntityBreakdown_modelToPromptTemplate() {
        StubService stub = installStub();
        AiInsightsController.getEntityBreakdown(
            'Model',
            'gpt-4.1-2025-04-14',
            'PromptTemplate',
            DateTime.now().addDays(-1),
            DateTime.now(),
            null,
            null,
            null
        );
        ExplorerRequest req = stub.lastExplorerRequest;
        Assert.areEqual('PromptTemplate', req.groupBy);
        Assert.areEqual(1, req.criteria.models.size());
        Assert.areEqual('gpt-4.1-2025-04-14', req.criteria.models[0]);
    }

    @IsTest
    static void testGetEntityBreakdown_featureToUser() {
        StubService stub = installStub();
        AiInsightsController.getEntityBreakdown(
            'Feature',
            'EinsteinSalesEmail',
            'User',
            DateTime.now().addDays(-1),
            DateTime.now(),
            null,
            null,
            null
        );
        ExplorerRequest req = stub.lastExplorerRequest;
        Assert.areEqual('User', req.groupBy);
        Assert.areEqual(1, req.criteria.features.size());
        Assert.areEqual('EinsteinSalesEmail', req.criteria.features[0]);
    }

    @IsTest
    static void testGetEntityBreakdown_dayBreakdown() {
        StubService stub = installStub();
        // Day breakdown is the time-bucket pivot — entity stays the same,
        // groupBy becomes Day. The drill panel uses this for the Trend tab.
        AiInsightsController.getEntityBreakdown(
            'User',
            '005000000000001',
            'Day',
            DateTime.now().addDays(-30),
            DateTime.now(),
            'RequestCount',
            null,
            null
        );
        Assert.areEqual('Day', stub.lastExplorerRequest.groupBy);
    }

    @IsTest
    static void testGetEntityBreakdown_validation() {
        installStub();
        DateTime start = DateTime.now().addDays(-1);
        DateTime ending = DateTime.now();

        Boolean threwOnEntityType = false;
        try {
            AiInsightsController.getEntityBreakdown(null, 'k', 'User', start, ending, null, null, null);
        } catch (AuraHandledException e) {
            threwOnEntityType = true;
        }
        Assert.isTrue(threwOnEntityType, 'blank entityType wraps to AuraHandledException');

        Boolean threwOnEntityKey = false;
        try {
            AiInsightsController.getEntityBreakdown('User', '   ', 'PromptTemplate', start, ending, null, null, null);
        } catch (AuraHandledException e) {
            threwOnEntityKey = true;
        }
        Assert.isTrue(threwOnEntityKey, 'blank entityKey wraps to AuraHandledException');

        Boolean threwOnBreakdown = false;
        try {
            AiInsightsController.getEntityBreakdown('User', 'k', '', start, ending, null, null, null);
        } catch (AuraHandledException e) {
            threwOnBreakdown = true;
        }
        Assert.isTrue(threwOnBreakdown, 'blank breakdownBy wraps to AuraHandledException');

        Boolean threwOnUnsupportedType = false;
        try {
            AiInsightsController.getEntityBreakdown('Squiggle', 'k', 'User', start, ending, null, null, null);
        } catch (AuraHandledException e) {
            threwOnUnsupportedType = true;
        }
        Assert.isTrue(threwOnUnsupportedType, 'unsupported entityType wraps to AuraHandledException');

        Boolean threwOnDates = false;
        try {
            AiInsightsController.getEntityBreakdown('User', 'k', 'PromptTemplate', null, ending, null, null, null);
        } catch (AuraHandledException e) {
            threwOnDates = true;
        }
        Assert.isTrue(threwOnDates, 'null start date wraps to AuraHandledException');
    }

    @IsTest
    static void testGetEntityBreakdown_mergesInboundCriteria() {
        // Phase 5: when the rail is filtering by Model + Feature and the user
        // drills into a User entity, the panel forwards the rail criteria as
        // criteriaJson. The controller must merge those into the FilterCriteria
        // it builds — entity replaces its own dimension, every other dimension
        // survives intact.
        StubService stub = installStub();
        DateTime start = DateTime.now().addDays(-7);
        DateTime ending = DateTime.now();
        String criteriaJson = '{"models":["gpt-4o","gpt-5"],"features":["Agentforce"],"userIds":["005000000000999"]}';

        AiInsightsController.getEntityBreakdown(
            'User',
            '005000000000001',
            'PromptTemplate',
            start,
            ending,
            null,
            null,
            criteriaJson
        );

        ExplorerRequest req = stub.lastExplorerRequest;
        Assert.isNotNull(req, 'service was invoked');
        FilterCriteria c = req.criteria;
        Assert.isNotNull(c, 'criteria built');

        // Source entity wins over any inbound user list — drill scopes to one user.
        Assert.areEqual(1, c.userIds.size(), 'inbound userIds replaced by source User');
        Assert.areEqual('005000000000001', c.userIds[0]);

        // Other dimensions from the rail are preserved.
        Assert.areEqual(2, c.models.size(), 'inbound models survive');
        Assert.areEqual('gpt-4o', c.models[0]);
        Assert.areEqual(1, c.features.size(), 'inbound features survive');
        Assert.areEqual('Agentforce', c.features[0]);

        // Date range is sourced from the (start, ending) args, not criteriaJson.
        Assert.areEqual(start, c.startDate);
        Assert.areEqual(ending, c.endDate);
    }

    @IsTest
    static void testGetEntityBreakdown_blankCriteriaJsonIsNoop() {
        // Empty / blank criteriaJson behaves the same as the legacy call —
        // criteria gets the entity, nothing else. Guards against regressions
        // that would crash on the new param being unset.
        StubService stub = installStub();
        AiInsightsController.getEntityBreakdown(
            'Model',
            'gpt-5',
            'User',
            DateTime.now().addDays(-1),
            DateTime.now(),
            null,
            null,
            ''
        );
        FilterCriteria c = stub.lastExplorerRequest.criteria;
        Assert.areEqual(1, c.models.size());
        Assert.areEqual('gpt-5', c.models[0]);
        Assert.isNull(c.userIds, 'no users injected when criteriaJson is blank');
    }

    @IsTest
    static void testGetEntityBreakdown_toleratesBadCriteriaJson() {
        // Bad JSON falls through to "no inbound criteria" rather than throwing —
        // matches the parseCriteria contract used by runExplorerQuery.
        StubService stub = installStub();
        AiInsightsController.getEntityBreakdown(
            'User',
            '005000000000001',
            'Model',
            DateTime.now().addDays(-1),
            DateTime.now(),
            null,
            null,
            'not-valid-json'
        );
        FilterCriteria c = stub.lastExplorerRequest.criteria;
        Assert.areEqual(1, c.userIds.size(), 'entity still applied');
        Assert.areEqual('005000000000001', c.userIds[0]);
    }

    @IsTest
    static void testLiveServiceFallback() {
        // Exercise the zero-arg constructor path by leaving serviceOverride null.
        // The call may throw because DMOs aren't queryable in test context —
        // but either outcome covers the live-fallback branch safely.
        AiInsightsController.serviceOverride = null;
        try {
            AiInsightsController.checkPrerequisites();
        } catch (AuraHandledException e) {
            // Expected in most test orgs — ignore
        }
    }

    // ─────────────── Phase 3 — Adoption analytics endpoints ─────

    @IsTest
    static void testGetEntitlementSnapshot_delegates() {
        StubService stub = installStub();
        EntitlementSnapshotDTO dto = AiInsightsController.getEntitlementSnapshot(
            DateTime.now().addDays(-7),
            DateTime.now()
        );
        Assert.areEqual(1, stub.entitlementSnapshotCalls);
        Assert.areEqual(11, dto.entitledCount);
        Assert.areEqual(false, dto.entitledFallback);
    }

    @IsTest
    static void testGetEntitlementSnapshot_invalidRangeWraps() {
        installStub();
        try {
            AiInsightsController.getEntitlementSnapshot(DateTime.now(), DateTime.now().addDays(-1));
            Assert.fail('expected AuraHandledException');
        } catch (AuraHandledException e) {
            // expected
        }
    }

    @IsTest
    static void testGetAdoptionCohorts_delegates() {
        StubService stub = installStub();
        AdoptionCohortsDTO dto = AiInsightsController.getAdoptionCohorts(DateTime.now().addDays(-30), DateTime.now());
        Assert.areEqual(1, stub.adoptionCohortsCalls);
        Assert.areEqual(7, dto.totalUsersObserved);
    }

    @IsTest
    static void testGetOrgAdoptionDeltas_delegates() {
        StubService stub = installStub();
        OrgAdoptionDeltasDTO dto = AiInsightsController.getOrgAdoptionDeltas(
            DateTime.now().addDays(-60),
            DateTime.now()
        );
        Assert.areEqual(1, stub.orgAdoptionDeltasCalls);
        Assert.areEqual(12.50, dto.latestRequestsWowPct);
    }

    @IsTest
    static void testGetPowerUserSegments_delegates() {
        StubService stub = installStub();
        PowerUserSegmentsDTO dto = AiInsightsController.getPowerUserSegments(
            DateTime.now().addDays(-7),
            DateTime.now()
        );
        Assert.areEqual(1, stub.powerUserSegmentsCalls);
        Assert.areEqual(13, dto.totalActiveUsers);
        Assert.areEqual(0.78, dto.top10PercentVolumeShare);
    }

    @IsTest
    static void testGetFeatureAdoption_delegates() {
        StubService stub = installStub();
        List<FeatureAdoptionDTO> rows = AiInsightsController.getFeatureAdoption(
            DateTime.now().addDays(-7),
            DateTime.now()
        );
        Assert.areEqual(1, stub.featureAdoptionCalls);
        Assert.areEqual(1, rows.size());
        Assert.areEqual('Stub Feature', rows[0].featureName);
    }
}
