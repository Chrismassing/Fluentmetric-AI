/**
 * Agentforce invocable: returns sample prompt outputs for a specific prompt
 * template. Used by the `drilldown` topic to answer "show me sample outputs
 * for prompt X" or "what did this prompt generate?".
 *
 * Context-window guard: rows are capped at 25 and stripped of
 * `inputPromptFull` / `generatedTextFull` before serialization.
 */
public with sharing class GetPromptOutputsAction {
    @TestVisible
    private static AiInsightsService serviceOverride;

    private static final Integer OUTPUT_ROW_CAP = 25;

    public class Request {
        @InvocableVariable(label='Start date')
        public Datetime startDate;
        @InvocableVariable(label='End date')
        public Datetime endDate;
        @InvocableVariable(
            label='Prompt dev name'
            description='Prompt template developer name (raw, unquoted).'
            required=true
        )
        public String promptDevName;
        @InvocableVariable(label='Limit count' description='Max output rows to return. Defaults to 10, capped at 25.')
        public Integer limitCount;
    }

    public class Response {
        @InvocableVariable(
            label='Outputs JSON'
            description='JSON array of {requestId, userName, requestDate, inputPrompt, generatedText, feedbackValue, isToxic, inputTokens, outputTokens, model}. Truncated text only.'
        )
        public String outputsJson;
        @InvocableVariable(label='Row count')
        public Integer rowCount;
    }

    @InvocableMethod(
        label='Get GenAI Prompt Outputs'
        description='Returns sample input/output pairs for a specific prompt template, with truncated text and feedback/toxicity flags.'
        category='FluentMetric AI Tableau Next'
    )
    public static List<Response> run(List<Request> requests) {
        AiInsightsService svc = serviceOverride == null ? new AiInsightsService() : serviceOverride;
        List<Response> out = new List<Response>();
        for (Request r : requests) {
            Response resp = new Response();
            try {
                if (String.isBlank(r.promptDevName)) {
                    throw new IllegalArgumentException('promptDevName is required');
                }
                DateRangeFilter filter = new DateRangeFilter();
                filter.startDate = r.startDate == null ? Datetime.now().addDays(-30) : r.startDate;
                filter.endDate = r.endDate == null ? Datetime.now() : r.endDate;
                Integer effectiveLimit = (r.limitCount == null ||
                    r.limitCount <= 0)
                    ? 10
                    : Math.min(r.limitCount, OUTPUT_ROW_CAP);
                List<PromptOutputDTO> rows = svc.getPromptOutputs(r.promptDevName, filter, effectiveLimit);
                resp.outputsJson = JSON.serialize(stripFullText(rows));
                resp.rowCount = rows == null ? 0 : rows.size();
            } catch (Exception e) {
                resp.outputsJson = JSON.serialize(
                    new Map<String, Object>{ 'error' => true, 'message' => e.getMessage() }
                );
                resp.rowCount = 0;
            }
            out.add(resp);
        }
        return out;
    }

    private static List<Map<String, Object>> stripFullText(List<PromptOutputDTO> rows) {
        List<Map<String, Object>> out = new List<Map<String, Object>>();
        if (rows == null) {
            return out;
        }
        for (PromptOutputDTO r : rows) {
            out.add(
                new Map<String, Object>{
                    'requestId' => r.requestId,
                    'userName' => r.userName,
                    'requestDate' => r.requestDate,
                    'inputPrompt' => r.inputPrompt,
                    'generatedText' => r.generatedText,
                    'feedbackValue' => r.feedbackValue,
                    'isToxic' => r.isToxic,
                    'inputTokens' => r.inputTokens,
                    'outputTokens' => r.outputTokens,
                    'model' => r.model
                }
            );
        }
        return out;
    }
}
