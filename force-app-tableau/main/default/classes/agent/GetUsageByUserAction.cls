/**
 * Agentforce invocable: returns the top-N users ranked by GenAI request volume
 * for a date range. Used by the Tableau Next Analyst agent to answer "who are
 * the heaviest AI users?".
 */
public with sharing class GetUsageByUserAction {
    @TestVisible
    private static AiInsightsService serviceOverride;

    public class Request {
        @InvocableVariable(label='Start date')
        public Datetime startDate;
        @InvocableVariable(label='End date')
        public Datetime endDate;
        @InvocableVariable(label='Top N rows' description='Limit on the number of users returned. Defaults to 10.')
        public Integer topN;
    }

    public class Response {
        @InvocableVariable(
            label='Users JSON'
            description='JSON array of {userName, requestCount, acceptanceRate, totalTokens}.'
        )
        public String usersJson;
        @InvocableVariable(label='Row count')
        public Integer rowCount;
    }

    @InvocableMethod(
        label='Get GenAI Usage by User'
        description='Returns the top users by request volume with acceptance rate and total tokens.'
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
                List<UserUsageDTO> rows = svc.getUsageByUser(filter);
                Integer limitN = r.topN == null || r.topN <= 0 ? 10 : r.topN;
                if (rows.size() > limitN) {
                    rows = new List<UserUsageDTO>(rows);
                    List<UserUsageDTO> trimmed = new List<UserUsageDTO>();
                    for (Integer i = 0; i < limitN; i++)
                        trimmed.add(rows[i]);
                    rows = trimmed;
                }
                resp.usersJson = JSON.serialize(rows);
                resp.rowCount = rows.size();
            } catch (Exception e) {
                resp.usersJson = JSON.serialize(
                    new Map<String, Object>{ 'error' => true, 'message' => e.getMessage() }
                );
                resp.rowCount = 0;
            }
            out.add(resp);
        }
        return out;
    }
}
