/**
 * Live DAO for Salesforce Digital Wallet's Consumption Tagging objects.
 *
 * Wallet objects (TenantEnrichedUsageEvent DLO + Consumption Insights DMO +
 * Consumption Insights Extended SDM) are only present in Wallet-enabled
 * production orgs that have installed the Consumption Tagging app from
 * Setup → Digital Wallet. In every other org class — sandboxes, scratch
 * orgs, Data Cloud One companion orgs, trial orgs — these objects do not
 * exist and queries against them throw QueryException at runtime.
 *
 * This DAO defends against that by:
 *   1. Wrapping every Wallet query in try/catch and returning empty/null on
 *      any exception. `isWalletAvailable()` is the authoritative signal.
 *   2. Caching the availability probe per transaction so repeated callers
 *      don't pay the cost of repeated failing queries.
 *   3. Centralising every Wallet field name as a static constant so a
 *      schema-discovery pass against a real prod org only needs to update
 *      one block. See Documents/WALLET-LIVE-SCHEMA.md.
 *
 * Schema basis: doc-derived (Salesforce help articles, see WALLET-LIVE-SCHEMA.md).
 * Field-name casing follows FluentMetric AI's convention from
 * Documents/LIVE-SCHEMA.md (camelCase + `__c`). When the first real prod
 * org becomes available, run the verification checklist in WALLET-LIVE-SCHEMA.md.
 */
