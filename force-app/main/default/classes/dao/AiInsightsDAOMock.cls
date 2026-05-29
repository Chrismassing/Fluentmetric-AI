/**
 * Test double for IAiInsightsDAO.
 *
 * DMO data is not available in Apex test context, so service/controller
 * tests inject this mock. Each method returns a pre-seeded list that the
 * test builds with the `queue*` helpers. Unset queues return an empty list —
 * matching live DAO behavior when the DMO has no matching rows.
 *
 * The mock stores records as SObject maps so tests can populate arbitrary
 * camelCase `__c` fields without needing the DMO to exist at compile time.
 */
@IsTest
public class AiInsightsDAOMock implements IAiInsightsDAO {
    public List<SObject> requestsToReturn = new List<SObject>();
    public List<SObject> requestsByUserToReturn = new List<SObject>();
    public List<SObject> requestsByPromptToReturn = new List<SObject>();
    public List<SObject> recentRequestsByUserToReturn = new List<SObject>();
    public List<SObject> recentRequestsByPromptToReturn = new List<SObject>();
    public List<SObject> requestsByModelToReturn = new List<SObject>();
    public List<SObject> requestsByFeatureToReturn = new List<SObject>();
    public List<SObject> requestTagsToReturn = new List<SObject>();
    public List<SObject> responsesToReturn = new List<SObject>();
    public List<SObject> generationsToReturn = new List<SObject>();
    public List<SObject> feedbackByGenerationToReturn = new List<SObject>();
    public List<SObject> feedbackByDateToReturn = new List<SObject>();
    public List<SObject> contentQualityToReturn = new List<SObject>();
    public List<SObject> contentCategoriesToReturn = new List<SObject>();
    public Integer countToReturn = 0;

    public List<SObject> getRequestsByDateRange(DateTime startDate, DateTime endDate) {
        return requestsToReturn;
    }
    public List<SObject> getRequestsByUser(String userId, DateTime startDate, DateTime endDate) {
        return requestsByUserToReturn;
    }
    public List<SObject> getRequestsByPromptTemplate(String promptDevName, DateTime startDate, DateTime endDate) {
        return requestsByPromptToReturn;
    }
    public List<SObject> getRecentRequestsByUser(
        String userId,
        DateTime startDate,
        DateTime endDate,
        Integer limitCount
    ) {
        return recentRequestsByUserToReturn == null || recentRequestsByUserToReturn.isEmpty()
            ? requestsByUserToReturn
            : recentRequestsByUserToReturn;
    }
    public List<SObject> getRecentRequestsByPromptTemplate(
        String promptDevName,
        DateTime startDate,
        DateTime endDate,
        Integer limitCount
    ) {
        return recentRequestsByPromptToReturn == null || recentRequestsByPromptToReturn.isEmpty()
            ? requestsByPromptToReturn
            : recentRequestsByPromptToReturn;
    }
    public List<SObject> getRequestsByModel(String model, DateTime startDate, DateTime endDate, Integer limitCount) {
        return requestsByModelToReturn;
    }
    public List<SObject> getRequestsByFeature(
        String feature,
        DateTime startDate,
        DateTime endDate,
        Integer limitCount
    ) {
        return requestsByFeatureToReturn;
    }
    public List<SObject> getRecentRequestsWithCriteria(
        FilterCriteria criteria,
        String anchorField,
        String anchorValue,
        Integer limitCount
    ) {
        return recentRequestsByUserToReturn;
    }
    public List<SObject> getRequestTags(Set<String> requestIds) {
        return requestTagsToReturn;
    }
    public List<SObject> getResponsesForRequests(Set<String> requestIds) {
        return responsesToReturn;
    }
    public List<SObject> getGenerationsForResponses(Set<String> responseIds) {
        return generationsToReturn;
    }
    public List<SObject> getFeedbackForGenerations(Set<String> generationIds) {
        return feedbackByGenerationToReturn;
    }
    public List<SObject> getFeedbackForDateRange(DateTime startDate, DateTime endDate) {
        return feedbackByDateToReturn;
    }
    public List<SObject> getContentQualityForGenerations(Set<String> generationIds) {
        return contentQualityToReturn;
    }
    public List<SObject> getContentCategories(Set<String> contentQualityIds) {
        return contentCategoriesToReturn;
    }
    public Integer countRequestsByDateRange(DateTime startDate, DateTime endDate) {
        return countToReturn;
    }

    // Aggregate mocks — tests assign these lists directly
    public List<AggregateResult> aggregatesByUserToReturn = new List<AggregateResult>();
    public List<AggregateResult> aggregatesByPromptToReturn = new List<AggregateResult>();
    public List<AggregateResult> aggregatesByModelToReturn = new List<AggregateResult>();
    public List<AggregateResult> aggregatesByFeatureToReturn = new List<AggregateResult>();
    public List<AggregateResult> aggregatesByUserAndPromptToReturn = new List<AggregateResult>();
    public List<AggregateResult> aggregatesByUserAndModelToReturn = new List<AggregateResult>();
    public List<AggregateResult> aggregatesByUserAndFeatureToReturn = new List<AggregateResult>();
    public AggregateResult totalsToReturn;
    public Integer distinctUsersToReturn = 0;
    public Integer distinctPromptsToReturn = 0;
    public Integer generationsCountToReturn = 0;
    public Integer toxicFlagsToReturn = 0;

