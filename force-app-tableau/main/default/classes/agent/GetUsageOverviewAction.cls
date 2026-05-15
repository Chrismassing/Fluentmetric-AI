/**
 * Agentforce invocable: returns the headline usage overview KPIs (request
 * volume, unique users, acceptance rate, total tokens, cost) for a date
 * range. Backed by the Lightning edition's AiInsightsService — no Tableau
 * Cloud REST callouts.
 */
public with sharing class GetUsageOverviewAction {
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
        @InvocableVariable(label='Total requests')
        public Integer totalRequests;
        @InvocableVariable(label='Unique users')
        public Integer uniqueUsers;
        @InvocableVariable(label='Acceptance rate label' description='Acceptance rate as a percent string, e.g. "78%".')
        public String acceptanceRateLabel;
        @InvocableVariable(label='Total input tokens')
        public Long totalInputTokens;
        @InvocableVariable(label='Total output tokens')
        public Long totalOutputTokens;
        @InvocableVariable(label='Top user name')
        public String topUserName;
        @InvocableVariable(label='Top prompt label')
        public String topPromptLabel;
        @InvocableVariable(label='Top model name')
        public String topModelName;
        @InvocableVariable(label='Date range label')
        public String dateRangeLabel;
    }

    @InvocableMethod(
        label='Get GenAI Usage Overview'
        description='Returns top-of-funnel KPIs (requests, users, acceptance rate, tokens, top user/prompt/model) for the FluentMetric AI dashboard.'
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
                UsageOverviewDTO dto = svc.getOverview(filter);
                resp.totalRequests = dto.totalRequests;
                resp.uniqueUsers = dto.uniqueUsers;
                resp.acceptanceRateLabel = formatRate(dto.acceptanceRate);
                resp.totalInputTokens = dto.totalInputTokens;
                resp.totalOutputTokens = dto.totalOutputTokens;
                resp.topUserName = dto.topUserName;
                resp.topPromptLabel = dto.topPromptLabel;
                resp.topModelName = dto.topModelName;
                resp.dateRangeLabel = dto.dateRangeLabel;
            } catch (Exception e) {
                resp.dateRangeLabel = 'Error: ' + e.getMessage();
            }
            out.add(resp);
        }
        return out;
    }

    private static String formatRate(Decimal rate) {
        if (rate == null)
            return null;
        Integer pct = Integer.valueOf(Math.round(rate * 100));
        return pct + '%';
    }
}
