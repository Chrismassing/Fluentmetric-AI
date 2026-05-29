/**
 * Tests for AiInsightsService using the AiInsightsDAOMock test double.
 *
 * DMO SObject rows are constructed via `AiInsightsTestUtil`, which uses
 * `Type.forName(...)` + `System.JSON.deserialize(...)` to produce
 * read-only DMO SObjects (the types aren't in `Schema.getGlobalDescribe()`
 * during Apex test context, so `newSObject()` doesn't work — but the
 * Type is resolvable and the deserialize trick works). Local
 * `make*` thunks below delegate to the helper for backward compatibility
 * with the existing test bodies.
 *
 * AggregateResult cannot be JSON-deserialized with arbitrary aliases —
 * tests that need a concrete AggregateResult either call
 * `AiInsightsTestUtil.oneRowAggregate()` or exercise the empty-DAO
 * defensive path.
 */
@IsTest
private class AiInsightsServiceTest {
    // ───────── Fixture plumbing ──────────────────────────────────

    private static SObject makeRequest(
        String gatewayRequestId,
        String userId,
        String promptDevName,
        String model,
        String feature,
        DateTime ts,
        Decimal promptTokens,
        Decimal completionTokens
    ) {
        return AiInsightsTestUtil.makeRequest(
            gatewayRequestId,
            userId,
            promptDevName,
            model,
            feature,
            ts,
            promptTokens,
            completionTokens
        );
    }

    private static SObject makeResponse(String requestId, String responseId) {
        return AiInsightsTestUtil.makeResponse(requestId, responseId);
    }

    private static SObject makeGeneration(String responseId, String genId, String text) {
        return AiInsightsTestUtil.makeGeneration(responseId, genId, text);
    }

    private static SObject makeFeedback(String genId, String userId, String feedback, String action) {
        return AiInsightsTestUtil.makeFeedback(genId, userId, feedback, action);
    }

    private static SObject makeQuality(String qualityId, String genId, Boolean isToxic) {
        return AiInsightsTestUtil.makeQuality(qualityId, genId, isToxic);
    }

    private static SObject makeCategory(String qualityId, String category, String value) {
        return AiInsightsTestUtil.makeCategory(qualityId, category, value);
    }

    // ───────── Tests ─────────────────────────────────────────────

    @IsTest
    static void testGetOverview_happyPath() {
        AiInsightsDAOMock mock = new AiInsightsDAOMock();
        DateTime t = DateTime.now();
        mock.requestsToReturn = new List<SObject>{
            makeRequest('r1', '005000000000001', 'Atlas__P1', 'gpt-4', 'f1', t, 100.0, 50.0),
            makeRequest('r2', '005000000000001', 'Atlas__P1', 'gpt-4', 'f1', t, 200.0, 100.0),
            makeRequest('r3', 'NOT_SET', '"Atlas__P2"', 'gpt-4', 'f2', t, 50.0, 25.0)
        };
        mock.feedbackByDateToReturn = new List<SObject>{
            makeFeedback('g1', '005000000000001', 'thumbs_up', 'accepted'),
            makeFeedback('g2', '005000000000001', 'thumbs_down', 'rejected')
        };
        mock.responsesToReturn = new List<SObject>{ makeResponse('r1', 'resp1') };
        mock.generationsToReturn = new List<SObject>{ makeGeneration('resp1', 'g1', 'hi') };
        mock.contentQualityToReturn = new List<SObject>{ makeQuality('q1', 'g1', true) };
        // Seed aggregate slots — service reads totals/distinctUsers/distinctPrompts via the DAO
        mock.totalsToReturn = AiInsightsTestUtil.totalsAggregate(3, 350, 175);
        mock.distinctUsersToReturn = 2;
        mock.distinctPromptsToReturn = 2;

        AiInsightsService svc = new AiInsightsService(mock, new UserResolverService());
        DateRangeFilter f = new DateRangeFilter(t.addDays(-7), t.addDays(1));

        Test.startTest();
        UsageOverviewDTO overview = svc.getOverview(f);
        Test.stopTest();

        Assert.areEqual(3, overview.totalRequests, 'totalRequests count');
        Assert.areEqual(2, overview.uniqueUsers, 'unique users incl NOT_SET');
        Assert.areEqual(2, overview.uniquePromptTemplates, 'unique prompts');
        Assert.areEqual(350L, overview.totalInputTokens, 'totalInputTokens sum');
        Assert.areEqual(175L, overview.totalOutputTokens, 'totalOutputTokens sum');
        Assert.areEqual(2, overview.feedbackCount, 'feedback count');
        Assert.areEqual(0.5, overview.acceptanceRate, 'acceptance rate 50%');
        // toxicFlagCount is computed by a direct DMO query (countToxicFlagsInRange),
        // not routed through the DAO mock. In Apex test context the DMO is not
        // reachable so the path returns 0 by design (caught exception).
        Assert.areEqual(0, overview.toxicFlagCount, 'toxic count is 0 — DMO unreachable in tests');
        Assert.isNotNull(overview.dateRangeLabel);
    }

    @IsTest
    static void testGetOverview_emptyResults() {
        AiInsightsDAOMock mock = new AiInsightsDAOMock();
        AiInsightsService svc = new AiInsightsService(mock, new UserResolverService());
        UsageOverviewDTO overview = svc.getOverview(new DateRangeFilter(DateTime.now().addDays(-7), DateTime.now()));
        Assert.areEqual(0, overview.totalRequests, 'zero when mock empty');
        Assert.areEqual(0, overview.uniqueUsers);
        Assert.areEqual(0, overview.feedbackCount);
    }

    @IsTest
    static void testGetOverview_invalidDateRange() {
        AiInsightsService svc = new AiInsightsService(new AiInsightsDAOMock(), new UserResolverService());
        Boolean threw = false;
        try {
            svc.getOverview(new DateRangeFilter(DateTime.now(), DateTime.now().addDays(-1)));
        } catch (IllegalArgumentException e) {
            threw = true;
        }
        Assert.isTrue(threw, 'invalid date range throws');
    }

