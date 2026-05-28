/**
 * Agentforce invocable: returns the entitlement-aware adoption snapshot —
 * how many users are entitled (via configured Permission Sets), how many were
 * active in the window, and the resulting adoption rate. Used by the
 * `adoption_health` topic to answer "how many of my licensed users actually
 * use AI?".
 */
public with sharing class GetEntitlementSnapshotAction {
    @TestVisible
    private static AiInsightsService serviceOverride;

    public class Request {
        @InvocableVariable(
            label='Start date'
            description='Start of the analysis window. Defaults to 30 days ago when blank.'
        )
        public Datetime startDate;
        @InvocableVariable(label='End date' description='End of the analysis window. Defaults to now when blank.')
        public Datetime endDate;
    }

    public class Response {
        @InvocableVariable(label='Entitled user count')
        public Integer entitledCount;
        @InvocableVariable(label='Active user count')
        public Integer activeCount;
        @InvocableVariable(label='Adoption rate label' description='Adoption rate as a percent string, e.g. "62%".')
        public String adoptionRateLabel;
        @InvocableVariable(
            label='Entitled fallback'
            description='True when the configured Permission Sets resolved zero entitled users and the snapshot fell back to total active org users.'
        )
        public Boolean entitledFallback;
        @InvocableVariable(
            label='Unmatched active count'
            description='Active users who do not appear in the entitled set — surfaces a misconfigured Permission Set list.'
        )
        public Integer unmatchedActiveCount;
        @InvocableVariable(
            label='Configured permission sets label'
            description='Comma-joined list of configured Permission Set names — empty when nothing is configured.'
        )
        public String configuredPermissionSetsLabel;
    }

    @InvocableMethod(
        label='Get GenAI Entitlement Snapshot'
        description='Returns entitled vs. active user counts, adoption rate, and the configured Permission Set list for the FluentMetric AI dashboard.'
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
                EntitlementSnapshotDTO dto = svc.getEntitlementSnapshot(filter);
                resp.entitledCount = dto.entitledCount;
                resp.activeCount = dto.activeCount;
                resp.adoptionRateLabel = formatRate(dto.adoptionRate);
                resp.entitledFallback = dto.entitledFallback;
                resp.unmatchedActiveCount = dto.unmatchedActiveCount;
                resp.configuredPermissionSetsLabel = dto.configuredPermissionSets == null
                    ? ''
                    : String.join(dto.configuredPermissionSets, ', ');
            } catch (Exception e) {
                resp.adoptionRateLabel = 'Error: ' + e.getMessage();
            }
            out.add(resp);
        }
        return out;
    }

    private static String formatRate(Decimal rate) {
        if (rate == null) {
            return null;
        }
        Integer pct = Integer.valueOf(Math.round(rate * 100));
        return pct + '%';
    }
}
