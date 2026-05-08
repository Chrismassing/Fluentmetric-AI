/**
 * Live DAO implementation. Queries Data Cloud DMOs using dynamic SOQL via
 * `Database.queryWithBinds`.
 *
 * Schema rules (verified against cvk-dev 2026-04-29):
 *   - DMO object names end in `__dlm`, field names are camelCase ending in `__c`
 *   - Date filtering uses `timestamp__c`, NOT `CreatedDate__c`
 *   - Joins use business-key strings (gatewayRequestId, generationId), NOT
 *     auto-generated relationship fields
 *   - Parent-child SOQL subqueries are not supported — do the join in Apex
 *   - `ORDER BY COUNT(...)` is rejected — aggregate sorting happens in Apex
 *   - `userId__c` may hold the sentinel `"NOT_SET"` for system calls
 *
 * All queries are bounded by a mandatory date range to stay well below
 * the 50k-row SOQL governor limit on typical analytics ranges.
 */
public with sharing class AiInsightsDAO implements IAiInsightsDAO {
    private static final String REQUEST_FIELDS =
        'Id, gatewayRequestId__c, userId__c, orgId__c, prompt__c, maskedPrompt__c, ' +
        'model__c, provider__c, feature__c, appType__c, promptTemplateDevName__c, ' +
        'promptTemplateVersionNo__c, timestamp__c, promptTokens__c, completionTokens__c, ' +
        'totalTokens__c, numGenerations__c, sessionId__c, botVersionId__c';

    public List<SObject> getRequestsByDateRange(DateTime startDate, DateTime endDate) {
        String soql =
            'SELECT ' +
            REQUEST_FIELDS +
            ' ' +
            'FROM GenAIGatewayRequest__dlm ' +
            'WHERE timestamp__c >= :startDate AND timestamp__c <= :endDate ' +
            'ORDER BY timestamp__c DESC ' +
            'LIMIT 50000';
        return Database.queryWithBinds(
            soql,
            new Map<String, Object>{ 'startDate' => startDate, 'endDate' => endDate },
            AccessLevel.USER_MODE
        );
    }

    public List<SObject> getRequestsByUser(String userId, DateTime startDate, DateTime endDate) {
        String soql =
            'SELECT ' +
            REQUEST_FIELDS +
            ' ' +
            'FROM GenAIGatewayRequest__dlm ' +
            'WHERE userId__c = :userId ' +
            'AND timestamp__c >= :startDate AND timestamp__c <= :endDate ' +
            'ORDER BY timestamp__c DESC ' +
            'LIMIT 10000';
        return Database.queryWithBinds(
            soql,
            new Map<String, Object>{ 'userId' => userId, 'startDate' => startDate, 'endDate' => endDate },
            AccessLevel.USER_MODE
        );
    }

    public List<SObject> getRequestsByPromptTemplate(String promptDevName, DateTime startDate, DateTime endDate) {
        String soql =
            'SELECT ' +
            REQUEST_FIELDS +
            ' ' +
            'FROM GenAIGatewayRequest__dlm ' +
            'WHERE promptTemplateDevName__c = :promptDevName ' +
            'AND timestamp__c >= :startDate AND timestamp__c <= :endDate ' +
            'ORDER BY timestamp__c DESC ' +
            'LIMIT 10000';
        return Database.queryWithBinds(
            soql,
            new Map<String, Object>{ 'promptDevName' => promptDevName, 'startDate' => startDate, 'endDate' => endDate },
            AccessLevel.USER_MODE
        );
    }

    /**
     * Narrow "recent N" pulls used by the entity-details drill-in service.
     * Each capped internally at 500 rows (drill-ins are by design small) and
     * ordered `timestamp__c DESC` so the caller sees the most recent rows first.
     */
    private static Integer boundedLimit(Integer requested) {
        if (requested == null || requested <= 0) {
            return 500;
        }
        return requested > 500 ? 500 : requested;
    }

    public List<SObject> getRecentRequestsByUser(
        String userId,
        DateTime startDate,
        DateTime endDate,
        Integer limitCount
    ) {
        Integer effectiveLimit = boundedLimit(limitCount);
        String soql =
            'SELECT ' +
            REQUEST_FIELDS +
            ' ' +
            'FROM GenAIGatewayRequest__dlm ' +
            'WHERE userId__c = :userId ' +
            'AND timestamp__c >= :startDate AND timestamp__c <= :endDate ' +
            'ORDER BY timestamp__c DESC ' +
            'LIMIT :effectiveLimit';
        return Database.queryWithBinds(
            soql,
            new Map<String, Object>{
                'userId' => userId,
                'startDate' => startDate,
                'endDate' => endDate,
                'effectiveLimit' => effectiveLimit
            },
            AccessLevel.USER_MODE
        );
    }

    public List<SObject> getRecentRequestsByPromptTemplate(
        String promptDevName,
        DateTime startDate,
        DateTime endDate,
        Integer limitCount
    ) {
        Integer effectiveLimit = boundedLimit(limitCount);
        String soql =
            'SELECT ' +
            REQUEST_FIELDS +
            ' ' +
            'FROM GenAIGatewayRequest__dlm ' +
            'WHERE promptTemplateDevName__c = :promptDevName ' +
            'AND timestamp__c >= :startDate AND timestamp__c <= :endDate ' +
            'ORDER BY timestamp__c DESC ' +
            'LIMIT :effectiveLimit';
        return Database.queryWithBinds(
            soql,
            new Map<String, Object>{
                'promptDevName' => promptDevName,
                'startDate' => startDate,
                'endDate' => endDate,
                'effectiveLimit' => effectiveLimit
            },
            AccessLevel.USER_MODE
        );
    }

    public List<SObject> getRequestsByModel(String model, DateTime startDate, DateTime endDate, Integer limitCount) {
        Integer effectiveLimit = boundedLimit(limitCount);
        String soql =
            'SELECT ' +
            REQUEST_FIELDS +
            ' ' +
            'FROM GenAIGatewayRequest__dlm ' +
            'WHERE model__c = :model ' +
            'AND timestamp__c >= :startDate AND timestamp__c <= :endDate ' +
            'ORDER BY timestamp__c DESC ' +
            'LIMIT :effectiveLimit';
        return Database.queryWithBinds(
            soql,
            new Map<String, Object>{
                'model' => model,
                'startDate' => startDate,
                'endDate' => endDate,
                'effectiveLimit' => effectiveLimit
            },
            AccessLevel.USER_MODE
        );
    }

    public List<SObject> getRequestsByFeature(
        String feature,
        DateTime startDate,
        DateTime endDate,
        Integer limitCount
    ) {
        Integer effectiveLimit = boundedLimit(limitCount);
        String soql =
            'SELECT ' +
            REQUEST_FIELDS +
            ' ' +
            'FROM GenAIGatewayRequest__dlm ' +
            'WHERE feature__c = :feature ' +
            'AND timestamp__c >= :startDate AND timestamp__c <= :endDate ' +
            'ORDER BY timestamp__c DESC ' +
            'LIMIT :effectiveLimit';
        return Database.queryWithBinds(
            soql,
            new Map<String, Object>{
                'feature' => feature,
                'startDate' => startDate,
                'endDate' => endDate,
                'effectiveLimit' => effectiveLimit
            },
            AccessLevel.USER_MODE
        );
    }

    public List<SObject> getRecentRequestsWithCriteria(
        FilterCriteria criteria,
        String anchorField,
        String anchorValue,
        Integer limitCount
    ) {
        Integer effectiveLimit = boundedLimit(limitCount);
        FilterQueryBuilder.Result fq = FilterQueryBuilder.build(criteria);
        // Prepend the entity anchor to the criteria WHERE clause. The anchor
        // field is a known constant passed by the service (e.g. 'userId__c'),
        // never raw user input, so string concatenation here is safe.
        String whereClause = anchorField + ' = :anchorVal AND ' + fq.whereClause;
        String soql =
            'SELECT ' +
            REQUEST_FIELDS +
            ' FROM GenAIGatewayRequest__dlm' +
            ' WHERE ' +
            whereClause +
            ' ORDER BY timestamp__c DESC' +
            ' LIMIT :effectiveLimit';
        Map<String, Object> binds = new Map<String, Object>(fq.binds);
        binds.put('anchorVal', anchorValue);
        binds.put('effectiveLimit', effectiveLimit);
        return Database.queryWithBinds(soql, binds, AccessLevel.USER_MODE);
    }

    public List<SObject> getRequestTags(Set<String> requestIds) {
        if (requestIds == null || requestIds.isEmpty()) {
            return new List<SObject>();
        }
        String soql =
            'SELECT Id, parent__c, tag__c, tagValue__c, timestamp__c ' +
            'FROM GenAIGatewayRequestTag__dlm ' +
            'WHERE parent__c IN :requestIds ' +
            'LIMIT 50000';
        return Database.queryWithBinds(
            soql,
            new Map<String, Object>{ 'requestIds' => requestIds },
            AccessLevel.USER_MODE
        );
    }

    public List<SObject> getResponsesForRequests(Set<String> requestIds) {
        if (requestIds == null || requestIds.isEmpty()) {
            return new List<SObject>();
        }
        String soql =
            'SELECT Id, generationRequestId__c, generationResponseId__c, timestamp__c ' +
            'FROM GenAIGatewayResponse__dlm ' +
            'WHERE generationRequestId__c IN :requestIds ' +
            'LIMIT 50000';
        return Database.queryWithBinds(
            soql,
            new Map<String, Object>{ 'requestIds' => requestIds },
            AccessLevel.USER_MODE
        );
    }

    public List<SObject> getGenerationsForResponses(Set<String> responseIds) {
        if (responseIds == null || responseIds.isEmpty()) {
            return new List<SObject>();
        }
        String soql =
            'SELECT Id, generationId__c, generationResponseId__c, responseText__c, ' +
            'maskedResponseText__c, feature__c, timestamp__c ' +
            'FROM GenAIGeneration__dlm ' +
            'WHERE generationResponseId__c IN :responseIds ' +
            'LIMIT 50000';
        return Database.queryWithBinds(
            soql,
            new Map<String, Object>{ 'responseIds' => responseIds },
            AccessLevel.USER_MODE
        );
    }

    public List<SObject> getFeedbackForGenerations(Set<String> generationIds) {
        if (generationIds == null || generationIds.isEmpty()) {
            return new List<SObject>();
        }
        String soql =
            'SELECT Id, feedbackId__c, generationId__c, userId__c, feedback__c, ' +
            'action__c, source__c, feature__c, appType__c, timestamp__c ' +
            'FROM GenAIFeedback__dlm ' +
            'WHERE generationId__c IN :generationIds ' +
            'LIMIT 50000';
        return Database.queryWithBinds(
            soql,
            new Map<String, Object>{ 'generationIds' => generationIds },
            AccessLevel.USER_MODE
        );
    }

    public List<SObject> getFeedbackForDateRange(DateTime startDate, DateTime endDate) {
        String soql =
            'SELECT Id, feedbackId__c, generationId__c, userId__c, feedback__c, ' +
            'action__c, source__c, feature__c, appType__c, timestamp__c ' +
            'FROM GenAIFeedback__dlm ' +
            'WHERE timestamp__c >= :startDate AND timestamp__c <= :endDate ' +
            'LIMIT 50000';
        return Database.queryWithBinds(
            soql,
            new Map<String, Object>{ 'startDate' => startDate, 'endDate' => endDate },
            AccessLevel.USER_MODE
        );
    }

    public List<SObject> getContentQualityForGenerations(Set<String> generationIds) {
        if (generationIds == null || generationIds.isEmpty()) {
            return new List<SObject>();
        }
        String soql =
            'SELECT Id, id__c, parent__c, isToxicityDetected__c, contentType__c, ' +
            'feature__c, timestamp__c ' +
            'FROM GenAIContentQuality__dlm ' +
            'WHERE parent__c IN :generationIds ' +
            'LIMIT 50000';
        return Database.queryWithBinds(
            soql,
            new Map<String, Object>{ 'generationIds' => generationIds },
            AccessLevel.USER_MODE
        );
    }

    public List<SObject> getContentCategories(Set<String> contentQualityIds) {
        if (contentQualityIds == null || contentQualityIds.isEmpty()) {
            return new List<SObject>();
        }
        String soql =
            'SELECT Id, id__c, parent__c, category__c, value__c, detectorType__c, timestamp__c ' +
            'FROM GenAIContentCategory__dlm ' +
            'WHERE parent__c IN :contentQualityIds ' +
            'LIMIT 50000';
        return Database.queryWithBinds(
            soql,
            new Map<String, Object>{ 'contentQualityIds' => contentQualityIds },
            AccessLevel.USER_MODE
        );
    }

    public Integer countRequestsByDateRange(DateTime startDate, DateTime endDate) {
        String soql =
            'SELECT COUNT() ' +
            'FROM GenAIGatewayRequest__dlm ' +
            'WHERE timestamp__c >= :startDate AND timestamp__c <= :endDate';
        return Database.countQueryWithBinds(
            soql,
            new Map<String, Object>{ 'startDate' => startDate, 'endDate' => endDate },
            AccessLevel.USER_MODE
        );
    }

    // ─────────────────── Aggregate queries (scale-safe) ───────────────────
    //
    // DMOs can aggregate server-side. These methods fetch dozens-to-hundreds
    // of grouped rows instead of potentially millions of raw rows, avoiding
    // the 50k SOQL "too many rows for direct assignment" limit on busy orgs.
    // Common alias shape on the returned AggregateResult rows:
    //   cnt (Integer/Long), pt (Double), ct (Double), tt (Double),
    //   minTs (DateTime), maxTs (DateTime)

    public List<AggregateResult> getRequestAggregatesByUser(DateTime startDate, DateTime endDate) {
        String soql =
            'SELECT userId__c gkey, ' +
            'COUNT(Id) cnt, ' +
            'SUM(promptTokens__c) pt, ' +
            'SUM(completionTokens__c) ct, ' +
            'SUM(totalTokens__c) tt, ' +
            'MIN(timestamp__c) minTs, ' +
            'MAX(timestamp__c) maxTs ' +
            'FROM GenAIGatewayRequest__dlm ' +
            'WHERE timestamp__c >= :startDate AND timestamp__c <= :endDate ' +
            'GROUP BY userId__c';
        return (List<AggregateResult>) Database.queryWithBinds(
            soql,
            new Map<String, Object>{ 'startDate' => startDate, 'endDate' => endDate },
            AccessLevel.USER_MODE
        );
    }

    public List<AggregateResult> getRequestAggregatesByPrompt(DateTime startDate, DateTime endDate) {
        String soql =
            'SELECT promptTemplateDevName__c gkey, ' +
            'COUNT(Id) cnt, ' +
            'SUM(promptTokens__c) pt, ' +
            'SUM(completionTokens__c) ct, ' +
            'SUM(totalTokens__c) tt, ' +
            'MIN(timestamp__c) minTs, ' +
            'MAX(timestamp__c) maxTs ' +
            'FROM GenAIGatewayRequest__dlm ' +
            'WHERE timestamp__c >= :startDate AND timestamp__c <= :endDate ' +
            'GROUP BY promptTemplateDevName__c';
        return (List<AggregateResult>) Database.queryWithBinds(
            soql,
            new Map<String, Object>{ 'startDate' => startDate, 'endDate' => endDate },
            AccessLevel.USER_MODE
        );
    }

    public List<AggregateResult> getRequestAggregatesByUserAndPrompt(DateTime startDate, DateTime endDate) {
        String soql =
            'SELECT userId__c uid, promptTemplateDevName__c pdn, COUNT(Id) cnt, SUM(totalTokens__c) tt ' +
            'FROM GenAIGatewayRequest__dlm ' +
            'WHERE timestamp__c >= :startDate AND timestamp__c <= :endDate ' +
            'GROUP BY userId__c, promptTemplateDevName__c';
        return (List<AggregateResult>) Database.queryWithBinds(
            soql,
            new Map<String, Object>{ 'startDate' => startDate, 'endDate' => endDate },
            AccessLevel.USER_MODE
        );
    }

    public AggregateResult getRequestTotals(DateTime startDate, DateTime endDate) {
        // minTs / maxTs are aliased so callers using this for a TimeBucket
        // entity drill-in can populate `firstUsed` / `lastUsed` on the DTO
        // without a second round-trip.
        String soql =
            'SELECT COUNT(Id) cnt, ' +
            'SUM(promptTokens__c) pt, ' +
            'SUM(completionTokens__c) ct, ' +
            'SUM(totalTokens__c) tt, ' +
            'MIN(timestamp__c) minTs, ' +
            'MAX(timestamp__c) maxTs ' +
            'FROM GenAIGatewayRequest__dlm ' +
            'WHERE timestamp__c >= :startDate AND timestamp__c <= :endDate';
        List<AggregateResult> results = (List<AggregateResult>) Database.queryWithBinds(
            soql,
            new Map<String, Object>{ 'startDate' => startDate, 'endDate' => endDate },
            AccessLevel.USER_MODE
        );
        return results.isEmpty() ? null : results[0];
    }

    public Integer countDistinctUsers(DateTime startDate, DateTime endDate) {
        String soql =
            'SELECT userId__c g ' +
            'FROM GenAIGatewayRequest__dlm ' +
            'WHERE timestamp__c >= :startDate AND timestamp__c <= :endDate ' +
            'GROUP BY userId__c';
        List<AggregateResult> rows = (List<AggregateResult>) Database.queryWithBinds(
            soql,
            new Map<String, Object>{ 'startDate' => startDate, 'endDate' => endDate },
            AccessLevel.USER_MODE
        );
        return rows.size();
    }

    public Integer countDistinctPromptTemplates(DateTime startDate, DateTime endDate) {
        String soql =
            'SELECT promptTemplateDevName__c g ' +
            'FROM GenAIGatewayRequest__dlm ' +
            'WHERE timestamp__c >= :startDate AND timestamp__c <= :endDate ' +
            'AND promptTemplateDevName__c != null ' +
            'GROUP BY promptTemplateDevName__c';
        List<AggregateResult> rows = (List<AggregateResult>) Database.queryWithBinds(
            soql,
            new Map<String, Object>{ 'startDate' => startDate, 'endDate' => endDate },
            AccessLevel.USER_MODE
        );
        return rows.size();
    }

    public List<AggregateResult> getRequestAggregatesByModel(DateTime startDate, DateTime endDate) {
        String soql =
            'SELECT model__c gkey, ' +
            'COUNT(Id) cnt, ' +
            'SUM(promptTokens__c) pt, ' +
            'SUM(completionTokens__c) ct, ' +
            'SUM(totalTokens__c) tt, ' +
            'MIN(timestamp__c) minTs, ' +
            'MAX(timestamp__c) maxTs ' +
            'FROM GenAIGatewayRequest__dlm ' +
            'WHERE timestamp__c >= :startDate AND timestamp__c <= :endDate ' +
            'GROUP BY model__c';
        return (List<AggregateResult>) Database.queryWithBinds(
            soql,
            new Map<String, Object>{ 'startDate' => startDate, 'endDate' => endDate },
            AccessLevel.USER_MODE
        );
    }

    public List<AggregateResult> getRequestAggregatesByFeature(DateTime startDate, DateTime endDate) {
        String soql =
            'SELECT feature__c gkey, ' +
            'COUNT(Id) cnt, ' +
            'SUM(promptTokens__c) pt, ' +
            'SUM(completionTokens__c) ct, ' +
            'SUM(totalTokens__c) tt, ' +
            'MIN(timestamp__c) minTs, ' +
            'MAX(timestamp__c) maxTs ' +
            'FROM GenAIGatewayRequest__dlm ' +
            'WHERE timestamp__c >= :startDate AND timestamp__c <= :endDate ' +
            'GROUP BY feature__c';
        return (List<AggregateResult>) Database.queryWithBinds(
            soql,
            new Map<String, Object>{ 'startDate' => startDate, 'endDate' => endDate },
            AccessLevel.USER_MODE
        );
    }

    public List<AggregateResult> getRequestAggregatesByUserAndModel(DateTime startDate, DateTime endDate) {
        // Includes SUM(totalTokens__c) tt because the cost service needs both
        // counts and tokens to compute per-user/per-model cost.
        String soql =
            'SELECT userId__c uid, model__c pdn, COUNT(Id) cnt, SUM(totalTokens__c) tt ' +
            'FROM GenAIGatewayRequest__dlm ' +
            'WHERE timestamp__c >= :startDate AND timestamp__c <= :endDate ' +
            'GROUP BY userId__c, model__c';
        return (List<AggregateResult>) Database.queryWithBinds(
            soql,
            new Map<String, Object>{ 'startDate' => startDate, 'endDate' => endDate },
            AccessLevel.USER_MODE
        );
    }

    public List<AggregateResult> getRequestAggregatesByUserAndFeature(DateTime startDate, DateTime endDate) {
        String soql =
            'SELECT userId__c uid, feature__c pdn, COUNT(Id) cnt, SUM(totalTokens__c) tt ' +
            'FROM GenAIGatewayRequest__dlm ' +
            'WHERE timestamp__c >= :startDate AND timestamp__c <= :endDate ' +
            'GROUP BY userId__c, feature__c';
        return (List<AggregateResult>) Database.queryWithBinds(
            soql,
            new Map<String, Object>{ 'startDate' => startDate, 'endDate' => endDate },
            AccessLevel.USER_MODE
        );
    }

    public Integer countGenerationsByDateRange(DateTime startDate, DateTime endDate) {
        String soql =
            'SELECT COUNT() ' +
            'FROM GenAIGeneration__dlm ' +
            'WHERE timestamp__c >= :startDate AND timestamp__c <= :endDate';
        return Database.countQueryWithBinds(
            soql,
            new Map<String, Object>{ 'startDate' => startDate, 'endDate' => endDate },
            AccessLevel.USER_MODE
        );
    }

    public Integer countToxicFlagsByDateRange(DateTime startDate, DateTime endDate) {
        String soql =
            'SELECT COUNT(Id) cnt ' +
            'FROM GenAIContentQuality__dlm ' +
            'WHERE timestamp__c >= :startDate AND timestamp__c <= :endDate ' +
            'AND isToxicityDetected__c = \'true\'';
        List<AggregateResult> rows = (List<AggregateResult>) Database.queryWithBinds(
            soql,
            new Map<String, Object>{ 'startDate' => startDate, 'endDate' => endDate },
            AccessLevel.USER_MODE
        );
        if (rows.isEmpty()) {
            return 0;
        }
        Object raw = rows[0].get('cnt');
        if (raw == null) {
            return 0;
        }
        if (raw instanceof Integer) {
            return (Integer) raw;
        }
        if (raw instanceof Long) {
            return ((Long) raw).intValue();
        }
        if (raw instanceof Decimal) {
            return ((Decimal) raw).intValue();
        }
        try {
            return Decimal.valueOf(String.valueOf(raw)).intValue();
        } catch (Exception e) {
            return 0;
        }
    }

    // ── STDM (Session Trace Data Model) ────────────────────────────────────
    // Schema verified against cvk-dev 2026-05-05:
    //   ssot__AiAgentInteractionStep__dlm — 1,517 rows; step-level detail
    //     ssot__AiAgentInteractionStepType__c: ACTION_STEP | LLM_STEP | TOPIC_STEP |
    //       TRUST_GUARDRAILS_STEP | SESSION_END | INTERRUPT_STEP
    //     ssot__AiAgentInteractionId__c — join to ssot__AiAgentInteraction__dlm
    //     ssot__StartTimestamp__c / ssot__EndTimestamp__c — date filtering
    //     ssot__Name__c — action name (e.g. 'explain_warning')
    //     ssot__GenAiGatewayRequestId__c — 'NOT_SET' on ACTION_STEPs (no gateway tokens)
    //   ssot__AiAgentInteraction__dlm — 9,787 rows; turn-level
    //     ssot__AiAgentSessionId__c — join to ssot__AiAgentSession__dlm
    //   ssot__AiAgentSession__dlm — 2,277 rows; session-level
    //     ssot__AiAgentChannelType__c — 'PSTN', 'Builder: Voice Preview', etc.

    /**
     * Lightweight probe: try to COUNT one ACTION_STEP row in the date range.
     * Returns false on any error (DMO missing, permission denied, etc.) so
     * callers can safely fall back to NOT_COSTED for Agentforce rows.
     */
    public Boolean isStdmAvailable(DateTime startDate, DateTime endDate) {
        try {
            String soql =
                'SELECT COUNT() ' +
                'FROM ssot__AiAgentInteractionStep__dlm ' +
                'WHERE ssot__StartTimestamp__c >= :startDate ' +
                'AND ssot__StartTimestamp__c <= :endDate ' +
                'AND ssot__AiAgentInteractionStepType__c = \'ACTION_STEP\' ' +
                'LIMIT 1';
            Integer n = Database.countQueryWithBinds(
                soql,
                new Map<String, Object>{ 'startDate' => startDate, 'endDate' => endDate },
                AccessLevel.USER_MODE
            );
            return n >= 0;
        } catch (Exception e) {
            return false;
        }
    }

    /**
     * Count of ACTION_STEP rows in the date range. Used by the cost overview.
     */
    public Integer countAgentforceActionsByDateRange(DateTime startDate, DateTime endDate) {
        try {
            String soql =
                'SELECT COUNT() ' +
                'FROM ssot__AiAgentInteractionStep__dlm ' +
                'WHERE ssot__StartTimestamp__c >= :startDate ' +
                'AND ssot__StartTimestamp__c <= :endDate ' +
                'AND ssot__AiAgentInteractionStepType__c = \'ACTION_STEP\'';
            return Database.countQueryWithBinds(
                soql,
                new Map<String, Object>{ 'startDate' => startDate, 'endDate' => endDate },
                AccessLevel.USER_MODE
            );
        } catch (Exception e) {
            return 0;
        }
    }

    /**
     * Group ACTION_STEP rows by action name so the UI can show a per-action
     * breakdown. Each AggregateResult has: `actionName` (ssot__Name__c),
     * `cnt` (invocation count).
     */
    public List<AggregateResult> getAgentforceActionAggregatesByName(DateTime startDate, DateTime endDate) {
        try {
            String soql =
                'SELECT ssot__Name__c actionName, COUNT(ssot__Id__c) cnt ' +
                'FROM ssot__AiAgentInteractionStep__dlm ' +
                'WHERE ssot__StartTimestamp__c >= :startDate ' +
                'AND ssot__StartTimestamp__c <= :endDate ' +
                'AND ssot__AiAgentInteractionStepType__c = \'ACTION_STEP\' ' +
                'GROUP BY ssot__Name__c';
            return (List<AggregateResult>) Database.queryWithBinds(
                soql,
                new Map<String, Object>{ 'startDate' => startDate, 'endDate' => endDate },
                AccessLevel.USER_MODE
            );
        } catch (Exception e) {
            return new List<AggregateResult>();
        }
    }

    /**
     * Minimal timestamp + token projection for day-bucket sparklines.
     *
     * Returns only `timestamp__c` and `totalTokens__c` to keep heap small even
     * at the 50k row cap. The service buckets these into per-day totals in
     * Apex because DMO SOQL does not reliably support DAY(timestamp__c) or
     * DATE_TRUNC in GROUP BY across namespaces.
     *
     * On a 30-day range with ~40 requests/day this returns ~1,200 rows — well
     * under the governor ceiling. Very busy orgs may saturate; the service
     * detects that and falls back to bucketed COUNT queries.
     */
    public List<SObject> getRequestTimestampsAndTokens(DateTime startDate, DateTime endDate) {
        String soql =
            'SELECT timestamp__c, totalTokens__c ' +
            'FROM GenAIGatewayRequest__dlm ' +
            'WHERE timestamp__c >= :startDate AND timestamp__c <= :endDate ' +
            'ORDER BY timestamp__c ASC ' +
            'LIMIT 50000';
        return Database.queryWithBinds(
            soql,
            new Map<String, Object>{ 'startDate' => startDate, 'endDate' => endDate },
            AccessLevel.USER_MODE
        );
    }

    // ── Facet discovery ────────────────────────────────────────────────────
    // Used by the filter rail — one lightweight aggregate per dimension,
    // returns { gkey, cnt } rows. DMO SOQL can't ORDER BY COUNT(Id), so the
    // caller sorts + slices in Apex. The field name is whitelisted because we
    // interpolate it into the SOQL (value binds wouldn't work for a column
    // name) — anything outside the allowlist is rejected before query time.
    @TestVisible
    private static final Set<String> FACET_ALLOWED_FIELDS = new Set<String>{
        'model__c',
        'provider__c',
        'feature__c',
        'appType__c',
        'promptTemplateDevName__c'
    };

    public List<AggregateResult> getDistinctFieldValues(String fieldName, DateTime startDate, DateTime endDate) {
        if (!FACET_ALLOWED_FIELDS.contains(fieldName)) {
            throw new IllegalArgumentException('Unsupported facet field: ' + fieldName);
        }
        String soql =
            'SELECT ' +
            fieldName +
            ' gkey, COUNT(Id) cnt ' +
            'FROM GenAIGatewayRequest__dlm ' +
            'WHERE timestamp__c >= :startDate AND timestamp__c <= :endDate ' +
            'AND ' +
            fieldName +
            ' != null ' +
            'GROUP BY ' +
            fieldName;
        return (List<AggregateResult>) Database.queryWithBinds(
            soql,
            new Map<String, Object>{ 'startDate' => startDate, 'endDate' => endDate },
            AccessLevel.USER_MODE
        );
    }

    public List<AggregateResult> getDistinctUserAggregates(DateTime startDate, DateTime endDate) {
        String soql =
            'SELECT userId__c gkey, COUNT(Id) cnt ' +
            'FROM GenAIGatewayRequest__dlm ' +
            'WHERE timestamp__c >= :startDate AND timestamp__c <= :endDate ' +
            'AND userId__c != null ' +
            'GROUP BY userId__c';
        return (List<AggregateResult>) Database.queryWithBinds(
            soql,
            new Map<String, Object>{ 'startDate' => startDate, 'endDate' => endDate },
            AccessLevel.USER_MODE
        );
    }

    /**
     * Flagged-row timestamp stream for safety sparkline + heatmap. Volume is
     * typically tiny (only rows scored toxic by the classifier).
     */
    public List<SObject> getToxicFlagTimestamps(DateTime startDate, DateTime endDate) {
        String soql =
            'SELECT timestamp__c ' +
            'FROM GenAIContentQuality__dlm ' +
            'WHERE timestamp__c >= :startDate AND timestamp__c <= :endDate ' +
            'AND isToxicityDetected__c = \'true\' ' +
            'ORDER BY timestamp__c ASC ' +
            'LIMIT 10000';
        return Database.queryWithBinds(
            soql,
            new Map<String, Object>{ 'startDate' => startDate, 'endDate' => endDate },
            AccessLevel.USER_MODE
        );
    }

    /**
     * Raw ACTION_STEP rows for the drill-in explorer. Bounded at 500.
     * Includes action name, timestamps, and the interaction ID for joining
     * to session/channel data if needed.
     */
    public List<SObject> getAgentforceActionSteps(DateTime startDate, DateTime endDate, Integer limitCount) {
        Integer effectiveLimit = (limitCount == null || limitCount <= 0 || limitCount > 500) ? 500 : limitCount;
        try {
            String soql =
                'SELECT ssot__Id__c, ssot__Name__c, ssot__AiAgentInteractionId__c, ' +
                'ssot__StartTimestamp__c, ssot__EndTimestamp__c, ssot__ErrorMessageText__c ' +
                'FROM ssot__AiAgentInteractionStep__dlm ' +
                'WHERE ssot__StartTimestamp__c >= :startDate ' +
                'AND ssot__StartTimestamp__c <= :endDate ' +
                'AND ssot__AiAgentInteractionStepType__c = \'ACTION_STEP\' ' +
                'ORDER BY ssot__StartTimestamp__c DESC ' +
                'LIMIT :effectiveLimit';
            return Database.queryWithBinds(
                soql,
                new Map<String, Object>{
                    'startDate' => startDate,
                    'endDate' => endDate,
                    'effectiveLimit' => effectiveLimit
                },
                AccessLevel.USER_MODE
            );
        } catch (Exception e) {
            return new List<SObject>();
        }
    }

    /**
     * Criteria-aware single-entity aggregate for the drill-in modal header.
     * Applies FilterCriteria (date range + dimension IN clauses from
     * FilterQueryBuilder) plus an entity anchor (e.g. userId__c = :anchorVal).
     * Returns one AggregateResult with aliases cnt/pt/ct/tt/minTs/maxTs, or
     * null when no rows match. `anchorField` is a safe constant from the
     * service layer, never raw user input.
     */
    public AggregateResult getRequestAggregateForEntity(
        FilterCriteria criteria,
        String anchorField,
        String anchorValue
    ) {
        FilterQueryBuilder.Result fq = FilterQueryBuilder.build(criteria);
        String soql =
            'SELECT COUNT(Id) cnt, SUM(promptTokens__c) pt, SUM(completionTokens__c) ct,' +
            ' SUM(totalTokens__c) tt, MIN(timestamp__c) minTs, MAX(timestamp__c) maxTs' +
            ' FROM GenAIGatewayRequest__dlm' +
            ' WHERE ' +
            anchorField +
            ' = :anchorVal AND ' +
            fq.whereClause;
        Map<String, Object> binds = new Map<String, Object>(fq.binds);
        binds.put('anchorVal', anchorValue);
        List<AggregateResult> rows = (List<AggregateResult>) Database.queryWithBinds(
            soql,
            binds,
            AccessLevel.USER_MODE
        );
        return rows.isEmpty() ? null : rows[0];
    }

    /**
     * Criteria-aware related-entity aggregate for unique-count in the drill-in
     * modal header. Groups rows matching the anchor + FilterCriteria by
     * `groupByField` so the caller can count distinct values (e.g. how many
     * distinct prompt templates a user used in the filtered subset).
     * Each AggregateResult has aliases gkey (groupByField value) and cnt.
     * `anchorField` and `groupByField` are safe constants from the service.
     */
    public List<AggregateResult> getRelatedEntityAggregates(
        FilterCriteria criteria,
        String anchorField,
        String anchorValue,
        String groupByField
    ) {
        FilterQueryBuilder.Result fq = FilterQueryBuilder.build(criteria);
        String soql =
            'SELECT ' +
            groupByField +
            ' gkey, COUNT(Id) cnt' +
            ' FROM GenAIGatewayRequest__dlm' +
            ' WHERE ' +
            anchorField +
            ' = :anchorVal AND ' +
            fq.whereClause +
            ' GROUP BY ' +
            groupByField;
        Map<String, Object> binds = new Map<String, Object>(fq.binds);
        binds.put('anchorVal', anchorValue);
        return (List<AggregateResult>) Database.queryWithBinds(soql, binds, AccessLevel.USER_MODE);
    }
}