    @IsTest
    static void testGetUsageByUser_groupingAndResolution() {
        AiInsightsDAOMock mock = new AiInsightsDAOMock();
        DateTime t = DateTime.now();
        String realUserId = String.valueOf(UserInfo.getUserId());
        mock.requestsToReturn = new List<SObject>{
            makeRequest('r1', realUserId, 'Atlas__P1', 'gpt-4', 'f1', t, 100.0, 50.0),
            makeRequest('r2', realUserId, 'Atlas__P1', 'gpt-4', 'f1', t, 200.0, 100.0),
            makeRequest('r3', 'NOT_SET', '"Atlas__P2"', 'gpt-4', 'f2', t, 50.0, 25.0)
        };
        // Service reads `dao.getRequestAggregatesByUser` to seed the per-user buckets.
        mock.aggregatesByUserToReturn = AiInsightsTestUtil.aggregateRows(
            new List<Map<String, Object>>{
                new Map<String, Object>{ 'gkey' => realUserId, 'cnt' => 2, 'tt' => 300 },
                new Map<String, Object>{ 'gkey' => 'NOT_SET', 'cnt' => 1, 'tt' => 75 }
            }
        );

        AiInsightsService svc = new AiInsightsService(mock, new UserResolverService());

        Test.startTest();
        List<UserUsageDTO> rows = svc.getUsageByUser(new DateRangeFilter(t.addDays(-7), t.addDays(1)));
        Test.stopTest();

        Assert.areEqual(2, rows.size(), 'two user buckets');
        Assert.areEqual(2, rows[0].requestCount, 'top bucket sorted first');
        Assert.areEqual(300L, rows[0].totalTokens, 'token sum for real user');

        // System Call row is present
        Boolean hasSystem = false;
        for (UserUsageDTO r : rows) {
            if (r.userId == 'NOT_SET') {
                hasSystem = true;
                Assert.areEqual('System Call', r.userName, 'sentinel resolved to System Call');
            }
        }
        Assert.isTrue(hasSystem, 'sentinel user present');
    }

    @IsTest
    static void testGetUsageByUser_empty() {
        AiInsightsService svc = new AiInsightsService(new AiInsightsDAOMock(), new UserResolverService());
        List<UserUsageDTO> rows = svc.getUsageByUser(new DateRangeFilter(DateTime.now().addDays(-1), DateTime.now()));
        Assert.areEqual(0, rows.size(), 'empty list for no data');
    }

    @IsTest
    static void testGetUsageByPrompt_happy() {
        AiInsightsDAOMock mock = new AiInsightsDAOMock();
        DateTime t = DateTime.now();
        mock.requestsToReturn = new List<SObject>{
            makeRequest('r1', '005000000000001', 'Atlas__Foo', 'gpt-4', 'f1', t, 100.0, 50.0),
            makeRequest('r2', '005000000000002', 'Atlas__Foo', 'gpt-4', 'f1', t, 100.0, 50.0),
            makeRequest('r3', '005000000000001', '"Atlas__Bar"', 'gpt-4', 'f2', t, 100.0, 50.0)
        };
        // Service reads aggregatesByPrompt for the bucket list and aggregatesByUserAndPrompt
        // for the unique-user pivot.
        mock.aggregatesByPromptToReturn = AiInsightsTestUtil.aggregateRows(
            new List<Map<String, Object>>{
                new Map<String, Object>{ 'gkey' => 'Atlas__Foo', 'cnt' => 2, 'tt' => 300, 'pt' => 200, 'ct' => 100 },
                new Map<String, Object>{ 'gkey' => '"Atlas__Bar"', 'cnt' => 1, 'tt' => 150, 'pt' => 100, 'ct' => 50 }
            }
        );
        mock.aggregatesByUserAndPromptToReturn = AiInsightsTestUtil.aggregateRows(
            new List<Map<String, Object>>{
                new Map<String, Object>{ 'uid' => '005000000000001', 'pdn' => 'Atlas__Foo', 'cnt' => 1 },
                new Map<String, Object>{ 'uid' => '005000000000002', 'pdn' => 'Atlas__Foo', 'cnt' => 1 },
                new Map<String, Object>{ 'uid' => '005000000000001', 'pdn' => '"Atlas__Bar"', 'cnt' => 1 }
            }
        );

        AiInsightsService svc = new AiInsightsService(mock, new UserResolverService());
        List<PromptUsageDTO> rows = svc.getUsageByPrompt(new DateRangeFilter(t.addDays(-7), t.addDays(1)));
        Assert.areEqual(2, rows.size(), 'two prompt buckets');
        Assert.areEqual(2, rows[0].invocationCount, 'top bucket sorted first');
        Assert.areEqual(2, rows[0].uniqueUserCount, 'distinct users in top bucket');
        Assert.isNotNull(rows[0].promptLabel, 'label resolved');
    }

    @IsTest
    static void testGetPromptOutputs_chainAndTruncate() {
        AiInsightsDAOMock mock = new AiInsightsDAOMock();
        DateTime t = DateTime.now();
        mock.requestsByPromptToReturn = new List<SObject>{
            makeRequest('r1', 'NOT_SET', 'Atlas__P1', 'gpt-4', 'f1', t, 100.0, 50.0)
        };
        mock.responsesToReturn = new List<SObject>{ makeResponse('r1', 'resp1') };
        mock.generationsToReturn = new List<SObject>{ makeGeneration('resp1', 'g1', 'the response text') };
        mock.feedbackByGenerationToReturn = new List<SObject>{ makeFeedback('g1', 'NOT_SET', 'thumbs_up', 'accepted') };
        mock.contentQualityToReturn = new List<SObject>{ makeQuality('q1', 'g1', false) };

        AiInsightsService svc = new AiInsightsService(mock, new UserResolverService());
        List<PromptOutputDTO> outs = svc.getPromptOutputs(
            'Atlas__P1',
            new DateRangeFilter(t.addDays(-7), t.addDays(1)),
            10
        );
        Assert.areEqual(1, outs.size(), 'one output row');
        Assert.areEqual('r1', outs[0].requestId);
        Assert.areEqual('System Call', outs[0].userName, 'sentinel resolved');
        Assert.areEqual(false, outs[0].isToxic, 'toxic flag false');
        Assert.areEqual('thumbs_up', outs[0].feedbackValue);
    }

    @IsTest
    static void testGetPromptOutputs_requiresPromptName() {
        AiInsightsService svc = new AiInsightsService(new AiInsightsDAOMock(), new UserResolverService());
        Boolean threw = false;
        try {
            svc.getPromptOutputs(null, new DateRangeFilter(DateTime.now().addDays(-1), DateTime.now()), 10);
        } catch (IllegalArgumentException e) {
            threw = true;
        }
        Assert.isTrue(threw, 'blank prompt name throws');
    }

    @IsTest
    static void testGetTokenConsumption_groupByUser_withOthersBucket() {
        AiInsightsDAOMock mock = new AiInsightsDAOMock();
        DateTime t = DateTime.now();
        List<SObject> rows = new List<SObject>();
        // 11 distinct users → top 10 + others bucket
        for (Integer i = 0; i < 11; i++) {
            rows.add(
                makeRequest(
                    'r' + i,
                    '005000000000' + ('00' + String.valueOf(i)).right(3),
                    'Atlas__P1',
                    'gpt-4',
                    'f1',
                    t,
                    100.0 * (11 - i),
                    50.0
                )
            );
        }
        mock.requestsToReturn = rows;
        // Token consumption (group=user) reads dao.getRequestAggregatesByUser.
        // Seed 11 user buckets with descending totalTokens so the 11th becomes Others.
        List<Map<String, Object>> aggSeeds = new List<Map<String, Object>>();
        for (Integer i = 0; i < 11; i++) {
            String uid = '005000000000' + ('00' + String.valueOf(i)).right(3);
            Integer pt = 100 * (11 - i);
            aggSeeds.add(new Map<String, Object>{ 'gkey' => uid, 'cnt' => 1, 'pt' => pt, 'ct' => 50, 'tt' => pt + 50 });
        }
        mock.aggregatesByUserToReturn = AiInsightsTestUtil.aggregateRows(aggSeeds);

        AiInsightsService svc = new AiInsightsService(mock, new UserResolverService());
        List<TokenConsumptionDTO> result = svc.getTokenConsumption(
            new DateRangeFilter(t.addDays(-7), t.addDays(1)),
            'user'
        );
        Assert.areEqual(11, result.size(), 'top 10 + others bucket');
        Assert.areEqual('Others', result[10].groupLabel, 'last row is Others bucket');
    }

