/**
 * Tests for the lightweight Explorer DTOs that ship cross-component filter
 * state (FilterCriteria) and the populated combobox payload (FilterFacetsDTO).
 *
 * Both classes are pure data carriers — these tests exist to lock in the
 * `hasAnyDimensionFilter()` decision matrix and to give the 2GP packager
 * the per-class coverage it needs.
 */
@IsTest
private class FilterCriteriaTest {
    // ───────── FilterCriteria.hasAnyDimensionFilter ──────────────────────

    @IsTest
    static void defaultConstructor_hasNoDimensionFilter() {
        FilterCriteria c = new FilterCriteria();
        Assert.isFalse(c.hasAnyDimensionFilter(), 'all-null lists → no filter');
    }

    @IsTest
    static void dateOnlyConstructor_hasNoDimensionFilter() {
        FilterCriteria c = new FilterCriteria(DateTime.now().addDays(-7), DateTime.now());
        Assert.areNotEqual(null, c.startDate);
        Assert.areNotEqual(null, c.endDate);
        Assert.isFalse(c.hasAnyDimensionFilter(), 'date alone is not a dimension filter');
    }

    @IsTest
    static void emptyLists_haveNoDimensionFilter() {
        FilterCriteria c = new FilterCriteria();
        c.userIds = new List<String>();
        c.promptTemplateDevNames = new List<String>();
        c.models = new List<String>();
        c.providers = new List<String>();
        c.features = new List<String>();
        c.appTypes = new List<String>();
        Assert.isFalse(c.hasAnyDimensionFilter(), 'empty lists are equivalent to null');
    }

    @IsTest
    static void eachDimensionTriggersTrue() {
        // Every list field, exercised individually so the OR chain in
        // hasAnyDimensionFilter() is fully covered.
        FilterCriteria byUser = new FilterCriteria();
        byUser.userIds = new List<String>{ '005000000000001' };
        Assert.isTrue(byUser.hasAnyDimensionFilter(), 'userIds');

        FilterCriteria byPrompt = new FilterCriteria();
        byPrompt.promptTemplateDevNames = new List<String>{ 'P' };
        Assert.isTrue(byPrompt.hasAnyDimensionFilter(), 'promptTemplateDevNames');

        FilterCriteria byModel = new FilterCriteria();
        byModel.models = new List<String>{ 'gpt-4o' };
        Assert.isTrue(byModel.hasAnyDimensionFilter(), 'models');

        FilterCriteria byProvider = new FilterCriteria();
        byProvider.providers = new List<String>{ 'OpenAI' };
        Assert.isTrue(byProvider.hasAnyDimensionFilter(), 'providers');

        FilterCriteria byFeature = new FilterCriteria();
        byFeature.features = new List<String>{ 'plannerservice' };
        Assert.isTrue(byFeature.hasAnyDimensionFilter(), 'features');

        FilterCriteria byApp = new FilterCriteria();
        byApp.appTypes = new List<String>{ 'core' };
        Assert.isTrue(byApp.hasAnyDimensionFilter(), 'appTypes');
    }

    // ───────── FilterFacetsDTO ───────────────────────────────────────────

    @IsTest
    static void filterFacets_defaultConstructor_initializesEmptyLists() {
        FilterFacetsDTO f = new FilterFacetsDTO();
        Assert.areNotEqual(null, f.models);
        Assert.areEqual(0, f.models.size());
        Assert.areEqual(0, f.providers.size());
        Assert.areEqual(0, f.features.size());
        Assert.areEqual(0, f.appTypes.size());
        Assert.areEqual(0, f.promptTemplates.size());
        Assert.areEqual(0, f.topUsers.size());
    }

    @IsTest
    static void facetOption_carriesValueLabelAndCount() {
        FilterFacetsDTO.FacetOption opt = new FilterFacetsDTO.FacetOption('gpt-4o', 'GPT-4o', 42);
        Assert.areEqual('gpt-4o', opt.value);
        Assert.areEqual('GPT-4o', opt.label);
        Assert.areEqual(42, opt.count);
    }

    @IsTest
    static void facetOption_appendsToList() {
        FilterFacetsDTO f = new FilterFacetsDTO();
        f.models.add(new FilterFacetsDTO.FacetOption('gpt-4o', 'GPT-4o', 100));
        f.models.add(new FilterFacetsDTO.FacetOption('claude-sonnet-4', 'Claude Sonnet 4', 12));
        Assert.areEqual(2, f.models.size());
        Assert.areEqual('gpt-4o', f.models[0].value);
        Assert.areEqual(12, f.models[1].count);
    }
}
