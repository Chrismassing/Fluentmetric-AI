/**
 * Unified filter bag for the detailed request view / Explorer.
 *
 * Every field is optional; `null` or an empty list means "no filter on this
 * dimension". The date range is always required downstream — validation
 * happens in AiInsightsService, not here, so test code can build partial
 * criteria without fighting constructor rules.
 *
 * All list values flow into bind variables via FilterQueryBuilder — values
 * are never concatenated into the SOQL string.
 */
public with sharing class FilterCriteria {
    @AuraEnabled
    public DateTime startDate;
    @AuraEnabled
    public DateTime endDate;
    @AuraEnabled
    public List<String> userIds;
    @AuraEnabled
    public List<String> promptTemplateDevNames;
    @AuraEnabled
    public List<String> models;
    @AuraEnabled
    public List<String> providers;
    @AuraEnabled
    public List<String> features;
    @AuraEnabled
    public List<String> appTypes;

    public FilterCriteria() {
    }

    public FilterCriteria(DateTime startDate, DateTime endDate) {
        this.startDate = startDate;
        this.endDate = endDate;
    }

    public Boolean hasAnyDimensionFilter() {
        return !isEmpty(userIds) ||
            !isEmpty(promptTemplateDevNames) ||
            !isEmpty(models) ||
            !isEmpty(providers) ||
            !isEmpty(features) ||
            !isEmpty(appTypes);
    }

    private static Boolean isEmpty(List<String> vals) {
        return vals == null || vals.isEmpty();
    }
}