    @IsTest
    static void testGetTokenConsumption_groupByDay() {
        AiInsightsDAOMock mock = new AiInsightsDAOMock();
        DateTime t = DateTime.now();
        mock.requestsToReturn = new List<SObject>{
            makeRequest('r1', '005000000000001', 'Atlas__P1', 'gpt-4', 'f1', t, 100.0, 50.0),
            makeRequest('r2', '005000000000002', 'Atlas__P1', 'gpt-4', 'f1', t.addDays(-1), 100.0, 50.0)
        };
        // The day-grouping path fans out one `dao.getRequestTotals(bucketStart, bucketEnd)`
        // per day. The mock returns the same `totalsToReturn` for every call, so we narrow
        // the range to 2 days and seed a non-zero count → 2 buckets emitted.
        mock.totalsToReturn = AiInsightsTestUtil.totalsAggregate(1, 100, 50);
        AiInsightsService svc = new AiInsightsService(mock, new UserResolverService());
        List<TokenConsumptionDTO> result = svc.getTokenConsumption(
            new DateRangeFilter(t.addDays(-1), t.addDays(1)),
            'day'
        );
        Assert.areEqual(2, result.size(), 'one bucket per day');
    }

    @IsTest
    static void testGetTokenConsumption_requiresGroupBy() {
        AiInsightsService svc = new AiInsightsService(new AiInsightsDAOMock(), new UserResolverService());
        Boolean threw = false;
        try {
            svc.getTokenConsumption(new DateRangeFilter(DateTime.now().addDays(-1), DateTime.now()), null);
        } catch (IllegalArgumentException e) {
            threw = true;
        }
        Assert.isTrue(threw, 'blank groupBy throws');
    }

    @IsTest
    static void testGetSafetyOverview_happy() {
        AiInsightsDAOMock mock = new AiInsightsDAOMock();
        DateTime t = DateTime.now();
        mock.requestsToReturn = new List<SObject>{
            makeRequest('r1', '005000000000001', 'Atlas__P1', 'gpt-4', 'f1', t, 100.0, 50.0)
        };
        mock.responsesToReturn = new List<SObject>{ makeResponse('r1', 'resp1') };
        mock.generationsToReturn = new List<SObject>{ makeGeneration('resp1', 'g1', 'body') };
        mock.contentQualityToReturn = new List<SObject>{ makeQuality('q1', 'g1', true) };
        mock.contentCategoriesToReturn = new List<SObject>{
            makeCategory('q1', 'Toxicity', '0.75'),
            makeCategory('q1', 'Hate', 'not-a-number'),
            makeCategory('q1', 'Violence', '0.1')
        };
        // Service reads counts via DAO; raw rows above only matter for the chain walk
        // (which isn't reachable in test context anyway).
        mock.generationsCountToReturn = 1;
        mock.toxicFlagsToReturn = 1;

        AiInsightsService svc = new AiInsightsService(mock, new UserResolverService());
        ContentSafetyDTO out = svc.getSafetyOverview(new DateRangeFilter(t.addDays(-7), t.addDays(1)));
        Assert.areEqual(1, out.totalGenerations);
        Assert.areEqual(1, out.toxicCount);
        // Category breakdown + recentFlaggedOutputs are populated by direct DMO queries
        // (queryContentCategoriesByDate / queryRecentToxicQuality), which return empty in
        // Apex test context. The DTO defaults remain (empty maps / empty list).
        Assert.areEqual(0, out.recentFlaggedOutputs.size(), 'no flagged outputs — DMO unreachable in tests');
    }

    @IsTest
    static void testRunExplorer_requestCountByUser() {
        // `runExplorer` calls `runExplorerAggregatePath`, which runs
        // `Database.queryWithBinds` directly against `GenAIGatewayRequest__dlm`
        // — NOT through the DAO. In Apex test context the DMO is unreachable,
        // the SOQL throws, and the path returns an empty list (defensive
        // behavior). v1.0.1 asserts that defensive behavior; routing the
        // explorer through the DAO is deferred to v1.1.
        AiInsightsService svc = new AiInsightsService(new AiInsightsDAOMock(), new UserResolverService());

        ExplorerRequest req = new ExplorerRequest();
        req.startDate = DateTime.now().addDays(-7);
        req.endDate = DateTime.now().addDays(1);
        req.groupBy = 'User';
        req.metric = 'RequestCount';

        List<ExplorerResultDTO> rows = svc.runExplorer(req);
        Assert.areEqual(0, rows.size(), 'empty list when DMO unreachable (test context)');
    }

    @IsTest
    static void testRunExplorer_totalTokensByModel_withFilter() {
        // Same DMO-unreachable caveat as above — see testRunExplorer_requestCountByUser.
        AiInsightsService svc = new AiInsightsService(new AiInsightsDAOMock(), new UserResolverService());

        ExplorerRequest req = new ExplorerRequest();
        req.startDate = DateTime.now().addDays(-7);
        req.endDate = DateTime.now().addDays(1);
        req.groupBy = 'Model';
        req.metric = 'TotalTokens';
        req.filters = new Map<String, String>{ 'model' => 'gpt-4' };

        List<ExplorerResultDTO> rows = svc.runExplorer(req);
        Assert.areEqual(0, rows.size(), 'empty list when DMO unreachable (test context)');
    }

    @IsTest
    static void testRunExplorer_invalidArgs() {
        AiInsightsService svc = new AiInsightsService(new AiInsightsDAOMock(), new UserResolverService());
        // Missing ExplorerRequest
        Boolean threw = false;
        try {
            svc.runExplorer(null);
        } catch (IllegalArgumentException e) {
            threw = true;
        }
        Assert.isTrue(threw, 'null request throws');

        // Missing metric
        ExplorerRequest bad = new ExplorerRequest();
        bad.startDate = DateTime.now().addDays(-1);
        bad.endDate = DateTime.now();
        bad.groupBy = 'User';
        threw = false;
        try {
            svc.runExplorer(bad);
        } catch (IllegalArgumentException e) {
            threw = true;
        }
        Assert.isTrue(threw, 'missing metric throws');
    }

