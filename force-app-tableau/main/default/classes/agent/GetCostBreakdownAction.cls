/**
 * Agentforce invocable: returns a per-group cost breakdown so the
 * FluentMetric Tableau Analyst agent can answer cost questions
 * ("how much did this cost", "spend by model", "cost breakdown by user").
 *
 * Mirrors the JSON-error-envelope pattern of GetTokenConsumptionAction.
 * Defaults the date window to the trailing 30 days when caller leaves
 * dates blank — same default the rest of the Tableau Edition uses.
 *
 * Inputs:
 *   - startDate  (Datetime, optional)
 *   - endDate    (Datetime, optional)
 *   - groupBy    (String, optional — model | user | prompt | feature; defaults to model)
 *
 * Outputs:
 *   - groupBy           — echoes the resolved dimension
 *   - totalFlexCredits  — sum of FC across all rows
 *   - totalUsd          — sum of discountedUsd across all rows
 *   - costConfidence    — ACTUAL when Wallet is the source, otherwise the
 *                         weakest band across rows (HIGH > ESTIMATED >
 *                         FALLBACK > NOT_COSTED)
 *   - costSource        — ACTUAL_WALLET when any row is wallet-stamped, else
 *                         ESTIMATED_TIER
 *   - rowsJson          — JSON array of CostBreakdownDTO rows
 */
public with sharing class GetCostBreakdownAction {
    @TestVisible
    private static AiInsightsService serviceOverride;

    public class Request {
        @InvocableVariable(label='Start date')
        public Datetime startDate;
        @InvocableVariable(label='End date')
        public Datetime endDate;
        @InvocableVariable(
            label='Group by'
            description='One of: model, user, prompt, feature. Defaults to "model" when blank.'
        )
        public String groupBy;
    }

    public class Response {
        @InvocableVariable(label='Group by' description='Echoes the resolved group-by dimension.')
        public String groupBy;
        @InvocableVariable(label='Total Flex Credits' description='Sum of Flex Credits across all rows.')
        public Long totalFlexCredits;
        @InvocableVariable(label='Total USD' description='Sum of discounted USD across all rows.')
        public Decimal totalUsd;
        @InvocableVariable(
            label='Cost confidence'
            description='ACTUAL when Wallet sourced; otherwise weakest band across rows (HIGH/ESTIMATED/FALLBACK/NOT_COSTED).'
        )
        public String costConfidence;
        @InvocableVariable(
            label='Cost source'
            description='ACTUAL_WALLET when wallet-stamped, otherwise ESTIMATED_TIER.'
        )
        public String costSource;
        @InvocableVariable(
            label='Rows JSON'
            description='JSON array of {groupKey, groupLabel, flexCredits, discountedUsd, confidence, source}.'
        )
        public String rowsJson;
    }

    @InvocableMethod(
        label='Get GenAI Cost Breakdown'
        description='Returns Flex Credit + USD cost grouped by model/user/prompt/feature, with Wallet-first confidence badging.'
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

                List<CostBreakdownDTO> rows = svc.getCostConsumption(filter, gb);
                resp.rowsJson = JSON.serialize(rows);

                Long totalFc = 0L;
                Decimal totalUsd = 0;
                String aggregateConfidence = null;
                String aggregateSource = CostCalculatorService.SOURCE_ESTIMATE;
                Boolean anyWallet = false;
                for (CostBreakdownDTO dto : rows) {
                    if (dto.flexCredits != null) {
                        totalFc += dto.flexCredits;
                    }
                    if (dto.discountedUsd != null) {
                        totalUsd += dto.discountedUsd;
                    }
                    aggregateConfidence = weakerConfidence(aggregateConfidence, dto.confidence);
                    if (CostCalculatorService.SOURCE_WALLET.equals(dto.source)) {
                        anyWallet = true;
                    }
                }
                resp.totalFlexCredits = totalFc;
                resp.totalUsd = totalUsd.setScale(4);
                resp.costConfidence = aggregateConfidence == null
                    ? CostCalculatorService.CONFIDENCE_HIGH
                    : aggregateConfidence;
                resp.costSource = anyWallet ? CostCalculatorService.SOURCE_WALLET : aggregateSource;
            } catch (Exception e) {
                resp.rowsJson = JSON.serialize(new Map<String, Object>{ 'error' => true, 'message' => e.getMessage() });
                resp.totalFlexCredits = 0L;
                resp.totalUsd = 0;
                resp.costConfidence = CostCalculatorService.CONFIDENCE_NOT_COSTED;
                resp.costSource = CostCalculatorService.SOURCE_NONE;
            }
            out.add(resp);
        }
        return out;
    }

    /**
     * Pick the weaker of two confidence bands so the rolled-up label reflects
     * the lowest-quality input. Treats null as "no opinion yet" so the first
     * non-null value wins.
     */
    private static String weakerConfidence(String current, String incoming) {
        if (incoming == null) {
            return current;
        }
        if (current == null) {
            return incoming;
        }
        Map<String, Integer> rank = new Map<String, Integer>{
            CostCalculatorService.CONFIDENCE_ACTUAL => 4,
            CostCalculatorService.CONFIDENCE_HIGH => 3,
            CostCalculatorService.CONFIDENCE_ESTIMATED => 2,
            CostCalculatorService.CONFIDENCE_FALLBACK => 1,
            CostCalculatorService.CONFIDENCE_NOT_COSTED => 0
        };
        Integer cr = rank.containsKey(current) ? rank.get(current) : 3;
        Integer ir = rank.containsKey(incoming) ? rank.get(incoming) : 3;
        return cr <= ir ? current : incoming;
    }
}
