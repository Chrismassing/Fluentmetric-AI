/**
 * Agentforce invocable: returns per-feature adoption rows (breadth, depth,
 * unique users, repeat users, first/last observed). Used by the
 * `adoption_health` topic to answer "which AI features are sticking?".
 */
public with sharing class GetFeatureAdoptionAction {
    @TestVisible
    private static AiInsightsService serviceOverride;

    public class Request {
        @InvocableVariable(label='Start date')
        public Datetime startDate;
        @InvocableVariable(label='End date')
        public Datetime endDate;
    }

    public class Response {
        @InvocableVariable(
            label='Features JSON'
            description='JSON array of {featureName, uniqueUserCount, repeatUserCount, invocationCount, totalTokens, breadthRate, depthMedian, firstObservedInRange, lastObservedInRange, entitledFallback}.'
        )
        public String featuresJson;
        @InvocableVariable(
            label='Entitled fallback'
            description='True when breadth denominator fell back to total active org users (no entitlement Permission Sets matched).'
        )
        public Boolean entitledFallback;
        @InvocableVariable(label='Row count')
        public Integer rowCount;
    }

    @InvocableMethod(
        label='Get GenAI Feature Adoption'
        description='Returns per-feature breadth (unique users / entitled), depth (median invocations), and first/last observed timestamps.'
        category='FluentMetric AI Tableau Next'
    )
    public static List<Response> run(List<Request> requests) {
        AiInsightsService svc = serviceOverride == null ? new AiInsightsService() : serviceOverride;
        List<Response> out = new List<Response>();
        for (Request r : requests) {
            Response resp = new Response();
            try {
                DateRangeFilter filter = new DateRangeFilter();
                filter.startDate = r.startDate == null ? Datetime.now().addDays(-30) : r.startDate;
                filter.endDate = r.endDate == null ? Datetime.now() : r.endDate;
                List<FeatureAdoptionDTO> rows = svc.getFeatureAdoption(filter);
                resp.featuresJson = JSON.serialize(rows == null ? new List<FeatureAdoptionDTO>() : rows);
                resp.rowCount = rows == null ? 0 : rows.size();
                // Take fallback flag from first row — service uses the same denominator across all rows.
                resp.entitledFallback = (rows != null && !rows.isEmpty() && rows[0].entitledFallback == true);
            } catch (Exception e) {
                resp.featuresJson = JSON.serialize(
                    new Map<String, Object>{ 'error' => true, 'message' => e.getMessage() }
                );
                resp.rowCount = 0;
                resp.entitledFallback = false;
            }
            out.add(resp);
        }
        return out;
    }
}