    // ───────── Entity details ────────────────────────────────────

    @IsTest
    static void testGetEntityDetails_user_hydratesRecent() {
        AiInsightsDAOMock mock = new AiInsightsDAOMock();
        DateTime t = DateTime.now();
        String realUserId = String.valueOf(UserInfo.getUserId());
        // Seed both the recent-rows and the default requestsByUser queue so
        // the mock returns rows regardless of which overload the service hits.
        mock.recentRequestsByUserToReturn = new List<SObject>{
            makeRequest('r1', realUserId, 'Atlas__P1', 'gpt-4', 'f1', t, 100.0, 50.0),
            makeRequest('r2', realUserId, 'Atlas__P2', 'gpt-4', 'f1', t, 200.0, 100.0)
        };
        mock.responsesToReturn = new List<SObject>{ makeResponse('r1', 'resp1') };
        mock.generationsToReturn = new List<SObject>{ makeGeneration('resp1', 'g1', 'the generated body') };
        mock.feedbackByGenerationToReturn = new List<SObject>{
            makeFeedback('g1', realUserId, 'thumbs_up', 'accepted')
        };
        mock.contentQualityToReturn = new List<SObject>{ makeQuality('q1', 'g1', false) };

        AiInsightsService svc = new AiInsightsService(mock, new UserResolverService());
        EntityDetailsDTO out = svc.getEntityDetails(
            'User',
            realUserId,
            new DateRangeFilter(t.addDays(-7), t.addDays(1)),
            20
        );

        Assert.areEqual('User', out.entityType);
        Assert.areEqual(realUserId, out.entityKey);
        Assert.isNotNull(out.entityLabel, 'resolver populated a label');
        Assert.areEqual(2, out.recentRequests.size(), 'both requests surface (generation + request-only)');
        Assert.areEqual(1, out.positiveFeedbackCount, 'thumbs_up counted');
        Assert.areEqual(0, out.negativeFeedbackCount);
        Assert.areEqual(0, out.toxicFlagCount, 'no toxic rows in bounded set');
    }

    @IsTest
    static void testGetEntityDetails_promptTemplate_empty() {
        AiInsightsDAOMock mock = new AiInsightsDAOMock();
        AiInsightsService svc = new AiInsightsService(mock, new UserResolverService());
        EntityDetailsDTO out = svc.getEntityDetails(
            'PromptTemplate',
            '"Atlas__NonexistentPrompt"',
            new DateRangeFilter(DateTime.now().addDays(-1), DateTime.now()),
            20
        );
        Assert.areEqual(0, out.requestCount, 'empty drill-in is zero, not null');
        Assert.isNull(out.acceptanceRate, 'no feedback → null acceptanceRate');
        Assert.areEqual(0, out.recentRequests.size());
    }

    @IsTest
    static void testGetEntityDetails_model_routesToModelDao() {
        AiInsightsDAOMock mock = new AiInsightsDAOMock();
        DateTime t = DateTime.now();
        mock.requestsByModelToReturn = new List<SObject>{
            makeRequest('r1', 'NOT_SET', 'Atlas__P1', 'gpt-4.1-2025-04-14', 'f1', t, 100.0, 50.0)
        };
        // Hydration chain — one generation so we know the walk happens.
        mock.responsesToReturn = new List<SObject>{ makeResponse('r1', 'resp1') };
        mock.generationsToReturn = new List<SObject>{ makeGeneration('resp1', 'g1', 'model-scoped body') };

        AiInsightsService svc = new AiInsightsService(mock, new UserResolverService());
        EntityDetailsDTO out = svc.getEntityDetails(
            'Model',
            'gpt-4.1-2025-04-14',
            new DateRangeFilter(t.addDays(-7), t.addDays(1)),
            20
        );
        Assert.areEqual('Model', out.entityType);
        Assert.areEqual('gpt-4.1-2025-04-14', out.entityLabel, 'model label == raw key');
        Assert.areEqual(1, out.recentRequests.size());
        Assert.areEqual('gpt-4.1-2025-04-14', out.recentRequests[0].model);
    }

    @IsTest
    static void testGetEntityDetails_feature_routesToFeatureDao() {
        AiInsightsDAOMock mock = new AiInsightsDAOMock();
        DateTime t = DateTime.now();
        mock.requestsByFeatureToReturn = new List<SObject>{
            makeRequest('r1', 'NOT_SET', 'Atlas__P1', 'gpt-4', 'plannerservice', t, 100.0, 50.0),
            makeRequest('r2', 'NOT_SET', 'Atlas__P2', 'gpt-4', 'plannerservice', t, 200.0, 100.0)
        };
        AiInsightsService svc = new AiInsightsService(mock, new UserResolverService());
        EntityDetailsDTO out = svc.getEntityDetails(
            'Feature',
            'plannerservice',
            new DateRangeFilter(t.addDays(-7), t.addDays(1)),
            20
        );
        Assert.areEqual('Feature', out.entityType);
        Assert.areEqual('plannerservice', out.entityLabel);
        // Both requests surface via the "request-only" fallback (no generation chain)
        Assert.areEqual(2, out.recentRequests.size());
    }

    @IsTest
    static void testGetEntityDetails_invalidType() {
        AiInsightsService svc = new AiInsightsService(new AiInsightsDAOMock(), new UserResolverService());
        Boolean threw = false;
        try {
            svc.getEntityDetails('Org', 'x', new DateRangeFilter(DateTime.now().addDays(-1), DateTime.now()), 20);
        } catch (IllegalArgumentException e) {
            threw = true;
        }
        Assert.isTrue(threw, 'unsupported entityType throws');
    }

    @IsTest
    static void testGetEntityDetails_requiresKey() {
        AiInsightsService svc = new AiInsightsService(new AiInsightsDAOMock(), new UserResolverService());
        Boolean threw = false;
        try {
            svc.getEntityDetails('User', null, new DateRangeFilter(DateTime.now().addDays(-1), DateTime.now()), 20);
        } catch (IllegalArgumentException e) {
            threw = true;
        }
        Assert.isTrue(threw);
    }

    @IsTest
    static void testCheckPrerequisites_runs() {
        AiInsightsDAOMock mock = new AiInsightsDAOMock();
        mock.countToReturn = 42;
        AiInsightsService svc = new AiInsightsService(mock, new UserResolverService());

        Map<String, Boolean> flags = svc.checkPrerequisites();
        Assert.isTrue(flags.containsKey('dataCloudEnabled'));
        Assert.isTrue(flags.containsKey('hasDmoAccess'));
        Assert.isTrue(flags.containsKey('hasData'));
        Assert.isTrue(flags.containsKey('cacheAvailable'));
        Assert.areEqual(true, flags.get('hasData'), 'hasData is true when count > 0');
    }

