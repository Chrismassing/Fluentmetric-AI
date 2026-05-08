/**
 * Data access contract for the Einstein Generative AI Audit & Feedback DMOs.
 *
 * All methods return raw `SObject` lists — the Service layer is responsible for
 * aggregation, grouping, and name resolution. This keeps DMO SOQL quirks
 * isolated to the DAO, and allows a mock implementation for unit tests where
 * live DMO data is not available.
 *
 * Field and object names in the live schema are in camelCase (e.g.
 * `userId__c`, `timestamp__c`) and differ from Salesforce's help docs — see
 * Documents/LIVE-SCHEMA.md for the verified reference.
 */
public interface IAiInsightsDAO {
    List<SObject> getRequestsByDateRange(DateTime startDate, DateTime endDate);
    List<SObject> getRequestsByUser(String userId, DateTime startDate, DateTime endDate);
    List<SObject> getRequestsByPromptTemplate(String promptDevName, DateTime startDate, DateTime endDate);

    /**
     * Narrow "recent N" raw-row pulls for the entity-details drill-in. All
     * four variants ORDER BY timestamp__c DESC and accept a caller-supplied
     * `limitCount` capped internally at 500 — drill-ins are bounded by design,
     * so we never need a wider window for these.
     */
    List<SObject> getRecentRequestsByUser(String userId, DateTime startDate, DateTime endDate, Integer limitCount);
    List<SObject> getRecentRequestsByPromptTemplate(
        String promptDevName,
        DateTime startDate,
        DateTime endDate,
        Integer limitCount
    );
    List<SObject> getRequestsByModel(String model, DateTime startDate, DateTime endDate, Integer limitCount);
    List<SObject> getRequestsByFeature(String feature, DateTime startDate, DateTime endDate, Integer limitCount);

    /**
     * Criteria-aware recent-request pull for the entity drill-in modal.
     * Applies the full FilterCriteria (date range + dimension filters) plus
     * an entity-anchor clause (e.g. `userId__c = :entityVal`). The anchor
     * field and value are passed as plain Strings; the field name must be a
     * known safe value supplied by the service, never caller-provided input.
     */
    List<SObject> getRecentRequestsWithCriteria(
        FilterCriteria criteria,
        String anchorField,
        String anchorValue,
        Integer limitCount
    );

    List<SObject> getRequestTags(Set<String> requestIds);
    List<SObject> getResponsesForRequests(Set<String> requestIds);
    List<SObject> getGenerationsForResponses(Set<String> responseIds);
    List<SObject> getFeedbackForGenerations(Set<String> generationIds);
    List<SObject> getFeedbackForDateRange(DateTime startDate, DateTime endDate);
    List<SObject> getContentQualityForGenerations(Set<String> generationIds);
    List<SObject> getContentCategories(Set<String> contentQualityIds);
    Integer countRequestsByDateRange(DateTime startDate, DateTime endDate);

    /**
     * Aggregate methods — return pre-grouped rows so the service does not
     * have to pull millions of raw rows into heap for counts/sums. DMO SOQL
     * supports COUNT, SUM, MIN, MAX and multi-column GROUP BY; it does NOT
     * support ORDER BY on aggregate expressions (sort in Apex instead).
     *
     * Each row in the returned AggregateResult lists contains the group-by
     * columns plus aliased aggregates: `cnt`, `pt` (prompt tokens),
     * `ct` (completion tokens), `tt` (total tokens), `minTs`, `maxTs`.
     */
    List<AggregateResult> getRequestAggregatesByUser(DateTime startDate, DateTime endDate);
    List<AggregateResult> getRequestAggregatesByPrompt(DateTime startDate, DateTime endDate);
    List<AggregateResult> getRequestAggregatesByModel(DateTime startDate, DateTime endDate);
    List<AggregateResult> getRequestAggregatesByFeature(DateTime startDate, DateTime endDate);
    List<AggregateResult> getRequestAggregatesByUserAndPrompt(DateTime startDate, DateTime endDate);
    List<AggregateResult> getRequestAggregatesByUserAndModel(DateTime startDate, DateTime endDate);
    List<AggregateResult> getRequestAggregatesByUserAndFeature(DateTime startDate, DateTime endDate);
    AggregateResult getRequestTotals(DateTime startDate, DateTime endDate);
    Integer countDistinctUsers(DateTime startDate, DateTime endDate);
    Integer countDistinctPromptTemplates(DateTime startDate, DateTime endDate);

    /**
     * Count of generations in the date range (used by the Safety dashboard
     * denominator without pulling all request → response → generation chains
     * into heap).
     */
    Integer countGenerationsByDateRange(DateTime startDate, DateTime endDate);