public with sharing class AiWalletDAO implements IAiWalletDAO {
    // ───────────────────────── Wallet schema (verified against cvk-dev 2026-05-13) ─────────────────────────
    // Live object: TenantEnrichedUsageEvent__dll (Data Lake Object — `__dll` suffix, NOT `__dlm`).
    // All field names are lowercase + `__c` (NOT camelCase like the FluentMetric AI DMO convention).
    @TestVisible
    private static final String OBJ_TENANT_USAGE = 'TenantEnrichedUsageEvent__dll';

    @TestVisible
    private static final String F_UNITS_CONSUMED = 'unitsconsumed__c';
    @TestVisible
    private static final String F_RESOURCE_ID_OR_NAME = 'resourceidorapiname__c';
    @TestVisible
    private static final String F_ROOT_RESOURCE_ID_OR_NAME = 'rootresourceidorapiname__c';
    @TestVisible
    private static final String F_RESOURCE_TYPE = 'resourcetype__c';
    @TestVisible
    private static final String F_ROOT_RESOURCE_TYPE = 'rootresourcetype__c';
    @TestVisible
    private static final String F_FEATURE_DEV_NAME = 'featuredevelopername__c';
    @TestVisible
    private static final String F_USAGE_TYPE = 'usagetypedevelopername__c';
    @TestVisible
    private static final String F_EVENT_TIME = 'eventtime__c';
    @TestVisible
    private static final String F_USER_ID = 'userid__c';
    @TestVisible
    private static final String F_RESOURCE_TAGS = 'resourcetags__c';
    @TestVisible
    private static final String F_ROOT_RESOURCE_TAGS = 'rootresourcetags__c';
    @TestVisible
    private static final String F_ADDITIONAL_INFO = 'additionalinfo__c';

    // GroupBy enum-like constants exposed to callers.
    public static final String GROUP_BY_RESOURCE = 'RESOURCE';
    public static final String GROUP_BY_ROOT_RESOURCE = 'ROOT_RESOURCE';
    public static final String GROUP_BY_FEATURE = 'FEATURE';
    public static final String GROUP_BY_USAGE_TYPE = 'USAGE_TYPE';
    public static final String GROUP_BY_DATA_SPACE = 'DATA_SPACE';

    /** Transaction-scoped availability cache. */
    @TestVisible
    private static Boolean availabilityCache;

    // ───────────────────────── Public API ─────────────────────────

    public Boolean isWalletAvailable() {
        if (availabilityCache != null) {
            return availabilityCache;
        }
        try {
            // SELECT COUNT() is rejected by this DLO; SELECT Id LIMIT 1 is the
            // cheapest way to verify the object resolves and is queryable.
            String soql = 'SELECT Id FROM ' + OBJ_TENANT_USAGE + ' LIMIT 1';
            Database.queryWithBinds(soql, new Map<String, Object>{}, AccessLevel.USER_MODE);
            availabilityCache = true;
        } catch (Exception ex) {
            // Object missing, no data-space mapping, no permission, no DLO etc.
            // Any failure means Wallet is not available — fall back to estimate.
            availabilityCache = false;
        }
        return availabilityCache;
    }

    public Decimal getTotalFlexCredits(DateTime startDate, DateTime endDate) {
        if (!isWalletAvailable()) {
            return null;
        }
        try {
            String soql =
                'SELECT SUM(' +
                F_UNITS_CONSUMED +
                ') total ' +
                'FROM ' +
                OBJ_TENANT_USAGE +
                ' WHERE ' +
                F_EVENT_TIME +
                ' >= :startDate AND ' +
                F_EVENT_TIME +
                ' <= :endDate';
            List<AggregateResult> rows = Database.queryWithBinds(
                soql,
                new Map<String, Object>{ 'startDate' => startDate, 'endDate' => endDate },
                AccessLevel.USER_MODE
            );
            if (rows == null || rows.isEmpty()) {
                return 0;
            }
            Object total = rows[0].get('total');
            return total == null ? 0 : (Decimal) total;
        } catch (Exception ex) {
            return null;
        }
    }

    public List<WalletAggregateDTO> getFlexCreditAggregates(DateTime startDate, DateTime endDate, String groupBy) {
        if (!isWalletAvailable()) {
            return new List<WalletAggregateDTO>();
        }
        String groupField = resolveGroupField(groupBy);
        if (groupField == null) {
            return new List<WalletAggregateDTO>();
        }
        try {
            String soql =
                'SELECT ' +
                groupField +
                ' grp, SUM(' +
                F_UNITS_CONSUMED +
                ') fc ' +
                'FROM ' +
                OBJ_TENANT_USAGE +
                ' WHERE ' +
                F_EVENT_TIME +
                ' >= :startDate AND ' +
                F_EVENT_TIME +
                ' <= :endDate ' +
                'GROUP BY ' +
                groupField;
            List<AggregateResult> rows = Database.queryWithBinds(
                soql,
                new Map<String, Object>{ 'startDate' => startDate, 'endDate' => endDate },
                AccessLevel.USER_MODE
            );
            return mapAggregates(rows, groupBy);
        } catch (Exception ex) {
            return new List<WalletAggregateDTO>();
        }
    }

    public List<WalletAggregateDTO> getFlexCreditByPrompt(DateTime startDate, DateTime endDate) {
        if (!isWalletAvailable()) {
            return new List<WalletAggregateDTO>();
        }
        try {
            String soql =
                'SELECT ' +
                F_RESOURCE_ID_OR_NAME +
                ' grp, ' +
                F_ROOT_RESOURCE_ID_OR_NAME +
                ' rootGrp, SUM(' +
                F_UNITS_CONSUMED +
                ') fc ' +
                'FROM ' +
                OBJ_TENANT_USAGE +
                ' WHERE ' +
                F_EVENT_TIME +
                ' >= :startDate AND ' +
                F_EVENT_TIME +
                ' <= :endDate ' +
                'GROUP BY ' +
                F_RESOURCE_ID_OR_NAME +
                ', ' +
                F_ROOT_RESOURCE_ID_OR_NAME;
            List<AggregateResult> rows = Database.queryWithBinds(
                soql,
                new Map<String, Object>{ 'startDate' => startDate, 'endDate' => endDate },
                AccessLevel.USER_MODE
            );
            List<WalletAggregateDTO> out = new List<WalletAggregateDTO>();
            if (rows == null) {
                return out;
            }
            for (AggregateResult ar : rows) {
                WalletAggregateDTO dto = new WalletAggregateDTO();
                dto.resourceIdOrApiName = (String) ar.get('grp');
                dto.rootResourceIdOrApiName = (String) ar.get('rootGrp');
                dto.groupKey = dto.resourceIdOrApiName;
                dto.groupLabel = dto.resourceIdOrApiName;
                dto.flexCredits = toDecimal(ar.get('fc'));
                out.add(dto);
            }
            return out;
        } catch (Exception ex) {
            return new List<WalletAggregateDTO>();
        }
    }

    public List<WalletAggregateDTO> getFlexCreditByUser(DateTime startDate, DateTime endDate) {
        if (!isWalletAvailable()) {
            return new List<WalletAggregateDTO>();
        }
        try {
            String soql =
                'SELECT ' +
                F_USER_ID +
                ' grp, SUM(' +
                F_UNITS_CONSUMED +
                ') fc ' +
                'FROM ' +
                OBJ_TENANT_USAGE +
                ' WHERE ' +
                F_EVENT_TIME +
                ' >= :startDate AND ' +
                F_EVENT_TIME +
                ' <= :endDate ' +
                'GROUP BY ' +
                F_USER_ID;
            List<AggregateResult> rows = Database.queryWithBinds(
                soql,
                new Map<String, Object>{ 'startDate' => startDate, 'endDate' => endDate },
                AccessLevel.USER_MODE
            );
            List<WalletAggregateDTO> out = new List<WalletAggregateDTO>();
            if (rows == null) {
                return out;
            }
            for (AggregateResult ar : rows) {
                WalletAggregateDTO dto = new WalletAggregateDTO();
                String uid = (String) ar.get('grp');
                dto.userId = String.isBlank(uid) ? 'NOT_SET' : uid;
                dto.groupKey = dto.userId;
                dto.groupLabel = dto.userId;
                dto.flexCredits = toDecimal(ar.get('fc'));
                out.add(dto);
            }
            return out;
        } catch (Exception ex) {
            return new List<WalletAggregateDTO>();
        }
    }

    /**
     * Custom (and standard) tag aggregation — reads the JSON-encoded
     * `resourcetags__c` and `rootresourcetags__c` strings directly off the
     * TenantEnrichedUsageEvent DLO. Wallet stores tags as JSON per row
     * rather than as separate columns, so aggregation happens in Apex
     * after the fetch.
     *
     * Bounded at 50,000 rows. For wider ranges callers should narrow the
     * date window or pre-aggregate via the Consumption Insights DMO once
     * we add it as a separate DAO method.
     */
    public List<WalletAggregateDTO> getFlexCreditByCustomTag(DateTime startDate, DateTime endDate) {
        if (!isWalletAvailable()) {
            return new List<WalletAggregateDTO>();
        }
        try {
            String soql =
                'SELECT ' +
                F_RESOURCE_TAGS +
                ', ' +
                F_UNITS_CONSUMED +
                ' FROM ' +
                OBJ_TENANT_USAGE +
                ' WHERE ' +
                F_EVENT_TIME +
                ' >= :startDate AND ' +
                F_EVENT_TIME +
                ' <= :endDate ' +
                'AND ' +
                F_RESOURCE_TAGS +
                ' != null ' +
                'LIMIT 50000';
            List<SObject> rows = Database.queryWithBinds(
                soql,
                new Map<String, Object>{ 'startDate' => startDate, 'endDate' => endDate },
                AccessLevel.USER_MODE
            );
            return aggregateTagRows(rows);
        } catch (Exception ex) {
            return new List<WalletAggregateDTO>();
        }
    }

    /**
     * Parses each row's JSON tag string and accumulates Flex Credits per
     * (key, value) pair. Tag rows that fail to parse are silently skipped —
     * we never want a malformed JSON row to break the whole panel.
     */
    private List<WalletAggregateDTO> aggregateTagRows(List<SObject> rows) {
        Map<String, WalletAggregateDTO> bucket = new Map<String, WalletAggregateDTO>();
        if (rows == null) {
            return new List<WalletAggregateDTO>();
        }
        for (SObject row : rows) {
            String tagsJson = (String) row.get(F_RESOURCE_TAGS);
            Decimal fc = toDecimal(row.get(F_UNITS_CONSUMED));
            if (String.isBlank(tagsJson) || fc == 0) {
                continue;
            }
            Map<String, Object> parsed;
            try {
                parsed = (Map<String, Object>) JSON.deserializeUntyped(tagsJson);
            } catch (Exception ignored) {
                continue;
            }
            for (String key : parsed.keySet()) {
                Object value = parsed.get(key);
                String valueStr = value == null ? '' : String.valueOf(value);
                String bucketKey = key + ':' + valueStr;
                WalletAggregateDTO dto = bucket.get(bucketKey);
                if (dto == null) {
                    dto = new WalletAggregateDTO();
                    dto.customTagKey = key;
                    dto.customTagValue = valueStr;
                    dto.groupKey = bucketKey;
                    dto.groupLabel = key + ' = ' + valueStr;
                    dto.flexCredits = 0;
                    bucket.put(bucketKey, dto);
                }
                dto.flexCredits += fc;
            }
        }
        return bucket.values();
    }

    // ───────────────────────── Internals ─────────────────────────

    private String resolveGroupField(String groupBy) {
        if (String.isBlank(groupBy)) {
            return null;
        }
        if (groupBy == GROUP_BY_RESOURCE) {
            return F_RESOURCE_ID_OR_NAME;
        }
        if (groupBy == GROUP_BY_ROOT_RESOURCE) {
            return F_ROOT_RESOURCE_ID_OR_NAME;
        }
        if (groupBy == GROUP_BY_FEATURE) {
            return F_FEATURE_DEV_NAME;
        }
        if (groupBy == GROUP_BY_USAGE_TYPE) {
            return F_USAGE_TYPE;
        }
        // DATA_SPACE is sourced from Additional Info JSON — needs row-level
        // parsing rather than direct GROUP BY. Callers should use the
        // Additional Info path; we surface a safe null here.
        return null;
    }

    private List<WalletAggregateDTO> mapAggregates(List<AggregateResult> rows, String groupBy) {
        List<WalletAggregateDTO> out = new List<WalletAggregateDTO>();
        if (rows == null) {
            return out;
        }
        for (AggregateResult ar : rows) {
            WalletAggregateDTO dto = new WalletAggregateDTO();
            String grp = (String) ar.get('grp');
            dto.groupKey = grp;
            dto.groupLabel = grp;
            dto.flexCredits = toDecimal(ar.get('fc'));
            if (groupBy == GROUP_BY_RESOURCE) {
                dto.resourceIdOrApiName = grp;
            } else if (groupBy == GROUP_BY_ROOT_RESOURCE) {
                dto.rootResourceIdOrApiName = grp;
            } else if (groupBy == GROUP_BY_FEATURE) {
                dto.featureDeveloperName = grp;
            } else if (groupBy == GROUP_BY_USAGE_TYPE) {
                dto.usageType = grp;
            }
            out.add(dto);
        }
        return out;
    }

    private static Decimal toDecimal(Object raw) {
        if (raw == null) {
            return 0;
        }
        if (raw instanceof Decimal) {
            return (Decimal) raw;
        }
        if (raw instanceof Double) {
            return Decimal.valueOf((Double) raw);
        }
        if (raw instanceof Integer) {
            return (Decimal) ((Integer) raw);
        }
        if (raw instanceof Long) {
            return Decimal.valueOf((Long) raw);
        }
        try {
            return Decimal.valueOf(String.valueOf(raw));
        } catch (Exception ignored) {
            return 0;
        }
    }
}
