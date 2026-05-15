@IsTest
private class FmTableauNextTest {
    private class StubService extends AiInsightsService {
        public Boolean shouldThrow = false;
        public UsageOverviewDTO overview;
        public List<UserUsageDTO> users = new List<UserUsageDTO>();
        public List<PromptUsageDTO> prompts = new List<PromptUsageDTO>();

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
}
