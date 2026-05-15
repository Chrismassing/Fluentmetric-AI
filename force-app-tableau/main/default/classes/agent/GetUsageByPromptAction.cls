/**
 * Agentforce invocable: returns top prompt templates ranked by invocation
 * count, with acceptance rate. Used to answer "which prompts are getting the
 * most use / worst feedback?".
 */
public with sharing class GetUsageByPromptAction {
    @TestVisible
    private static AiInsightsService serviceOverride;

    public class Request {
        @InvocableVariable(label='Start date')
        public Datetime startDate;
        @InvocableVariable(label='End date')
        public Datetime endDate;
        @InvocableVariable(label='Top N rows')
        public Integer topN;
    }

    public class Response {
        @InvocableVariable(label='Prompts JSON' description='JSON array of {promptLabel, invocations, acceptanceRate}.')
        public String promptsJson;
        @InvocableVariable(label='Row count')
        public Integer rowCount;
    }

    @InvocableMethod(
        label='Get GenAI Usage by Prompt'
        description='Returns the top prompt templates by invocation volume with acceptance rate.'
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
                List<PromptUsageDTO> rows = svc.getUsageByPrompt(filter);
                Integer limitN = r.topN == null || r.topN <= 0 ? 10 : r.topN;
                if (rows.size() > limitN) {
                    List<PromptUsageDTO> trimmed = new List<PromptUsageDTO>();
                    for (Integer i = 0; i < limitN; i++)
                        trimmed.add(rows[i]);
                    rows = trimmed;
                }
                resp.promptsJson = JSON.serialize(rows);
                resp.rowCount = rows.size();
            } catch (Exception e) {
                resp.promptsJson = JSON.serialize(
                    new Map<String, Object>{ 'error' => true, 'message' => e.getMessage() }
                );
                resp.rowCount = 0;
            }
            out.add(resp);
        }
        return out;
    }
}