    public List<AggregateResult> getRequestAggregatesByUser(DateTime startDate, DateTime endDate) {
        return aggregatesByUserToReturn;
    }
    public List<AggregateResult> getRequestAggregatesByPrompt(DateTime startDate, DateTime endDate) {
        return aggregatesByPromptToReturn;
    }
    public List<AggregateResult> getRequestAggregatesByModel(DateTime startDate, DateTime endDate) {
        return aggregatesByModelToReturn;
    }
    public List<AggregateResult> getRequestAggregatesByFeature(DateTime startDate, DateTime endDate) {
        return aggregatesByFeatureToReturn;
    }
    public List<AggregateResult> getRequestAggregatesByUserAndPrompt(DateTime startDate, DateTime endDate) {
        return aggregatesByUserAndPromptToReturn;
    }
    public List<AggregateResult> getRequestAggregatesByUserAndModel(DateTime startDate, DateTime endDate) {
        return aggregatesByUserAndModelToReturn;
    }
    public List<AggregateResult> getRequestAggregatesByUserAndFeature(DateTime startDate, DateTime endDate) {
        return aggregatesByUserAndFeatureToReturn;
    }
    public AggregateResult getRequestTotals(DateTime startDate, DateTime endDate) {
        return totalsToReturn;
    }
    public Integer countDistinctUsers(DateTime startDate, DateTime endDate) {
        return distinctUsersToReturn;
    }
    public Integer countDistinctPromptTemplates(DateTime startDate, DateTime endDate) {
        return distinctPromptsToReturn;
    }
    public Integer countGenerationsByDateRange(DateTime startDate, DateTime endDate) {
        return generationsCountToReturn;
    }
    public Integer countToxicFlagsByDateRange(DateTime startDate, DateTime endDate) {
        return toxicFlagsToReturn;
    }

    // ── STDM mock fields ────────────────────────────────────────────────────
    public Boolean stdmAvailableToReturn = false;
    public Integer agentforceActionCountToReturn = 0;
    public List<AggregateResult> agentforceActionAggregatesByNameToReturn = new List<AggregateResult>();
    public List<SObject> agentforceActionStepsToReturn = new List<SObject>();

    public Boolean isStdmAvailable(DateTime startDate, DateTime endDate) {
        return stdmAvailableToReturn;
    }
    public Integer countAgentforceActionsByDateRange(DateTime startDate, DateTime endDate) {
        return agentforceActionCountToReturn;
    }
    public List<AggregateResult> getAgentforceActionAggregatesByName(DateTime startDate, DateTime endDate) {
        return agentforceActionAggregatesByNameToReturn;
    }
    public List<SObject> getAgentforceActionSteps(DateTime startDate, DateTime endDate, Integer limitCount) {
        return agentforceActionStepsToReturn;
    }

    // ── Daily-bucket / trends mock fields ──────────────────────────────────
    public List<SObject> requestTimestampsToReturn = new List<SObject>();
    public List<SObject> toxicFlagTimestampsToReturn = new List<SObject>();

    public List<SObject> getRequestTimestampsAndTokens(DateTime startDate, DateTime endDate) {
        return requestTimestampsToReturn;
    }
    public List<SObject> getToxicFlagTimestamps(DateTime startDate, DateTime endDate) {
        return toxicFlagTimestampsToReturn;
    }

    // ── Facet discovery mocks ──────────────────────────────────────────────
    // Per-field distinct-value lists. Tests can set the map entry for any
    // whitelisted field (model__c, provider__c, feature__c, appType__c,
    // promptTemplateDevName__c); absent entries return empty lists.
    public Map<String, List<AggregateResult>> distinctValuesByField = new Map<String, List<AggregateResult>>();
    public List<AggregateResult> distinctUsersToReturnList = new List<AggregateResult>();

    public List<AggregateResult> getDistinctFieldValues(String fieldName, DateTime startDate, DateTime endDate) {
        List<AggregateResult> rows = distinctValuesByField.get(fieldName);
        return rows == null ? new List<AggregateResult>() : rows;
    }
    public List<AggregateResult> getDistinctUserAggregates(DateTime startDate, DateTime endDate) {
        return distinctUsersToReturnList;
    }

    public AggregateResult getRequestAggregateForEntity(
        FilterCriteria criteria,
        String anchorField,
        String anchorValue
    ) {
        return null;
    }

    public List<AggregateResult> getRelatedEntityAggregates(
        FilterCriteria criteria,
        String anchorField,
        String anchorValue,
        String groupByField
    ) {
        return new List<AggregateResult>();
    }