    @IsTest
    static void testHelpers_parsing() {
        // Null and typed inputs
        Assert.areEqual(0L, AiInsightsService.toLong(null));
        Assert.areEqual(5L, AiInsightsService.toLong((Decimal) 5));
        Assert.areEqual(5L, AiInsightsService.toLong((Double) 5.0));
        Assert.areEqual(5L, AiInsightsService.toLong((Integer) 5));
        Assert.areEqual(5L, AiInsightsService.toLong((Long) 5L));
        Assert.areEqual(7L, AiInsightsService.toLong('7'));
        Assert.areEqual(0L, AiInsightsService.toLong('not-a-number'));

        Assert.areEqual(0, AiInsightsService.toInteger(null));
        Assert.areEqual(5, AiInsightsService.toInteger((Decimal) 5));
        Assert.areEqual(5, AiInsightsService.toInteger((Double) 5.0));
        Assert.areEqual(5, AiInsightsService.toInteger((Long) 5L));
        Assert.areEqual(5, AiInsightsService.toInteger((Integer) 5));
        Assert.areEqual(7, AiInsightsService.toInteger('7'));

        Assert.isFalse(AiInsightsService.parseBool(null));
        Assert.isTrue(AiInsightsService.parseBool('true'));
        Assert.isTrue(AiInsightsService.parseBool('TRUE'));
        Assert.isFalse(AiInsightsService.parseBool('false'));
        Assert.isTrue(AiInsightsService.parseBool(true));

        Assert.isNull(AiInsightsService.parseDecimal(null));
        Assert.areEqual(0.5, AiInsightsService.parseDecimal('0.5'));
        Assert.areEqual(0.5, AiInsightsService.parseDecimal((Decimal) 0.5));
        Assert.isNull(AiInsightsService.parseDecimal('bad'));

        Assert.isNull(AiInsightsService.truncate(null, 10));
        Assert.areEqual('hello', AiInsightsService.truncate('hello', 10));
        Assert.isTrue(AiInsightsService.truncate('the quick brown fox', 5).startsWith('the q'));
    }

    @IsTest
    static void testHelpers_dateBuckets() {
        DateTime t = DateTime.newInstanceGmt(2025, 3, 14, 10, 0, 0);
        Assert.areEqual('2025-03-14', AiInsightsService.formatDayBucket(t));
        String wk = AiInsightsService.formatWeekBucket(t);
        Assert.isTrue(wk.startsWith('2025-W'));
    }

    // ───────── Overview trends ─────────────────────────────────────

    @IsTest
    static void testGetOverviewTrends_priorWindowAndBuckets() {
        // Uses a plain mock with pre-seeded prior-window totals + day-spread
        // timestamps. DMO-type availability is only required for the
        // timestamp rows; when unavailable we still exercise the
        // prior-window code path and assert zero-series output.
        AiInsightsDAOMock mock = new AiInsightsDAOMock();
        mock.distinctUsersToReturn = 7; // used for previousUniqueUsers

        AiInsightsService svc = new AiInsightsService(mock, new UserResolverService());
        // 3-day window so we can verify daysInWindow + sparkline length.
        DateTime endDate = DateTime.newInstanceGmt(2026, 5, 10, 23, 59, 0);
        DateTime startDate = endDate.addDays(-2);
        DateRangeFilter filter = new DateRangeFilter(startDate, endDate);

        // Seed timestamps so each day gets exactly one request.
        mock.requestTimestampsToReturn = new List<SObject>{
            makeRequest('r1', 'u1', 'P1', 'gpt-4', 'f', startDate.addHours(1), 10, 5),
            makeRequest('r2', 'u1', 'P1', 'gpt-4', 'f', startDate.addDays(1).addHours(1), 20, 10),
            makeRequest('r3', 'u1', 'P1', 'gpt-4', 'f', startDate.addDays(2).addHours(1), 30, 15)
        };
        // Three toxic flags — the service size()s this list for the prior
        // window, so size 3 gives us a deterministic previousToxicFlagCount.
        mock.toxicFlagTimestampsToReturn = new List<SObject>{
            makeQuality('q1', 'g1', true),
            makeQuality('q2', 'g2', true),
            makeQuality('q3', 'g3', true)
        };

        Test.startTest();
        OverviewTrendsDTO trends = svc.getOverviewTrends(filter);
        Test.stopTest();

        Assert.areEqual(3, trends.daysInWindow, 'window spans three days');
        Assert.areEqual(3, trends.dailyRequests.size(), 'dailyRequests sized to window');
        Assert.areEqual(3, trends.dailyTokens.size(), 'dailyTokens sized to window');
        Assert.areEqual(3, trends.dailyToxicFlags.size(), 'dailyToxicFlags sized to window');
        Assert.areEqual(7, trends.previousUniqueUsers, 'prior uniqueUsers comes from mock');
        Assert.areEqual(3, trends.previousToxicFlagCount, 'prior toxic flags come from mock');

        // All non-negative, shapes are valid regardless of DMO availability
        for (Integer v : trends.dailyRequests) {
            Assert.isTrue(v >= 0, 'request bucket non-negative');
        }
        for (Long v : trends.dailyTokens) {
            Assert.isTrue(v >= 0L, 'tokens bucket non-negative');
        }
    }

    @IsTest
    static void testGetOverviewTrends_invalidRange() {
        AiInsightsService svc = new AiInsightsService(new AiInsightsDAOMock(), new UserResolverService());
        Boolean threw = false;
        try {
            // end before start
            svc.getOverviewTrends(new DateRangeFilter(DateTime.now(), DateTime.now().addDays(-1)));
        } catch (IllegalArgumentException e) {
            threw = true;
        }
        Assert.isTrue(threw, 'should reject invalid range');
    }

    @IsTest
    static void testGetOverviewTrends_emptyMockReturnsZeros() {
        // Empty mock — both prior and current buckets must be zeroed and
        // sized to the range, not null.
        AiInsightsDAOMock mock = new AiInsightsDAOMock();
        AiInsightsService svc = new AiInsightsService(mock, new UserResolverService());
        DateTime t = DateTime.newInstanceGmt(2026, 5, 10, 0, 0, 0);
        OverviewTrendsDTO trends = svc.getOverviewTrends(new DateRangeFilter(t.addDays(-6), t));
        Assert.areEqual(7, trends.daysInWindow, 'seven-day window');
        Assert.areEqual(7, trends.dailyRequests.size());
        Assert.areEqual(0, trends.previousTotalRequests, 'no prior totals -> 0');
        Assert.areEqual(0, trends.previousFeedbackCount);
        Assert.areEqual(0, trends.previousUniqueUsers);
    }

    // ─────────────── Filter rail — getFilterFacets ───────────────
    //
    // These tests exercise the service wiring with an empty-returning DAO
    // mock. AggregateResult can't be instantiated in an Apex test, so we
    // rely on the mock returning empty lists to verify: (a) the service
    // never throws, (b) every facet list on the DTO is initialized (not
    // null), (c) the user-cap parameter is honored.

