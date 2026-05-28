/**
 * Agentforce invocable: returns safety/toxicity overview — total generations,
 * toxic count, toxic rate, top safety category by avg score, and recent
 * flagged outputs (capped at 10, with full text fields stripped to keep the
 * agent context window healthy). Used by the `safety_and_tokens` topic.
 */
public with sharing class GetSafetyOverviewAction {
    @TestVisible
    private static AiInsightsService serviceOverride;

    private static final Integer RECENT_FLAGGED_CAP = 10;

    public class Request {
        @InvocableVariable(label='Start date')
        public Datetime startDate;
        @InvocableVariable(label='End date')
        public Datetime endDate;
    }

    public class Response {
        @InvocableVariable(label='Total generations')
        public Integer totalGenerations;
        @InvocableVariable(label='Toxic count')
        public Integer toxicCount;
        @InvocableVariable(label='Toxic rate label' description='Toxic rate as a percent string, e.g. "1.4%".')
        public String toxicRateLabel;
        @InvocableVariable(label='Top safety category name' description='Category with the highest average score.')
        public String topCategoryName;
        @InvocableVariable(label='Top safety category avg score' description='Average score for the top category, 0-1.')
        public Decimal topCategoryAvgScore;
        @InvocableVariable(
            label='Recent flagged outputs JSON'
            description='JSON array of up to 10 recent flagged generations with truncated text. Full text fields stripped to bound context.'
        )
        public String recentFlaggedJson;
    }

    @InvocableMethod(
        label='Get GenAI Safety Overview'
        description='Returns content-safety counts, rates, the top-scored category, and recent flagged outputs (truncated).'
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
                ContentSafetyDTO dto = svc.getSafetyOverview(filter);
                resp.totalGenerations = dto.totalGenerations;
                resp.toxicCount = dto.toxicCount;
                resp.toxicRateLabel = formatRate(dto.toxicRate);

                // Top category by avg score
                if (dto.avgCategoryScores != null && !dto.avgCategoryScores.isEmpty()) {
                    String topCat;
                    Decimal topScore = -1;
                    for (String cat : dto.avgCategoryScores.keySet()) {
                        Decimal score = dto.avgCategoryScores.get(cat);
                        if (score != null && score > topScore) {
                            topScore = score;
                            topCat = cat;
                        }
                    }
                    resp.topCategoryName = topCat;
                    resp.topCategoryAvgScore = topScore < 0 ? null : topScore;
                }

                resp.recentFlaggedJson = JSON.serialize(stripFullText(dto.recentFlaggedOutputs));
            } catch (Exception e) {
                resp.recentFlaggedJson = JSON.serialize(
                    new Map<String, Object>{ 'error' => true, 'message' => e.getMessage() }
                );
            }
            out.add(resp);
        }
        return out;
    }

    /**
     * Drops `inputPromptFull` / `generatedTextFull` from each row and caps the
     * list to RECENT_FLAGGED_CAP. Keeps truncated `inputPrompt` / `generatedText`
     * so the agent still has context to summarize.
     */
    private static List<Map<String, Object>> stripFullText(List<PromptOutputDTO> rows) {
        List<Map<String, Object>> out = new List<Map<String, Object>>();
        if (rows == null) {
            return out;
        }
        Integer cap = Math.min(rows.size(), RECENT_FLAGGED_CAP);
        for (Integer i = 0; i < cap; i++) {
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
        Decimal pct = (rate * 100).setScale(2);
        return pct + '%';
    }
}
