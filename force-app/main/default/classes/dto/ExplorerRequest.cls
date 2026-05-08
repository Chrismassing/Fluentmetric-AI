/**
 * Parameters for the dynamic Explorer pivot.
 * groupBy:  one of User, PromptTemplate, Feature, Model, Day, Week
 * metric:   one of RequestCount, UniqueUsers, TotalTokens, AcceptanceRate, ToxicFlagCount, TotalCost
 * criteria: multi-dimension filter bag (user/prompt/model/provider/feature/appType)
 * filters:  legacy single-value map kept for `feedbackValue` (GenAIFeedback join) —
 *           dimension filters should move to `criteria`.
 */
public with sharing class ExplorerRequest {
    @AuraEnabled
    public DateTime startDate;
    @AuraEnabled
    public DateTime endDate;
    @AuraEnabled
    public String groupBy;
    @AuraEnabled
    public String metric;
    @AuraEnabled
    public FilterCriteria criteria;
    @AuraEnabled
    public Map<String, String> filters;
    @AuraEnabled
    public Integer resultLimit;

    public ExplorerRequest() {
        this.filters = new Map<String, String>();
        this.resultLimit = 25;
    }
}