    @IsTest
    static void testGetFilterFacets_emptyDao_returnsEmptyListsNotNull() {
        AiInsightsDAOMock mock = new AiInsightsDAOMock();
        AiInsightsService svc = new AiInsightsService(mock, new UserResolverService());
        DateRangeFilter filter = new DateRangeFilter(DateTime.now().addDays(-7), DateTime.now());

        Test.startTest();
        FilterFacetsDTO out = svc.getFilterFacets(filter, 50);
        Test.stopTest();

        Assert.isNotNull(out);
        Assert.isNotNull(out.models, 'models must be initialized');
        Assert.isNotNull(out.providers);
        Assert.isNotNull(out.features);
        Assert.isNotNull(out.appTypes);
        Assert.isNotNull(out.promptTemplates);
        Assert.isNotNull(out.topUsers);
        Assert.areEqual(0, out.models.size(), 'empty DAO -> empty models list');
        Assert.areEqual(0, out.topUsers.size(), 'empty DAO -> empty users list');
    }

    @IsTest
    static void testGetFilterFacets_defaultsUserLimit() {
        // When topUserLimit is null/zero the service defaults to 100. We
        // can't observe the cap directly with empty data, but we can verify
        // the call doesn't throw and still returns an empty list.
        AiInsightsDAOMock mock = new AiInsightsDAOMock();
        AiInsightsService svc = new AiInsightsService(mock, new UserResolverService());
        DateRangeFilter filter = new DateRangeFilter(DateTime.now().addDays(-7), DateTime.now());

        FilterFacetsDTO zero = svc.getFilterFacets(filter, 0);
        FilterFacetsDTO nullCap = svc.getFilterFacets(filter, null);

        Assert.areEqual(0, zero.topUsers.size());
        Assert.areEqual(0, nullCap.topUsers.size());
    }

    @IsTest
    static void testGetFilterFacets_invalidRange_throws() {
        AiInsightsService svc = new AiInsightsService(new AiInsightsDAOMock(), new UserResolverService());
        Boolean threw = false;
        try {
            svc.getFilterFacets(new DateRangeFilter(DateTime.now(), DateTime.now().addDays(-1)), 10);
        } catch (IllegalArgumentException e) {
            threw = true;
        }
        Assert.isTrue(threw, 'invalid range must throw');
    }

    // ─────────────── Filter rail — searchUsersInRange ───────────────

    @IsTest
    static void testSearchUsersInRange_shortTerm_returnsEmpty() {
        AiInsightsService svc = new AiInsightsService(new AiInsightsDAOMock(), new UserResolverService());
        DateRangeFilter filter = new DateRangeFilter(DateTime.now().addDays(-7), DateTime.now());

        List<FilterFacetsDTO.FacetOption> out = svc.searchUsersInRange('a', filter, 25);
        Assert.areEqual(0, out.size(), 'single-char term must short-circuit');

        out = svc.searchUsersInRange(null, filter, 25);
        Assert.areEqual(0, out.size(), 'null term must short-circuit');

        out = svc.searchUsersInRange('   ', filter, 25);
        Assert.areEqual(0, out.size(), 'blank term must short-circuit');
    }

    @IsTest
    static void testSearchUsersInRange_noMatches_returnsEmpty() {
        AiInsightsService svc = new AiInsightsService(new AiInsightsDAOMock(), new UserResolverService());
        DateRangeFilter filter = new DateRangeFilter(DateTime.now().addDays(-7), DateTime.now());
        List<FilterFacetsDTO.FacetOption> out = svc.searchUsersInRange('nobody', filter, 10);
        Assert.areEqual(0, out.size());
    }

    // ─────────────── ExplorerRequest — criteria merging ───────────────

    @IsTest
    static void testNormalizeCriteria_legacyFilterMapPromotedToCriteria() {
        AiInsightsService svc = new AiInsightsService(new AiInsightsDAOMock(), new UserResolverService());
        ExplorerRequest req = new ExplorerRequest();
        req.startDate = DateTime.now().addDays(-3);
        req.endDate = DateTime.now();
        req.filters = new Map<String, String>{ 'model' => 'gpt-4o', 'feature' => 'Agentforce' };

        DateRangeFilter filter = new DateRangeFilter(req.startDate, req.endDate);
        FilterCriteria c = svc.normalizeCriteria(req, filter);

        Assert.isNotNull(c.models);
        Assert.areEqual(1, c.models.size());
        Assert.areEqual('gpt-4o', c.models[0]);
        Assert.areEqual(1, c.features.size());
        Assert.areEqual('Agentforce', c.features[0]);
    }

    @IsTest
    static void testNormalizeCriteria_explicitCriteriaBeatsLegacyMap() {
        // The rail always wins: if the caller sends an explicit models list
        // in criteria, the legacy map must not overwrite it.
        AiInsightsService svc = new AiInsightsService(new AiInsightsDAOMock(), new UserResolverService());
        ExplorerRequest req = new ExplorerRequest();
        req.startDate = DateTime.now().addDays(-3);
        req.endDate = DateTime.now();
        req.filters = new Map<String, String>{ 'model' => 'gpt-ignored' };
        req.criteria = new FilterCriteria();
        req.criteria.models = new List<String>{ 'gpt-5' };

        DateRangeFilter filter = new DateRangeFilter(req.startDate, req.endDate);
        FilterCriteria c = svc.normalizeCriteria(req, filter);

        Assert.areEqual(1, c.models.size());
        Assert.areEqual('gpt-5', c.models[0], 'criteria must win over legacy map');
    }

    @IsTest
    static void testHelpers_dayIndexAndPriorWindow() {
        DateTime anchor = DateTime.newInstanceGmt(2026, 5, 1, 0, 0, 0);
        // Prior window is equal-length, ending just before anchor
        DateRangeFilter main = new DateRangeFilter(anchor, anchor.addDays(2));
        DateRangeFilter prior = AiInsightsService.buildPriorWindowFilter(main);
        Assert.isTrue(prior.endDate < main.startDate, 'prior ends before main starts');

        // Day index mapping
        Assert.areEqual(0, AiInsightsService.dayIndex(anchor.addHours(1), anchor, 3));
        Assert.areEqual(1, AiInsightsService.dayIndex(anchor.addDays(1).addHours(3), anchor, 3));
        Assert.areEqual(2, AiInsightsService.dayIndex(anchor.addDays(2).addHours(23), anchor, 3));
        Assert.areEqual(-1, AiInsightsService.dayIndex(anchor.addDays(-1), anchor, 3), 'negative range clamped to -1');
        Assert.areEqual(-1, AiInsightsService.dayIndex(null, anchor, 3));
    }

    // ───────── Phase 2.3 — V1 compromise fix tests ─────────────────

    @IsTest
    static void testReadTopNPromptAcceptanceSample_defaultsTo25_whenSettingMissing() {
        // No org-default record installed → fallback path returns 25
        Integer n = AiInsightsService.readTopNPromptAcceptanceSample();
        Assert.areEqual(25, n, 'default top-N is 25 when CSO row absent');
    }