    // ── Adoption analytics mocks (Phase 1.3) ───────────────────────────────
    public List<AggregateResult> aggregatesByPromptAndModelToReturn = new List<AggregateResult>();
    public List<SObject> requestTimestampsByUserToReturn = new List<SObject>();
    public Map<String, DateTime> firstObservedByPromptToReturn = new Map<String, DateTime>();
    public Integer distinctUserCountInWindowToReturn = 0;

    public List<AggregateResult> getRequestAggregatesByPromptAndModel(DateTime startDate, DateTime endDate) {
        return aggregatesByPromptAndModelToReturn;
    }

    public List<SObject> getRequestTimestampsByUser(DateTime startDate, DateTime endDate) {
        return requestTimestampsByUserToReturn;
    }

    public DateTime getFirstObservedTimestampByPrompt(String promptDevName) {
        if (String.isBlank(promptDevName) || firstObservedByPromptToReturn == null) {
            return null;
        }
        return firstObservedByPromptToReturn.get(promptDevName);
    }

    public Integer getDistinctUserCountInWindow(DateTime startDate, DateTime endDate) {
        return distinctUserCountInWindowToReturn == null ? 0 : distinctUserCountInWindowToReturn;
    }

    // ── Service-side DMO query absorbers (v1.0.1) ──────────────────────────
    public List<AggregateResult> aggregatesByPromptAndFeatureToReturn = new List<AggregateResult>();
    public List<SObject> contentCategoriesByDateToReturn = new List<SObject>();
    public List<SObject> recentToxicQualityToReturn = new List<SObject>();
    public Map<String, List<SObject>> generationsByIdsToReturn = new Map<String, List<SObject>>();
    public Map<String, List<SObject>> responsesByIdsToReturn = new Map<String, List<SObject>>();
    public Map<String, List<SObject>> requestsByGatewayIdsToReturn = new Map<String, List<SObject>>();
    public List<SObject> generationsByIdsDefault = new List<SObject>();
    public List<SObject> responsesByIdsDefault = new List<SObject>();
    public List<SObject> requestsByGatewayIdsDefault = new List<SObject>();
    public Map<String, List<AggregateResult>> explorerAggregatesByGroupField = new Map<String, List<AggregateResult>>();
    public List<AggregateResult> toxicFlagsByFeatureToReturn = new List<AggregateResult>();

    public List<AggregateResult> getRequestAggregatesByPromptAndFeature(DateTime startDate, DateTime endDate) {
        return aggregatesByPromptAndFeatureToReturn;
    }

    public List<SObject> getContentCategoriesByDate(DateTime startDate, DateTime endDate) {
        return contentCategoriesByDateToReturn;
    }

    public List<SObject> getRecentToxicQuality(DateTime startDate, DateTime endDate, Integer rowLimit) {
        return recentToxicQualityToReturn;
    }

    public List<SObject> getGenerationsByIds(Set<String> genIds) {
        if (generationsByIdsToReturn != null && !generationsByIdsToReturn.isEmpty() && genIds != null) {
            List<SObject> matched = new List<SObject>();
            for (String gid : genIds) {
                List<SObject> rows = generationsByIdsToReturn.get(gid);
                if (rows != null) {
                    matched.addAll(rows);
                }
            }
            if (!matched.isEmpty()) {
                return matched;
            }
        }
        return generationsByIdsDefault;
    }

    public List<SObject> getResponsesByIds(Set<String> responseIds) {
        if (responsesByIdsToReturn != null && !responsesByIdsToReturn.isEmpty() && responseIds != null) {
            List<SObject> matched = new List<SObject>();
            for (String rid : responseIds) {
                List<SObject> rows = responsesByIdsToReturn.get(rid);
                if (rows != null) {
                    matched.addAll(rows);
                }
            }
            if (!matched.isEmpty()) {
                return matched;
            }
        }
        return responsesByIdsDefault;
    }

    public List<SObject> getRequestsByGatewayIds(Set<String> requestIds) {
        if (requestsByGatewayIdsToReturn != null && !requestsByGatewayIdsToReturn.isEmpty() && requestIds != null) {
            List<SObject> matched = new List<SObject>();
            for (String rid : requestIds) {
                List<SObject> rows = requestsByGatewayIdsToReturn.get(rid);
                if (rows != null) {
                    matched.addAll(rows);
                }
            }
            if (!matched.isEmpty()) {
                return matched;
            }
        }
        return requestsByGatewayIdsDefault;
    }

    public List<AggregateResult> getExplorerAggregates(FilterCriteria criteria, String groupField) {
        if (explorerAggregatesByGroupField == null) {
            return new List<AggregateResult>();
        }
        List<AggregateResult> rows = explorerAggregatesByGroupField.get(groupField);
        return rows == null ? new List<AggregateResult>() : rows;
    }

    public List<AggregateResult> getToxicFlagsByFeature(DateTime startDate, DateTime endDate) {
        return toxicFlagsByFeatureToReturn;
    }
}