    /**
     * Toxic flag count from the Quality DMO, filtered directly by its own
     * `timestamp__c` and `isToxicityDetected__c = 'true'`. Bounded and fast —
     * the safety chain (Request → Response → Generation → Quality) is
     * prohibitively expensive on busy orgs.
     */
    Integer countToxicFlagsByDateRange(DateTime startDate, DateTime endDate);

    /**
     * STDM (Session Trace Data Model) access for Agentforce Action pricing.
     *
     * These methods query the `ssot__AiAgentInteractionStep__dlm` DMO, which
     * records individual steps within an Agentforce session. Action steps
     * (`ssot__AiAgentInteractionStepType__c = 'ACTION_STEP'`) are the billable
     * unit that Salesforce charges at a flat 20 Flex Credits regardless of
     * token consumption — the raw `GenAIGatewayRequest__dlm` DMO cannot
     * distinguish these from LLM-planner steps.
     *
     * When STDM isn't deployed in an org, `isStdmAvailable()` returns false and
     * callers must treat Agentforce-origin rows as `NOT_COSTED`.
     */
    Boolean isStdmAvailable(DateTime startDate, DateTime endDate);
    Integer countAgentforceActionsByDateRange(DateTime startDate, DateTime endDate);
    List<AggregateResult> getAgentforceActionAggregatesByName(DateTime startDate, DateTime endDate);
    List<SObject> getAgentforceActionSteps(DateTime startDate, DateTime endDate, Integer limitCount);

    /**
     * Timestamp stream for day-granularity bucketing. Returns minimal
     * `timestamp__c` + `totalTokens__c` rows for the range; the service
     * buckets them into days locally because DMO SOQL does not reliably
     * support DATE_TRUNC/GROUP BY DAY(timestamp__c).
     *
     * Caller must date-bound the request. A 50k row cap applies — on very
     * busy orgs the service MUST bucket per-day server-side counts via
     * `countRequestsByDateRange` over narrower sub-windows instead.
     */
    List<SObject> getRequestTimestampsAndTokens(DateTime startDate, DateTime endDate);

    /**
     * Timestamp stream for toxic flags used by the safety heatmap / sparkline.
     * Bounded at 10k — only flagged rows are returned, so volume is small.
     */
    List<SObject> getToxicFlagTimestamps(DateTime startDate, DateTime endDate);

    /**
     * Facet discovery for the filter rail: returns distinct non-null values of
     * a single `GenAIGatewayRequest__dlm` field within the date window along
     * with a count of rows per value. Each AggregateResult has two aliases:
     * `gkey` (the raw value) and `cnt` (Integer/Long count).
     *
     * `fieldName` must be one of a whitelisted set of camelCase field names —
     * the DAO validates the list to keep the dynamic SOQL safe. Aggregate
     * sorting happens in the service layer because DMO SOQL rejects
     * `ORDER BY COUNT(Id)`.
     */
    List<AggregateResult> getDistinctFieldValues(String fieldName, DateTime startDate, DateTime endDate);

    /**
     * Distinct userId__c values observed in the date window, with per-user
     * request counts. Caller resolves ids → display names. Bounded at the
     * DMO aggregate row cap; callers typically sort + slice in Apex.
     */
    List<AggregateResult> getDistinctUserAggregates(DateTime startDate, DateTime endDate);

    /**
     * Criteria-aware single-entity aggregate for the drill-in modal header.
     * Returns one AggregateResult with aliases cnt, pt, ct, tt, minTs, maxTs —
     * same shape as the per-dimension aggregate methods — but scoped to a
     * specific entity anchor (e.g. userId__c = 'someId') AND the active
     * FilterCriteria dimension filters (models, features, etc.). Used when the
     * user has dimension filters active so the KPI header reflects the
     * filtered subset rather than the full entity aggregate.
     *
     * Returns null when no rows match.
     */
    AggregateResult getRequestAggregateForEntity(FilterCriteria criteria, String anchorField, String anchorValue);

    /**
     * Criteria-aware related-entity unique-count helper. Groups rows matching
     * the anchor (e.g. userId__c = 'someId') + FilterCriteria by `groupByField`
     * (e.g. promptTemplateDevName__c) so the caller can count distinct values.
     * Each AggregateResult has aliases gkey (the groupByField value) and cnt.
     *
     * Used when dimension filters are active to count, e.g., how many distinct
     * prompt templates a user used within the filtered subset.
     */
    List<AggregateResult> getRelatedEntityAggregates(
        FilterCriteria criteria,
        String anchorField,
        String anchorValue,
        String groupByField
    );
}