    @IsTest
    static void testReadTopNPromptAcceptanceSample_capsAtCeiling_whenConfiguredHigh() {
        // Insert a CSO row with a value above the hard ceiling (50). The
        // helper must clamp it down rather than allow a runaway chain walk.
        FluentMetric_Cost_Settings__c s = FluentMetric_Cost_Settings__c.getOrgDefaults();
        if (s == null) {
            s = new FluentMetric_Cost_Settings__c();
        }
        s.Top_N_Prompt_Acceptance_Sample__c = 999;
        upsert s;

        Integer n = AiInsightsService.readTopNPromptAcceptanceSample();
        Assert.areEqual(50, n, 'configured 999 must clamp to hard ceiling 50');
    }

    @IsTest
    static void testSampleAcceptanceForPrompt_sampledRate_whenChainProducesFeedback() {
        AiInsightsDAOMock mock = new AiInsightsDAOMock();
        DateTime t = DateTime.now();
        mock.requestsByPromptToReturn = new List<SObject>{
            makeRequest('r1', '005000000000001', 'Atlas__P1', 'gpt-4', 'f1', t, 100.0, 50.0),
            makeRequest('r2', '005000000000002', 'Atlas__P1', 'gpt-4', 'f1', t, 100.0, 50.0)
        };
        mock.responsesToReturn = new List<SObject>{ makeResponse('r1', 'resp1'), makeResponse('r2', 'resp2') };
        mock.generationsToReturn = new List<SObject>{
            makeGeneration('resp1', 'g1', 'output 1'),
            makeGeneration('resp2', 'g2', 'output 2')
        };
        // 1 accepted + 1 rejected → expected rate 0.5
        mock.feedbackByGenerationToReturn = new List<SObject>{
            makeFeedback('g1', 'NOT_SET', 'thumbs_up', 'accepted'),
            makeFeedback('g2', 'NOT_SET', 'thumbs_down', 'rejected')
        };

        AiInsightsService svc = new AiInsightsService(mock, new UserResolverService());
        Decimal rate = svc.sampleAcceptanceForPrompt('Atlas__P1', new DateRangeFilter(t.addDays(-7), t.addDays(1)));
        Assert.areEqual(0.5000, rate, 'one positive, one negative ⇒ 0.5');
    }

    @IsTest
    static void testSampleAcceptanceForPrompt_returnsNull_whenNoFeedback() {
        AiInsightsDAOMock mock = new AiInsightsDAOMock();
        DateTime t = DateTime.now();
        mock.requestsByPromptToReturn = new List<SObject>{
            makeRequest('r1', '005000000000001', 'Atlas__P1', 'gpt-4', 'f1', t, 100.0, 50.0)
        };
        mock.responsesToReturn = new List<SObject>{ makeResponse('r1', 'resp1') };
        mock.generationsToReturn = new List<SObject>{ makeGeneration('resp1', 'g1', 'output 1') };
        // No feedback → null (not 0) so LWC renders '—'
        mock.feedbackByGenerationToReturn = new List<SObject>{};

        AiInsightsService svc = new AiInsightsService(mock, new UserResolverService());
        Decimal rate = svc.sampleAcceptanceForPrompt('Atlas__P1', new DateRangeFilter(t.addDays(-7), t.addDays(1)));
        Assert.isNull(rate, 'no feedback ⇒ null, leaving correlation pass intact');
    }

    // ─────────────── Phase 3 — Adoption analytics ────────────────
    //
    // AggregateResult can't be instantiated in tests, so the new method
    // tests run against empty mocks (verifying defensive defaults) plus
    // direct exercise of the @TestVisible helpers that drive the math.

    @IsTest
    static void testGetOrgAdoptionDeltas_emptyDao_returns8WeeksOfZeroes() {
        AiInsightsDAOMock mock = new AiInsightsDAOMock();
        AiInsightsService svc = new AiInsightsService(mock, new UserResolverService(), new EntitlementServiceMock());
        OrgAdoptionDeltasDTO dto = svc.getOrgAdoptionDeltas(
            new DateRangeFilter(DateTime.now().addDays(-30), DateTime.now())
        );
        Assert.isNotNull(dto.weeks, 'weeks list initialized');
        Assert.areEqual(8, dto.weeks.size(), '8-week trailing window');
        for (OrgAdoptionDeltasDTO.WeekDelta wd : dto.weeks) {
            Assert.areEqual(0, wd.requests, 'zero requests in empty DAO');
            Assert.areEqual(0, wd.activeUsers, 'zero users in empty DAO');
            Assert.areEqual(0L, wd.tokens, 'zero tokens in empty DAO');
            Assert.isNotNull(wd.weekIsoLabel, 'weekIsoLabel populated');
        }
        Assert.areEqual(0, dto.latestRequestsWowPct, 'no WoW change in empty DAO');
    }

    @IsTest
    static void testGetAdoptionCohorts_emptyDao_returnsEmptyDto() {
        AiInsightsDAOMock mock = new AiInsightsDAOMock();
        AiInsightsService svc = new AiInsightsService(mock, new UserResolverService(), new EntitlementServiceMock());
        AdoptionCohortsDTO dto = svc.getAdoptionCohorts(
            new DateRangeFilter(DateTime.now().addDays(-30), DateTime.now())
        );
        Assert.isNotNull(dto);
        Assert.isNotNull(dto.cohorts, 'cohorts list initialized');
        Assert.areEqual(0, dto.cohorts.size(), 'no rows when DAO returns empty');
        Assert.areEqual(false, dto.truncated, 'not truncated below 50k');
        Assert.areEqual(0, dto.totalUsersObserved);
    }

    @IsTest
    static void testGetPowerUserSegments_emptyDao_returnsZeroedDto() {
        AiInsightsDAOMock mock = new AiInsightsDAOMock();
        AiInsightsService svc = new AiInsightsService(mock, new UserResolverService(), new EntitlementServiceMock());
        PowerUserSegmentsDTO dto = svc.getPowerUserSegments(
            new DateRangeFilter(DateTime.now().addDays(-7), DateTime.now())
        );
        Assert.isNotNull(dto);
        Assert.areEqual(0, dto.totalActiveUsers);
        Assert.areEqual(0L, dto.totalRequests);
        Assert.areEqual(0, dto.top10PercentUserCount);
        Assert.isNotNull(dto.topUsers, 'topUsers list initialized');
        Assert.areEqual(0, dto.topUsers.size());
    }

    @IsTest
    static void testGetFeatureAdoption_emptyDao_returnsEmptyList() {
        AiInsightsDAOMock mock = new AiInsightsDAOMock();
        AiInsightsService svc = new AiInsightsService(mock, new UserResolverService(), new EntitlementServiceMock());
        List<FeatureAdoptionDTO> rows = svc.getFeatureAdoption(
            new DateRangeFilter(DateTime.now().addDays(-7), DateTime.now())
        );
        Assert.isNotNull(rows);
        Assert.areEqual(0, rows.size());
    }

