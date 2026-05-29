@IsTest
private class AiInsightsTestUtilSmokeTest {
    @IsTest
    static void buildsRequestRow() {
        SObject so = AiInsightsTestUtil.makeRequest(
            'r1',
            '005000000000001',
            'Atlas__P1',
            'gpt-4',
            'f1',
            DateTime.now(),
            100,
            50
        );
        Assert.isNotNull(so, 'helper returns non-null SObject');
        Assert.areEqual('005000000000001', String.valueOf(so.get('userId__c')));
        Assert.areEqual(150.0, (Decimal) so.get('totalTokens__c'));
    }

    @IsTest
    static void buildsFeedbackRow() {
        SObject so = AiInsightsTestUtil.makeFeedback('g1', '005000000000001', 'thumbs_up', 'accepted');
        Assert.isNotNull(so);
        Assert.areEqual('thumbs_up', String.valueOf(so.get('feedback__c')));
    }

    @IsTest
    static void producesAggregateResult() {
        AggregateResult ar = AiInsightsTestUtil.oneRowAggregate();
        Assert.isNotNull(ar);
        Assert.areEqual(1, Integer.valueOf(ar.get('cnt')));
    }

    @IsTest
    static void aggregateRow_setsAliasesFromMap() {
        AggregateResult ar = AiInsightsTestUtil.aggregateRow(
            new Map<String, Object>{ 'gkey' => 'user_007', 'cnt' => 42, 'tt' => 350 }
        );
        Assert.isNotNull(ar);
        Assert.areEqual('user_007', String.valueOf(ar.get('gkey')));
        Assert.areEqual(42, Integer.valueOf(ar.get('cnt')));
        Assert.areEqual(350, Integer.valueOf(ar.get('tt')));
    }

    @IsTest
    static void aggregateRows_returnsMultipleGroupedRows() {
        List<AggregateResult> rs = AiInsightsTestUtil.aggregateRows(
            new List<Map<String, Object>>{
                new Map<String, Object>{ 'gkey' => 'u1', 'cnt' => 5, 'tt' => 100 },
                new Map<String, Object>{ 'gkey' => 'u2', 'cnt' => 3, 'tt' => 50 }
            }
        );
        Assert.areEqual(2, rs.size(), 'two distinct group keys ⇒ two rows');
    }
}
