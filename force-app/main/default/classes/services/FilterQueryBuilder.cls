/**
 * Builds safe, bind-only WHERE clauses for GenAIGatewayRequest__dlm queries.
 *
 * Why this exists: AiInsightsService previously hand-rolled
 *   `if (isNotBlank(filter)) soql += ' AND field = :bind'`
 * once per filter dimension. As the Explorer grew more filter axes (user,
 * prompt template, provider, appType) that pattern scaled poorly and each new
 * dimension was another opportunity to forget a bind or leak a value into the
 * SOQL string. This builder centralizes the shape.
 *
 * Contract:
 *   - Caller passes a FilterCriteria.
 *   - Builder emits a `whereClause` (never starts with "WHERE ") and a
 *     `binds` map. Caller prepends "WHERE " itself so callers that need to
 *     splice the clause into a longer query keep full control.
 *   - All values go into `binds`; none are concatenated into SQL.
 *   - Empty lists are skipped entirely — the resulting clause only references
 *     fields the caller filtered on.
 *   - Date range is mandatory (the DMO is too large to scan unbounded).
 */
public with sharing class FilterQueryBuilder {
    public class Result {
        public String whereClause;
        public Map<String, Object> binds;

        public Result(String whereClause, Map<String, Object> binds) {
            this.whereClause = whereClause;
            this.binds = binds;
        }
    }

    /**
     * Build a WHERE clause for GenAIGatewayRequest__dlm using the unqualified
     * field names exposed on that object. Date bounds use `timestamp__c`.
     */
    public static Result build(FilterCriteria criteria) {
        if (criteria == null) {
            throw new IllegalArgumentException('FilterCriteria is required');
        }
        if (criteria.startDate == null || criteria.endDate == null) {
            throw new IllegalArgumentException('startDate and endDate are required');
        }
        List<String> clauses = new List<String>();
        Map<String, Object> binds = new Map<String, Object>();

        clauses.add('timestamp__c >= :startDate');
        clauses.add('timestamp__c <= :endDate');
        binds.put('startDate', criteria.startDate);
        binds.put('endDate', criteria.endDate);

        appendInClause(clauses, binds, 'userId__c', 'userIds', criteria.userIds);
        appendInClause(
            clauses,
            binds,
            'promptTemplateDevName__c',
            'promptTemplateDevNames',
            criteria.promptTemplateDevNames
        );
        appendInClause(clauses, binds, 'model__c', 'models', criteria.models);
        appendInClause(clauses, binds, 'provider__c', 'providers', criteria.providers);
        appendInClause(clauses, binds, 'feature__c', 'features', criteria.features);
        appendInClause(clauses, binds, 'appType__c', 'appTypes', criteria.appTypes);

        return new Result(String.join(clauses, ' AND '), binds);
    }

    /**
     * Back-compat helper: build from a plain date range with no dimension
     * filters, matching the original inline pattern. Preserves existing
     * call-site semantics for paths that don't need the new axes yet.
     */
    public static Result build(DateTime startDate, DateTime endDate) {
        FilterCriteria c = new FilterCriteria(startDate, endDate);
        return build(c);
    }

    private static void appendInClause(
        List<String> clauses,
        Map<String, Object> binds,
        String fieldName,
        String bindName,
        List<String> values
    ) {
        List<String> cleaned = cleanStringList(values);
        if (cleaned.isEmpty()) {
            return;
        }
        // Bind a Set<String> so Salesforce treats it as a true IN-list; passing
        // a raw List<String> works too but Sets are deduped and order-free
        // which matches how the LWC usually emits multi-select values.
        clauses.add(fieldName + ' IN :' + bindName);
        binds.put(bindName, new Set<String>(cleaned));
    }

    private static List<String> cleanStringList(List<String> input) {
        List<String> out = new List<String>();
        if (input == null) {
            return out;
        }
        for (String s : input) {
            if (String.isNotBlank(s)) {
                out.add(s);
            }
        }
        return out;
    }
}
