/**
 * Per-group cost breakdown row used by the Tableau Edition's
 * GetCostBreakdownAction so the agent can answer cost questions ("how much
 * did this cost", "spend by model", etc.). Populated by
 * AiInsightsService.getCostConsumption().
 *
 * Mirrors the public fields surfaced by CostCalculatorService.CostResult so
 * callers see the same confidence / source bands they would on the Lightning
 * Overview tile:
 *   - confidence: ACTUAL | HIGH | ESTIMATED | FALLBACK | NOT_COSTED
 *   - source:     ACTUAL_WALLET | ESTIMATED_TIER | NONE
 *
 * `groupKey` is the raw aggregation key (model name, userId, prompt dev name,
 * feature name). `groupLabel` is the human-readable label resolved by
 * UserResolverService for users / prompts; for model and feature it equals
 * `groupKey`.
 */
public class CostBreakdownDTO {
    @AuraEnabled
    public String groupKey;
    @AuraEnabled
    public String groupLabel;
    @AuraEnabled
    public Long flexCredits;
    @AuraEnabled
    public Decimal discountedUsd;
    @AuraEnabled
    public String confidence;
    @AuraEnabled
    public String source;

    public CostBreakdownDTO() {
        this.flexCredits = 0L;
        this.discountedUsd = 0;
        this.confidence = 'HIGH';
        this.source = 'ESTIMATED_TIER';
    }
}
