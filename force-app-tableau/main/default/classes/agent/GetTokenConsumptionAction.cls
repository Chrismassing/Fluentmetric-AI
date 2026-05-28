/**
 * Agentforce invocable: returns token-consumption rollup grouped by user,
 * prompt, model, day, or week. Used by the `safety_and_tokens` topic to
 * answer "where are we burning tokens?".
 *
 * Service-level guards apply: day grouping is capped at 31 days and week
 * grouping at 12 weeks; wider ranges throw IllegalArgumentException which is
 * surfaced via the JSON error envelope.
 */
public with sharing class GetTokenConsumptionAction {
    @TestVisible
    private static AiInsightsService serviceOverride;

    public class Request {
        @InvocableVariable(label='Start date')
        public Datetime startDate;
        @InvocableVariable(label='End date')
        public Datetime endDate;
        @InvocableVariable(
            label='Group by'
            description='One of: user, prompt, model, day, week. Defaults to "model" when blank.'
        )
        public String groupBy;
    }

    public class Response {
        @InvocableVariable(label='Group by' description='Echoes the resolved group-by dimension.')
        public String groupBy;
        @InvocableVariable(
            label='Rows JSON'
            description='JSON array of {groupKey, groupLabel, totalTokens, requestCount, avgTokensPerRequest}.'
        )
        public String rowsJson;
        @InvocableVariable(label='Top group key')
        public String topGroupKey;
        @InvocableVariable(label='Top group tokens')
        public Long topGroupTokens;
        @InvocableVariable(label='Row count')
        public Integer rowCount;
    }

    @InvocableMethod(
        label='Get GenAI Token Consumption'
        description='Returns token consumption grouped by user/prompt/model/day/week, with the top group surfaced.'
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
                String gb = String.isBlank(r.groupBy) ? 'model' : r.groupBy.toLowerCase();
                resp.groupBy = gb;
                List<TokenConsumptionDTO> rows = svc.getTokenConsumption(filter, gb);
                resp.rowsJson = JSON.serialize(rows);
                resp.rowCount = rows.size();
                if (!rows.isEmpty()) {
                    // Service already sorts DESC by totalTokens — head row is top.
                    resp.topGroupKey = rows[0].groupLabel == null ? rows[0].groupKey : rows[0].groupLabel;
                    resp.topGroupTokens = rows[0].totalTokens;
                }
            } catch (Exception e) {
                resp.rowsJson = JSON.serialize(new Map<String, Object>{ 'error' => true, 'message' => e.getMessage() });
                resp.rowCount = 0;
            }
            out.add(resp);
        }
        return out;
    }
}
