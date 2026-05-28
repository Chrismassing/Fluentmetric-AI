/**
 * Agentforce invocable: cross-cutting drill-in. Returns aggregate header
 * (request count, tokens, acceptance rate) plus the most recent requests for
 * a given entity (User, PromptTemplate, Model, or Feature). Used by the
 * `drilldown` topic.
 *
 * Context-window guard: recent requests are capped at 10 and stripped of
 * `inputPromptFull` / `generatedTextFull` before serialization.
 */
public with sharing class GetEntityDetailsAction {
    @TestVisible
    private static AiInsightsService serviceOverride;

    private static final Integer RECENT_REQUEST_CAP = 10;

    public class Request {
        @InvocableVariable(label='Start date')
        public Datetime startDate;
        @InvocableVariable(label='End date')
        public Datetime endDate;
        @InvocableVariable(
            label='Entity type'
            description='One of: User, PromptTemplate, Model, Feature.'
            required=true
        )
        public String entityType;
        @InvocableVariable(
            label='Entity key'
            description='Raw identifier — Salesforce User Id for User, prompt dev name for PromptTemplate, model string for Model, feature string for Feature.'
            required=true
        )
        public String entityKey;
        @InvocableVariable(
            label='Recent request limit'
            description='Max recent requests to return. Defaults to 10, capped at 10.'
        )
        public Integer recentLimit;
    }

    public class Response {
        @InvocableVariable(
            label='Entity label'
            description='Resolved human-readable label (user name / prompt label / raw key).'
        )
        public String entityLabel;
        @InvocableVariable(label='Request count')
        public Integer requestCount;
        @InvocableVariable(label='Total tokens')
        public Long totalTokens;
        @InvocableVariable(
            label='Acceptance rate label'
            description='Acceptance rate over the recent generation set, e.g. "78%".'
        )
        public String acceptanceRateLabel;
        @InvocableVariable(label='Unique user count')
        public Integer uniqueUserCount;
        @InvocableVariable(label='Unique prompt count')
        public Integer uniquePromptCount;
        @InvocableVariable(
            label='Recent requests JSON'
            description='JSON array of up to 10 recent requests with truncated text. Full text fields stripped to bound context.'
        )
        public String recentRequestsJson;
    }

    @InvocableMethod(
        label='Get GenAI Entity Details'
        description='Drill-in for any entity (User, PromptTemplate, Model, Feature) — returns aggregate header plus 10 recent truncated requests.'
        category='FluentMetric AI Tableau Next'
    )
    public static List<Response> run(List<Request> requests) {
        AiInsightsService svc = serviceOverride == null ? new AiInsightsService() : serviceOverride;
        List<Response> out = new List<Response>();
        for (Request r : requests) {
            Response resp = new Response();
            try {
                if (String.isBlank(r.entityType)) {
                    throw new IllegalArgumentException('entityType is required');
                }
                if (String.isBlank(r.entityKey)) {
                    throw new IllegalArgumentException('entityKey is required');
                }
                DateRangeFilter filter = new DateRangeFilter();
                filter.startDate = r.startDate == null ? Datetime.now().addDays(-30) : r.startDate;
                filter.endDate = r.endDate == null ? Datetime.now() : r.endDate;
                Integer cap = (r.recentLimit == null ||
                    r.recentLimit <= 0)
                    ? RECENT_REQUEST_CAP
                    : Math.min(r.recentLimit, RECENT_REQUEST_CAP);

                EntityDetailsDTO dto = svc.getEntityDetails(r.entityType, r.entityKey, filter, cap);
                resp.entityLabel = dto.entityLabel;
                resp.requestCount = dto.requestCount;
                resp.totalTokens = dto.totalTokens;
                resp.acceptanceRateLabel = formatRate(dto.acceptanceRate);
                resp.uniqueUserCount = dto.uniqueUserCount;
                resp.uniquePromptCount = dto.uniquePromptCount;
                resp.recentRequestsJson = JSON.serialize(stripFullText(dto.recentRequests, cap));
            } catch (Exception e) {
                resp.recentRequestsJson = JSON.serialize(
                    new Map<String, Object>{ 'error' => true, 'message' => e.getMessage() }
                );
            }
            out.add(resp);
        }
        return out;
    }

    private static List<Map<String, Object>> stripFullText(List<PromptOutputDTO> rows, Integer cap) {
        List<Map<String, Object>> out = new List<Map<String, Object>>();
        if (rows == null) {
            return out;
        }
        Integer effectiveCap = Math.min(rows.size(), cap);
        for (Integer i = 0; i < effectiveCap; i++) {
            PromptOutputDTO r = rows[i];
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

    private static String formatRate(Decimal rate) {
        if (rate == null) {
            return null;
        }
        Integer pct = Integer.valueOf(Math.round(rate * 100));
        return pct + '%';
    }
}
