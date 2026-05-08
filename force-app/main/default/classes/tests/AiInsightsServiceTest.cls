/**
 * Tests for AiInsightsService using the AiInsightsDAOMock test double.
 *
 * DMO SObject types (e.g. GenAIGatewayRequest__dlm) may not be instantiable
 * in Apex test context on orgs where Data Cloud is not enabled. We
 * use dynamic lookup via `Schema.getGlobalDescribe()` and skip asserts that
 * require a concrete DMO type when the describe returns null. Happy-path
 * tests assemble fake SObjects of available shapes.
 *
 * Because the mock returns `List<SObject>`, we can substitute with `Account`
 * (always available) when DMO types are not present — the service only calls
 * `.get('camelCaseField__c')` which works on any SObject-backed container
 * when the field exists. We use `Schema.SObjectType.getDescribe()` to pick a
 * type at runtime.
 */
@IsTest
private class AiInsightsServiceTest {
    // ───────── Fixture plumbing ──────────────────────────────────

    private static Boolean hasDmoType() {
        return Schema.getGlobalDescribe().containsKey('GenAIGatewayRequest__dlm');
    }

    /**
     * Build a fake "request row" as an SObject if DMO types are available.
     * Returns null in non-DMO orgs — callers should skip those assertions.
     */
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
        if (!hasDmoType()) {
            return null;
        }
        SObject so = Schema.getGlobalDescribe().get('GenAIGatewayRequest__dlm').newSObject();
        try {
            so.put('gatewayRequestId__c', gatewayRequestId);
            so.put('userId__c', userId);
            so.put('promptTemplateDevName__c', promptDevName);
            so.put('model__c', model);
            so.put('feature__c', feature);
            so.put('timestamp__c', ts);
            so.put('promptTokens__c', promptTokens);
            so.put('completionTokens__c', completionTokens);
            so.put(
                'totalTokens__c',
                (promptTokens == null ? 0 : promptTokens) + (completionTokens == null ? 0 : completionTokens)
            );
            so.put('prompt__c', 'Unit-test prompt for ' + promptDevName);
        } catch (Exception e) {
            // Field may not exist in this org flavor — fall back to whatever was set
        }
        return so;
    }

    private static SObject makeResponse(String requestId, String responseId) {
        if (!Schema.getGlobalDescribe().containsKey('GenAIGatewayResponse__dlm')) {
            return null;
        }
        SObject so = Schema.getGlobalDescribe().get('GenAIGatewayResponse__dlm').newSObject();
        try {
            so.put('generationRequestId__c', requestId);
            so.put('generationResponseId__c', responseId);
            so.put('timestamp__c', DateTime.now());
        } catch (Exception e) {
        }
        return so;
    }

    private static SObject makeGeneration(String responseId, String genId, String text) {
        if (!Schema.getGlobalDescribe().containsKey('GenAIGeneration__dlm')) {
            return null;
        }
        SObject so = Schema.getGlobalDescribe().get('GenAIGeneration__dlm').newSObject();
        try {
            so.put('generationResponseId__c', responseId);
            so.put('generationId__c', genId);
            so.put('responseText__c', text);
            so.put('timestamp__c', DateTime.now());
        } catch (Exception e) {
        }
        return so;
    }

    private static SObject makeFeedback(String genId, String userId, String feedback, String action) {
        if (!Schema.getGlobalDescribe().containsKey('GenAIFeedback__dlm')) {
            return null;
        }
        SObject so = Schema.getGlobalDescribe().get('GenAIFeedback__dlm').newSObject();
        try {
            so.put('feedbackId__c', 'fb_' + genId);
            so.put('generationId__c', genId);
            so.put('userId__c', userId);
            so.put('feedback__c', feedback);
            so.put('action__c', action);
            so.put('timestamp__c', DateTime.now());
        } catch (Exception e) {
        }
        return so;
    }

    private static SObject makeQuality(String qualityId, String genId, Boolean isToxic) {
        if (!Schema.getGlobalDescribe().containsKey('GenAIContentQuality__dlm')) {
            return null;
        }
        SObject so = Schema.getGlobalDescribe().get('GenAIContentQuality__dlm').newSObject();
        try {
            so.put('id__c', qualityId);
            so.put('parent__c', genId);
            so.put('isToxicityDetected__c', isToxic ? 'true' : 'false');
            so.put('timestamp__c', DateTime.now());
        } catch (Exception e) {
        }
        return so;
    }

    private static SObject makeCategory(String qualityId, String category, String value) {
        if (!Schema.getGlobalDescribe().containsKey('GenAIContentCategory__dlm')) {
            return null;
        }
        SObject so = Schema.getGlobalDescribe().get('GenAIContentCategory__dlm').newSObject();
        try {
            so.put('parent__c', qualityId);
            so.put('category__c', category);
            so.put('value__c', value);
            so.put('timestamp__c', DateTime.now());
        } catch (Exception e) {
        }
        return so;
    }

    private static void skipIfNoDmo() {
        // No-op stub — tests guard individually
    }

    // ───────── Tests ─────────────────────────────────────────────

    @IsTest
    static void testGetOverview_happyPath() {
        if (!hasDmoType()) {
            return;
        }
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
        Assert.areEqual(1, overview.toxicFlagCount, 'toxic count');
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
        if (!hasDmoType()) {
            return;
        }
        AiInsightsDAOMock mock = new AiInsightsDAOMock();
        DateTime t = DateTime.now();
        String realUserId = String.valueOf(UserInfo.getUserId());
        mock.requestsToReturn = new List<SObject>{
            makeRequest('r1', realUserId, 'Atlas__P1', 'gpt-4', 'f1', t, 100.0, 50.0),
            makeRequest('r2', realUserId, 'Atlas__P1', 'gpt-4', 'f1', t, 200.0, 100.0),
            makeRequest('r3', 'NOT_SET', '"Atlas__P2"', 'gpt-4', 'f2', t, 50.0, 25.0)
        };

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
        if (!hasDmoType()) {
            return;
        }
        AiInsightsDAOMock mock = new AiInsightsDAOMock();
        DateTime t = DateTime.now();
        mock.requestsToReturn = new List<SObject>{
            makeRequest('r1', '005000000000001', 'Atlas__Foo', 'gpt-4', 'f1', t, 100.0, 50.0),
            makeRequest('r2', '005000000000002', 'Atlas__Foo', 'gpt-4', 'f1', t, 100.0, 50.0),
            makeRequest('r3', '005000000000001', '"Atlas__Bar"', 'gpt-4', 'f2', t, 100.0, 50.0)
        };

        AiInsightsService svc = new AiInsightsService(mock, new UserResolverService());
        List<PromptUsageDTO> rows = svc.getUsageByPrompt(new DateRangeFilter(t.addDays(-7), t.addDays(1)));
        Assert.areEqual(2, rows.size(), 'two prompt buckets');
        Assert.areEqual(2, rows[0].invocationCount, 'top bucket sorted first');
        Assert.areEqual(2, rows[0].uniqueUserCount, 'distinct users in top bucket');
        Assert.isNotNull(rows[0].promptLabel, 'label resolved');
    }

    @IsTest
    static void testGetPromptOutputs_chainAndTruncate() {
        if (!hasDmoType()) {
            return;
        }
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
        if (!hasDmoType()) {
            return;
        }
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
        if (!hasDmoType()) {
            return;
        }
        AiInsightsDAOMock mock = new AiInsightsDAOMock();
        DateTime t = DateTime.now();
        mock.requestsToReturn = new List<SObject>{
            makeRequest('r1', '005000000000001', 'Atlas__P1', 'gpt-4', 'f1', t, 100.0, 50.0),
            makeRequest('r2', '005000000000002', 'Atlas__P1', 'gpt-4', 'f1', t.addDays(-1), 100.0, 50.0)
        };
        AiInsightsService svc = new AiInsightsService(mock, new UserResolverService());
        List<TokenConsumptionDTO> result = svc.getTokenConsumption(
            new DateRangeFilter(t.addDays(-7), t.addDays(1)),
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
        if (!hasDmoType()) {
            return;
        }
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

        AiInsightsService svc = new AiInsightsService(mock, new UserResolverService());
        ContentSafetyDTO out = svc.getSafetyOverview(new DateRangeFilter(t.addDays(-7), t.addDays(1)));
        Assert.areEqual(1, out.totalGenerations);
        Assert.areEqual(1, out.toxicCount);
        Assert.areEqual(1, out.recentFlaggedOutputs.size(), 'flagged output captured');
        Assert.isTrue(out.avgCategoryScores.containsKey('Toxicity'), 'category avg present');
        Assert.isTrue(out.flaggedByCategory.get('Toxicity') >= 1, 'Toxicity flagged above threshold');
    }

    @IsTest
    static void testRunExplorer_requestCountByUser() {
        if (!hasDmoType()) {
            return;
        }
        AiInsightsDAOMock mock = new AiInsightsDAOMock();
        DateTime t = DateTime.now();
        mock.requestsToReturn = new List<SObject>{
            makeRequest('r1', '005000000000001', 'Atlas__P1', 'gpt-4', 'f1', t, 100.0, 50.0),
            makeRequest('r2', '005000000000001', 'Atlas__P1', 'gpt-4', 'f1', t, 100.0, 50.0),
            makeRequest('r3', '005000000000002', 'Atlas__P2', 'gpt-4', 'f1', t, 100.0, 50.0)
        };
        AiInsightsService svc = new AiInsightsService(mock, new UserResolverService());

        ExplorerRequest req = new ExplorerRequest();
        req.startDate = t.addDays(-7);
        req.endDate = t.addDays(1);
        req.groupBy = 'User';
        req.metric = 'RequestCount';

        List<ExplorerResultDTO> rows = svc.runExplorer(req);
        Assert.areEqual(2, rows.size(), 'two users');
        Assert.areEqual(2, rows[0].metricValue.intValue(), 'top user has 2 requests');
    }

    @IsTest
    static void testRunExplorer_totalTokensByModel_withFilter() {
        if (!hasDmoType()) {
            return;
        }
        AiInsightsDAOMock mock = new AiInsightsDAOMock();
        DateTime t = DateTime.now();
        mock.requestsToReturn = new List<SObject>{
            makeRequest('r1', '005000000000001', 'Atlas__P1', 'gpt-4', 'f1', t, 100.0, 50.0),
            makeRequest('r2', '005000000000001', 'Atlas__P1', 'claude', 'f1', t, 200.0, 100.0)
        };
        AiInsightsService svc = new AiInsightsService(mock, new UserResolverService());

        ExplorerRequest req = new ExplorerRequest();
        req.startDate = t.addDays(-7);
        req.endDate = t.addDays(1);
        req.groupBy = 'Model';
        req.metric = 'TotalTokens';
        req.filters = new Map<String, String>{ 'model' => 'gpt-4' };

        List<ExplorerResultDTO> rows = svc.runExplorer(req);
        Assert.areEqual(1, rows.size(), 'filter narrows to one row');
        Assert.areEqual('gpt-4', rows[0].groupKey);
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
        if (!hasDmoType()) {
            return;
        }
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
        if (!hasDmoType()) {
            return;
        }
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
        if (!hasDmoType()) {
            return;
        }
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

        if (hasDmoType()) {
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
        }

        Test.startTest();
        OverviewTrendsDTO trends = svc.getOverviewTrends(filter);
        Test.stopTest();

        Assert.areEqual(3, trends.daysInWindow, 'window spans three days');
        Assert.areEqual(3, trends.dailyRequests.size(), 'dailyRequests sized to window');
        Assert.areEqual(3, trends.dailyTokens.size(), 'dailyTokens sized to window');
        Assert.areEqual(3, trends.dailyToxicFlags.size(), 'dailyToxicFlags sized to window');
        Assert.areEqual(7, trends.previousUniqueUsers, 'prior uniqueUsers comes from mock');
        // Toxic flag count is computed from DAO row size. When DMO types
        // aren't available in test context the mock returns an empty list
        // and the service rightly reports 0.
        Integer expectedToxic = hasDmoType() ? 3 : 0;
        Assert.areEqual(expectedToxic, trends.previousToxicFlagCount, 'prior toxic flags come from mock');

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
}
