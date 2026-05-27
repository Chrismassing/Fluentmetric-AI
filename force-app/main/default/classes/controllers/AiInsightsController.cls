/**
 * Thin @AuraEnabled facade over AiInsightsService for the FluentMetric AI LWCs.
 *
 * Responsibilities:
 *   - Validate inputs (dates, identifiers, group-by keys) before delegating
 *   - Wrap domain exceptions in AuraHandledException with user-friendly messages
 *   - Mark all read methods `cacheable=true` except the two that vary too much
 *     to cache (runExplorerQuery, checkPrerequisites)
 *
 * Business logic lives in AiInsightsService — this layer stays intentionally
 * small so the service can be shared with future surfaces (Agentforce actions,
 * Flow invocable methods) without dragging UI-specific wrapping logic.
 */
public with sharing class AiInsightsController {
    @TestVisible
    private static AiInsightsService serviceOverride;

    private static AiInsightsService service() {
        return serviceOverride == null ? new AiInsightsService() : serviceOverride;
    }

    @AuraEnabled(cacheable=true)
    public static UsageOverviewDTO getOverview(DateTime startDate, DateTime endDate) {
        try {
            DateRangeFilter filter = buildFilter(startDate, endDate);
            return service().getOverview(filter);
        } catch (Exception e) {
            throw wrap(e, 'Unable to load overview metrics');
        }
    }

    /**
     * Side-channel trends payload for the Overview card strip — carries the
     * prior-window KPI values (for ±% delta badges) and per-day sparkline
     * series. Separate endpoint so trend rendering fails independently of the
     * main KPI load and so each response stays comfortably inside the LWC
     * cacheable-return size budget.
     */
    @AuraEnabled(cacheable=true)
    public static OverviewTrendsDTO getOverviewTrends(DateTime startDate, DateTime endDate) {
        try {
            DateRangeFilter filter = buildFilter(startDate, endDate);
            return service().getOverviewTrends(filter);
        } catch (Exception e) {
            throw wrap(e, 'Unable to load overview trends');
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<UserUsageDTO> getUsageByUser(DateTime startDate, DateTime endDate) {
        try {
            DateRangeFilter filter = buildFilter(startDate, endDate);
            return service().getUsageByUser(filter);
        } catch (Exception e) {
            throw wrap(e, 'Unable to load user adoption');
        }
    }

    @AuraEnabled(cacheable=true)
    public static UserUsageDTO getUserDetail(String userId, DateTime startDate, DateTime endDate) {
        try {
            if (String.isBlank(userId)) {
                throw new IllegalArgumentException('userId is required');
            }
            DateRangeFilter filter = buildFilter(startDate, endDate);
            List<UserUsageDTO> all = service().getUsageByUser(filter);
            for (UserUsageDTO dto : all) {
                if (userId.equals(dto.userId)) {
                    return dto;
                }
            }
            return null;
        } catch (Exception e) {
            throw wrap(e, 'Unable to load user detail');
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<PromptUsageDTO> getUsageByPrompt(DateTime startDate, DateTime endDate) {
        try {
            DateRangeFilter filter = buildFilter(startDate, endDate);
            return service().getUsageByPrompt(filter);
        } catch (Exception e) {
            throw wrap(e, 'Unable to load prompt usage');
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<PromptOutputDTO> getPromptOutputs(
        String promptDevName,
        DateTime startDate,
        DateTime endDate,
        Integer limitCount
    ) {
        try {
            if (String.isBlank(promptDevName)) {
                throw new IllegalArgumentException('promptDevName is required');
            }
            DateRangeFilter filter = buildFilter(startDate, endDate);
            return service().getPromptOutputs(promptDevName, filter, limitCount);
        } catch (Exception e) {
            throw wrap(e, 'Unable to load prompt outputs');
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<TokenConsumptionDTO> getTokenConsumption(DateTime startDate, DateTime endDate, String groupBy) {
        try {
            if (String.isBlank(groupBy)) {
                throw new IllegalArgumentException('groupBy is required');
            }
            DateRangeFilter filter = buildFilter(startDate, endDate);
            return service().getTokenConsumption(filter, groupBy);
        } catch (Exception e) {
            throw wrap(e, 'Unable to load token consumption');
        }
    }

    @AuraEnabled(cacheable=true)
    public static ContentSafetyDTO getSafetyOverview(DateTime startDate, DateTime endDate) {
        try {
            DateRangeFilter filter = buildFilter(startDate, endDate);
            return service().getSafetyOverview(filter);
        } catch (Exception e) {
            throw wrap(e, 'Unable to load safety overview');
        }
    }

    /**
     * Run a dynamic Explorer pivot. All parameters are top-level primitives
     * because `@AuraEnabled` LWC marshalling of nested custom DTOs with
     * DateTime fields is fragile — nested DateTime fields get silently
     * dropped, and so does the whole DTO if any field fails. Keeping the
     * wire shape flat sidesteps both problems.
     *
     * `filtersJson` is the legacy single-value map ({ "feedbackValue": "thumbs_down" }).
     * `criteriaJson` is the new multi-dimension filter bag from the filter rail:
     *   { userIds, promptTemplateDevNames, models, providers, features, appTypes }
     * Either or both may arrive; the service merges them. Passing null/blank
     * for either is a no-op.
     */
    @AuraEnabled
    public static List<ExplorerResultDTO> runExplorerQuery(
        DateTime startDate,
        DateTime endDate,
        String groupBy,
        String metric,
        String filtersJson,
        String criteriaJson,
        Integer resultLimit
    ) {
        try {
            ExplorerRequest request = new ExplorerRequest();
            request.startDate = startDate;
            request.endDate = endDate;
            request.groupBy = groupBy;
            request.metric = metric;
            request.resultLimit = (resultLimit == null || resultLimit <= 0) ? 25 : resultLimit;
            request.filters = parseLegacyFilters(filtersJson);
            request.criteria = parseCriteria(criteriaJson, startDate, endDate);
            return service().runExplorer(request);
        } catch (Exception e) {
            throw wrap(e, 'Unable to run Explorer query');
        }
    }

    /**
     * Facet lists for the filter rail. Returns distinct values actually
     * observed in the date window for every dimension, sorted by popularity
     * and length-capped — no dead or stale combobox entries.
     */
    @AuraEnabled(cacheable=true)
    public static FilterFacetsDTO getFilterFacets(DateTime startDate, DateTime endDate, Integer topUserLimit) {
        try {
            DateRangeFilter filter = buildFilter(startDate, endDate);
            return service().getFilterFacets(filter, topUserLimit);
        } catch (Exception e) {
            throw wrap(e, 'Unable to load filter facets');
        }
    }

    /**
     * Typeahead for the user filter. `term` is the user's typed fragment
     * (case-insensitive substring against the resolved display name).
     * Terms under 2 chars return empty — the LWC debounces against that rule.
     */
    @AuraEnabled(cacheable=true)
    public static List<FilterFacetsDTO.FacetOption> searchUsersInRange(
        String term,
        DateTime startDate,
        DateTime endDate,
        Integer maxRows
    ) {
        try {
            DateRangeFilter filter = buildFilter(startDate, endDate);
            return service().searchUsersInRange(term, filter, maxRows);
        } catch (Exception e) {
            throw wrap(e, 'Unable to search users');
        }
    }

    /**
     * Cross-cutting entity drill-in for every dashboard row. `entityType` is
     * one of "User" | "PromptTemplate" | "Model" | "Feature". `entityKey` is
     * the raw identifier used for the drill-in (user Id, quoted prompt dev
     * name, model string, or feature string). `recentLimit` is capped at 20
     * in the service layer to keep the LWC drawer bounded.
     */
    @AuraEnabled(cacheable=true)
    public static EntityDetailsDTO getEntityDetails(
        String entityType,
        String entityKey,
        DateTime startDate,
        DateTime endDate,
        Integer recentLimit,
        String criteriaJson
    ) {
        try {
            if (String.isBlank(entityType)) {
                throw new IllegalArgumentException('entityType is required');
            }
            if (String.isBlank(entityKey)) {
                throw new IllegalArgumentException('entityKey is required');
            }
            DateRangeFilter filter = buildFilter(startDate, endDate);
            FilterCriteria criteria = String.isBlank(criteriaJson)
                ? null
                : parseCriteria(criteriaJson, startDate, endDate);
            if (criteria != null) {
                criteria.startDate = filter.startDate;
                criteria.endDate = filter.endDate;
            }
            return service().getEntityDetails(entityType, entityKey, filter, recentLimit, criteria);
        } catch (Exception e) {
            throw wrap(e, 'Unable to load entity details');
        }
    }

    /**
     * Pivot drill: given a source entity (User/PromptTemplate/Model/Feature),
     * group its requests by another dimension and return the top N rows. This
     * is the workhorse behind the side-sheet drill panel — clicking a User
     * with breakdownBy="PromptTemplate" returns the prompts that user invoked,
     * sorted by RequestCount descending.
     *
     * Implementation is a thin wrapper around runExplorer: the source entity
     * is injected into FilterCriteria as a single-element list, breakdownBy
     * becomes groupBy, and metric defaults to RequestCount (callers can
     * override). resultLimit defaults to 10 to keep the panel scannable.
     *
     * Cacheable=true is safe — the same (entity, breakdown, range) tuple
     * always returns the same answer for a given org snapshot.
     */
    @AuraEnabled(cacheable=true)
    public static List<ExplorerResultDTO> getEntityBreakdown(
        String entityType,
        String entityKey,
        String breakdownBy,
        DateTime startDate,
        DateTime endDate,
        String metric,
        Integer resultLimit,
        String criteriaJson
    ) {
        try {
            if (String.isBlank(entityType)) {
                throw new IllegalArgumentException('entityType is required');
            }
            if (String.isBlank(entityKey)) {
                throw new IllegalArgumentException('entityKey is required');
            }
            if (String.isBlank(breakdownBy)) {
                throw new IllegalArgumentException('breakdownBy is required');
            }
            DateRangeFilter filter = buildFilter(startDate, endDate);

            // Start from any inbound rail criteria (e.g. Explorer pre-filtered
            // by Model + Feature), then layer the source entity on top so the
            // drill stays scoped to the same slice the parent table is showing.
            FilterCriteria criteria = String.isBlank(criteriaJson)
                ? new FilterCriteria(filter.startDate, filter.endDate)
                : parseCriteria(criteriaJson, filter.startDate, filter.endDate);
            criteria.startDate = filter.startDate;
            criteria.endDate = filter.endDate;
            applyEntityToCriteria(criteria, entityType, entityKey);

            ExplorerRequest request = new ExplorerRequest();
            request.startDate = filter.startDate;
            request.endDate = filter.endDate;
            request.groupBy = breakdownBy;
            request.metric = String.isBlank(metric) ? 'RequestCount' : metric;
            request.criteria = criteria;
            request.resultLimit = (resultLimit == null || resultLimit <= 0) ? 10 : resultLimit;

            return service().runExplorer(request);
        } catch (Exception e) {
            throw wrap(e, 'Unable to load entity breakdown');
        }
    }

    /**
     * Inject a single source entity into a FilterCriteria. The mapping mirrors
     * getEntityDetails — the same identifier shape (raw user Id, quoted prompt
     * dev name, model string, feature string) is reused.
     */
    private static void applyEntityToCriteria(FilterCriteria criteria, String entityType, String entityKey) {
        String type = entityType == null ? '' : entityType.trim();
        if ('User'.equalsIgnoreCase(type)) {
            criteria.userIds = new List<String>{ entityKey };
        } else if ('PromptTemplate'.equalsIgnoreCase(type)) {
            criteria.promptTemplateDevNames = new List<String>{ entityKey };
        } else if ('Model'.equalsIgnoreCase(type)) {
            criteria.models = new List<String>{ entityKey };
        } else if ('Feature'.equalsIgnoreCase(type)) {
            criteria.features = new List<String>{ entityKey };
        } else {
            throw new IllegalArgumentException('Unsupported entityType: ' + entityType);
        }
    }

    @AuraEnabled
    public static Map<String, Boolean> checkPrerequisites() {
        try {
            return service().checkPrerequisites();
        } catch (Exception e) {
            throw wrap(e, 'Unable to check prerequisites');
        }
    }

    /**
     * Read the hierarchy custom setting for the live-preview Cost Settings
     * panel. Returned as a plain Map so the LWC doesn't have to bind to the
     * custom-setting type directly.
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getCostSettings() {
        try {
            CostCalculatorService svc = new CostCalculatorService();
            FluentMetric_Cost_Settings__c s = svc.getSettings();
            return new Map<String, Object>{
                'enabled' => svc.isCostMetricsEnabled(),
                'usdPerCredit' => s == null ||
                    s.Flex_Credit_USD_Rate__c == null
                    ? (Decimal) 0.004
                    : s.Flex_Credit_USD_Rate__c,
                'discountPercent' => s == null || s.Discount_Percent__c == null ? (Decimal) 0 : s.Discount_Percent__c,
                'fallbackModel' => s == null || String.isBlank(s.Default_Fallback_Model__c)
                    ? 'Standard-Default'
                    : s.Default_Fallback_Model__c
            };
        } catch (Exception e) {
            throw wrap(e, 'Unable to load cost settings');
        }
    }

    // ───────────────────────── Adoption analytics (Phase 3) ─────────

    /**
     * Adoption denominator snapshot for the dedicated funnel LWC. Returns
     * entitled-population resolution + active vs. entitled match rate. Falls
     * back to "all active org users" when the configured PermissionSets /
     * Profiles can't be resolved.
     */
    @AuraEnabled(cacheable=true)
    public static EntitlementSnapshotDTO getEntitlementSnapshot(DateTime startDate, DateTime endDate) {
        try {
            DateRangeFilter filter = buildFilter(startDate, endDate);
            return service().getEntitlementSnapshot(filter);
        } catch (Exception e) {
            throw wrap(e, 'Unable to load entitlement snapshot');
        }
    }

    /**
     * Cohort retention rollup for the cohort heatmap LWC. Bins users by ISO
     * week of first observed request and returns per-cohort retention
     * series (capped at 26 weeks).
     */
    @AuraEnabled(cacheable=true)
    public static AdoptionCohortsDTO getAdoptionCohorts(DateTime startDate, DateTime endDate) {
        try {
            DateRangeFilter filter = buildFilter(startDate, endDate);
            return service().getAdoptionCohorts(filter);
        } catch (Exception e) {
            throw wrap(e, 'Unable to load adoption cohorts');
        }
    }

    /**
     * Trailing 8-week trend (requests, activeUsers, tokens) plus latest WoW
     * pct deltas for the Overview KPI chips and Activity adoption sparkline.
     */
    @AuraEnabled(cacheable=true)
    public static OrgAdoptionDeltasDTO getOrgAdoptionDeltas(DateTime startDate, DateTime endDate) {
        try {
            DateRangeFilter filter = buildFilter(startDate, endDate);
            return service().getOrgAdoptionDeltas(filter);
        } catch (Exception e) {
            throw wrap(e, 'Unable to load adoption deltas');
        }
    }

    /**
     * Pareto-style power-user segmentation for the Overview Pareto chip and
     * the User Adoption tier badges.
     */
    @AuraEnabled(cacheable=true)
    public static PowerUserSegmentsDTO getPowerUserSegments(DateTime startDate, DateTime endDate) {
        try {
            DateRangeFilter filter = buildFilter(startDate, endDate);
            return service().getPowerUserSegments(filter);
        } catch (Exception e) {
            throw wrap(e, 'Unable to load power user segments');
        }
    }

    /**
     * Per-feature breadth/depth + first-observed timestamps for the Activity
     * tab feature-adoption table.
     */
    @AuraEnabled(cacheable=true)
    public static List<FeatureAdoptionDTO> getFeatureAdoption(DateTime startDate, DateTime endDate) {
        try {
            DateRangeFilter filter = buildFilter(startDate, endDate);
            return service().getFeatureAdoption(filter);
        } catch (Exception e) {
            throw wrap(e, 'Unable to load feature adoption');
        }
    }

    // ───────────────────────── Helpers ───────────────────────────

    private static DateRangeFilter buildFilter(DateTime startDate, DateTime endDate) {
        if (startDate == null || endDate == null) {
            throw new IllegalArgumentException('startDate and endDate are required');
        }
        if (startDate > endDate) {
            throw new IllegalArgumentException('startDate must be on or before endDate');
        }
        return new DateRangeFilter(startDate, endDate);
    }

    private static Map<String, String> parseLegacyFilters(String filtersJson) {
        Map<String, String> out = new Map<String, String>();
        if (String.isBlank(filtersJson)) {
            return out;
        }
        try {
            Map<String, Object> decoded = (Map<String, Object>) JSON.deserializeUntyped(filtersJson);
            for (String key : decoded.keySet()) {
                Object val = decoded.get(key);
                if (val != null) {
                    out.put(key, String.valueOf(val));
                }
            }
        } catch (Exception jsonEx) {
            // Bad JSON — treat as no filters rather than failing the whole query
        }
        return out;
    }

    /**
     * Decode the filter rail's multi-select criteria payload. The wire
     * shape mirrors FilterCriteria, but arrives as a JSON string because
     * LWC → Apex marshalling of nested custom types with DateTime fields
     * is fragile (the same reason `filtersJson` is a string). Each list
     * value is coerced to a String so any numeric / boolean that sneaks in
     * still binds cleanly in the WHERE IN clause.
     */
    private static FilterCriteria parseCriteria(String criteriaJson, DateTime startDate, DateTime endDate) {
        FilterCriteria out = new FilterCriteria(startDate, endDate);
        if (String.isBlank(criteriaJson)) {
            return out;
        }
        try {
            Map<String, Object> decoded = (Map<String, Object>) JSON.deserializeUntyped(criteriaJson);
            out.userIds = extractStringList(decoded, 'userIds');
            out.promptTemplateDevNames = extractStringList(decoded, 'promptTemplateDevNames');
            out.models = extractStringList(decoded, 'models');
            out.providers = extractStringList(decoded, 'providers');
            out.features = extractStringList(decoded, 'features');
            out.appTypes = extractStringList(decoded, 'appTypes');
        } catch (Exception jsonEx) {
            // Bad payload — fall back to no dimension filters
        }
        return out;
    }

    private static List<String> extractStringList(Map<String, Object> decoded, String key) {
        Object raw = decoded.get(key);
        if (raw == null) {
            return null;
        }
        if (!(raw instanceof List<Object>)) {
            return null;
        }
        List<String> out = new List<String>();
        for (Object item : (List<Object>) raw) {
            if (item != null) {
                String s = String.valueOf(item);
                if (String.isNotBlank(s)) {
                    out.add(s);
                }
            }
        }
        return out.isEmpty() ? null : out;
    }

    private static AuraHandledException wrap(Exception e, String friendlyMessage) {
        String detail = e == null ? 'Unknown error' : e.getMessage();
        AuraHandledException ahe = new AuraHandledException(friendlyMessage + ': ' + detail);
        // Preserve a helpful message for the Lightning error surface
        ahe.setMessage(friendlyMessage + ': ' + detail);
        return ahe;
    }
}