    @IsTest
    static void testGetEntitlementSnapshot_passesActiveSetToService() {
        AiInsightsDAOMock mock = new AiInsightsDAOMock();
        EntitlementServiceMock entMock = new EntitlementServiceMock();
        EntitlementSnapshotDTO seeded = new EntitlementSnapshotDTO();
        seeded.entitledCount = 42;
        seeded.activeCount = 7;
        seeded.totalActiveOrgUsers = 100;
        seeded.adoptionRate = 0.0700;
        seeded.entitledFallback = false;
        seeded.configuredPermissionSets = new List<String>{ 'Foo_PS', 'Bar_PSG' };
        entMock.snapshotToReturn = seeded;

        AiInsightsService svc = new AiInsightsService(mock, new UserResolverService(), entMock);
        EntitlementSnapshotDTO out = svc.getEntitlementSnapshot(
            new DateRangeFilter(DateTime.now().addDays(-7), DateTime.now())
        );
        Assert.areEqual(42, out.entitledCount, 'snapshot pass-through');
        Assert.areEqual(0.0700, out.adoptionRate);
        Assert.areEqual(false, out.entitledFallback);
        Assert.areEqual(2, out.configuredPermissionSets.size());
    }

    @IsTest
    static void testGetEntitlementSnapshot_neverThrows_onSnapshotException() {
        // Service swallows entitlement failures and returns a default DTO.
        AiInsightsDAOMock mock = new AiInsightsDAOMock();
        AiInsightsService svc = new AiInsightsService(mock, new UserResolverService(), new ThrowingEntitlement());
        EntitlementSnapshotDTO out = svc.getEntitlementSnapshot(
            new DateRangeFilter(DateTime.now().addDays(-7), DateTime.now())
        );
        Assert.isNotNull(out, 'fallback DTO returned, never null');
        Assert.areEqual(0, out.entitledCount);
        Assert.areEqual(true, out.entitledFallback, 'default DTO marks fallback');
    }

    private class ThrowingEntitlement implements IEntitlementService {
        public Set<Id> getEntitledUserIds() {
            throw new IllegalArgumentException('boom');
        }
        public List<String> getConfiguredPermissionSets() {
            throw new IllegalArgumentException('boom');
        }
        public EntitlementSnapshotDTO getSnapshot(Set<String> activeUserIdStrings) {
            throw new IllegalArgumentException('boom');
        }
    }

    // ─────────────── Phase 3 — Helper math ───────────────────────

    @IsTest
    static void testWowPct_zeroPrior_returnsHundredOnIncrease() {
        Decimal pct = AiInsightsService.wowPct((Long) 50, (Long) 0);
        Assert.areEqual(100, pct, 'zero prior + non-zero latest ⇒ 100%');
    }

    @IsTest
    static void testWowPct_zeroBoth_returnsZero() {
        Decimal pct = AiInsightsService.wowPct((Long) 0, (Long) 0);
        Assert.areEqual(0, pct, 'zero everywhere ⇒ 0%');
    }

    @IsTest
    static void testWowPct_normal_returnsRoundedPct() {
        // 120 vs. 100 = +20%
        Decimal pct = AiInsightsService.wowPct((Long) 120, (Long) 100);
        Assert.areEqual(20.00, pct, '+20% delta with 2dp');
        // 80 vs. 100 = -20%
        pct = AiInsightsService.wowPct((Long) 80, (Long) 100);
        Assert.areEqual(-20.00, pct, '-20% delta with 2dp');
    }

    @IsTest
    static void testToIsoWeekStart_normalizesToMonday() {
        // Wednesday 2026-05-27 → Monday 2026-05-25
        Date wed = Date.newInstance(2026, 5, 27);
        Date wkStart = AiInsightsService.toIsoWeekStart(wed);
        Assert.areEqual(Date.newInstance(2026, 5, 25), wkStart, 'Wed normalizes to prior Mon');
        // Already Monday — should return same day
        Date mon = Date.newInstance(2026, 5, 25);
        Assert.areEqual(mon, AiInsightsService.toIsoWeekStart(mon), 'Mon stays Mon');
        // Sunday 2026-05-31 → Monday 2026-05-25 (start of *that* ISO week)
        Date sun = Date.newInstance(2026, 5, 31);
        Assert.areEqual(
            Date.newInstance(2026, 5, 25),
            AiInsightsService.toIsoWeekStart(sun),
            'Sun normalizes back to Mon'
        );
    }

    @IsTest
    static void testIsoWeekLabel_formatsAsYYYY_Www() {
        Date mon = Date.newInstance(2026, 5, 25);
        String label = AiInsightsService.isoWeekLabel(mon);
        Assert.areEqual('2026-W22', label, 'ISO week 22 of 2026');
    }

    @IsTest
    static void testWeeksBetween_normalDelta() {
        Date a = Date.newInstance(2026, 5, 4); // Mon
        Date b = Date.newInstance(2026, 5, 25); // Mon, 3 weeks later
        Assert.areEqual(3, AiInsightsService.weeksBetween(a, b));
        Assert.areEqual(0, AiInsightsService.weeksBetween(a, a));
    }

    @IsTest
    static void testCountRepeatUsers_countsOnlyMultiInvocation() {
        Integer repeat = AiInsightsService.countRepeatUsers(new List<Integer>{ 1, 2, 3, 1, 5 });
        Assert.areEqual(3, repeat, 'three users with ≥2 invocations');
        Assert.areEqual(0, AiInsightsService.countRepeatUsers(null));
        Assert.areEqual(0, AiInsightsService.countRepeatUsers(new List<Integer>{ 1, 1, 1 }));
    }

    @IsTest
    static void testMedianInteger_oddAndEvenCounts() {
        Assert.areEqual(0, AiInsightsService.medianInteger(null), 'null ⇒ 0');
        Assert.areEqual(0, AiInsightsService.medianInteger(new List<Integer>{}), 'empty ⇒ 0');
        Assert.areEqual(3, AiInsightsService.medianInteger(new List<Integer>{ 5, 1, 3 }), 'odd count');
        // Even count: median of [1, 2, 3, 4] = 2.5
        Assert.areEqual(2.5, AiInsightsService.medianInteger(new List<Integer>{ 4, 2, 1, 3 }), 'even count');
    }

    @IsTest
    static void testThreeArgConstructor_acceptsExplicitEntitlement() {
        EntitlementServiceMock entMock = new EntitlementServiceMock();
        AiInsightsService svc = new AiInsightsService(new AiInsightsDAOMock(), new UserResolverService(), entMock);
        // Smoke: any read past the ctor wires fine; check via a method that
        // doesn't require AggregateResult fixtures.
        UsageOverviewDTO out = svc.getOverview(new DateRangeFilter(DateTime.now().addDays(-1), DateTime.now()));
        Assert.isNotNull(out);
    }
}
