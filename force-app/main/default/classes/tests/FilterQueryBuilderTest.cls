/**
 * Unit tests for FilterQueryBuilder — the WHERE/binds factory that backs
 * every dynamic filter path on the Explorer. The builder never touches the
 * DMO itself, so these tests don't need a mock DAO — they just verify
 * clause shape and the bind map.
 *
 * Coverage target: every branch in appendInClause + the required-date
 * validation, plus a "no caller value is ever interpolated" sanity check
 * (the binds map must always own the values, not the SOQL string).
 */
@IsTest
private class FilterQueryBuilderTest {
    private static final DateTime START_DT = DateTime.newInstance(2026, 4, 1, 0, 0, 0);
    private static final DateTime END_DT = DateTime.newInstance(2026, 4, 30, 23, 59, 59);

    @IsTest
    static void build_dateOnly_producesDateBounds() {
        FilterQueryBuilder.Result r = FilterQueryBuilder.build(START_DT, END_DT);
        System.assertNotEquals(null, r);
        System.assert(r.whereClause.contains('timestamp__c >= :startDate'), 'Missing start bound');
        System.assert(r.whereClause.contains('timestamp__c <= :endDate'), 'Missing end bound');
        System.assertEquals(START_DT, r.binds.get('startDate'));
        System.assertEquals(END_DT, r.binds.get('endDate'));
        System.assertEquals(2, r.binds.size(), 'Only date binds expected when no dimensions are set');
    }

    @IsTest
    static void build_nullCriteria_throws() {
        Boolean threw = false;
        try {
            FilterQueryBuilder.build((FilterCriteria) null);
        } catch (IllegalArgumentException e) {
            threw = true;
        }
        System.assert(threw, 'Expected IllegalArgumentException for null criteria');
    }

    @IsTest
    static void build_missingDates_throws() {
        FilterCriteria c = new FilterCriteria();
        Boolean threw = false;
        try {
            FilterQueryBuilder.build(c);
        } catch (IllegalArgumentException e) {
            threw = true;
        }
        System.assert(threw, 'Expected IllegalArgumentException for missing dates');
    }

    @IsTest
    static void build_singleDimension_emitsInClause() {
        FilterCriteria c = new FilterCriteria(START_DT, END_DT);
        c.models = new List<String>{ 'gpt-4o' };
        FilterQueryBuilder.Result r = FilterQueryBuilder.build(c);
        System.assert(r.whereClause.contains('model__c IN :models'), 'Expected IN clause: ' + r.whereClause);
        System.assert(r.binds.containsKey('models'));
        Set<String> bound = (Set<String>) r.binds.get('models');
        System.assert(bound.contains('gpt-4o'));
    }

    @IsTest
    static void build_multipleDimensions_allBound() {
        FilterCriteria c = new FilterCriteria(START_DT, END_DT);
        c.userIds = new List<String>{ '005000000000001', '005000000000002' };
        c.models = new List<String>{ 'gpt-4o', 'gpt-5' };
        c.features = new List<String>{ 'Agentforce' };
        c.providers = new List<String>{ 'OpenAI' };
        c.appTypes = new List<String>{ 'Copilot' };
        c.promptTemplateDevNames = new List<String>{ 'SomeTemplate' };

        FilterQueryBuilder.Result r = FilterQueryBuilder.build(c);
        System.assert(r.whereClause.contains('userId__c IN :userIds'));
        System.assert(r.whereClause.contains('model__c IN :models'));
        System.assert(r.whereClause.contains('feature__c IN :features'));
        System.assert(r.whereClause.contains('provider__c IN :providers'));
        System.assert(r.whereClause.contains('appType__c IN :appTypes'));
        System.assert(r.whereClause.contains('promptTemplateDevName__c IN :promptTemplateDevNames'));
        System.assertEquals(8, r.binds.size(), 'Expect date + 6 dimensions');
    }

    @IsTest
    static void build_emptyAndBlankListsSkipped() {
        FilterCriteria c = new FilterCriteria(START_DT, END_DT);
        c.models = new List<String>{ '', '   ', null };
        c.features = new List<String>();
        FilterQueryBuilder.Result r = FilterQueryBuilder.build(c);
        System.assert(!r.whereClause.contains('model__c'), 'Blank-only list must not produce a clause');
        System.assert(!r.whereClause.contains('feature__c'), 'Empty list must not produce a clause');
        System.assertEquals(2, r.binds.size(), 'Only date binds should remain');
    }

    @IsTest
    static void build_injectionValuesAreBoundNotConcatenated() {
        // Safety check: even "dangerous" strings ride as bind values, so the
        // SOQL string never contains the value itself.
        FilterCriteria c = new FilterCriteria(START_DT, END_DT);
        String nasty = '\' OR 1=1 --';
        c.models = new List<String>{ nasty };
        FilterQueryBuilder.Result r = FilterQueryBuilder.build(c);
        System.assert(!r.whereClause.contains(nasty), 'Caller value leaked into SOQL string');
        Set<String> bound = (Set<String>) r.binds.get('models');
        System.assert(bound.contains(nasty), 'Value must be present in binds map');
    }
}
