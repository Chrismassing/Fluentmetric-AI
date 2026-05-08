/**
 * Cost analytics service for FluentMetric AI.
 *
 * Pricing model (v1.5 — tier-based, matches the sf-flex-estimator formulas):
 *   Prompt FC = tierRate × max(1, ceil(totalTokens / Prompt_Token_Threshold__c)) × requestCount
 *   Action FC = Action_Flat_FC__c × max(1, ceil(actionTokens / Action_Token_Threshold__c)) × actionCount
 *   USD       = FC × Flex_Credit_USD_Rate__c × (1 - Discount_Percent__c/100)
 *
 * `FluentMetric_Rate_Card__mdt.Tier__c` (Basic / Standard / Advanced) is the
 * authoritative signal. The per-model `Flex_Credits_Per_Call__c` and
 * `USD_Per_Call__c` fields are deprecated override escape hatches — the
 * primary code path ignores them.
 *
 * Agentforce gating:
 *   Action invocations are NOT inferred from `botVersionId__c` rows in
 *   `GenAIGatewayRequest__dlm` — they require STDM. This service exposes
 *   `costForAgentforceActions(...)` for callers that have real action counts
 *   from `ssot__AiAgentInteractionStep__dlm`. Callers without STDM should
 *   emit `CostResult` with `confidence = NOT_COSTED` for bot-origin rows.
 *
 * Design notes:
 *   - Rate card + settings caches are transaction-scoped statics.
 *   - Every method is `virtual` so tests can subclass.
 *   - NEVER throws — all error paths return a zero-cost `CostResult`.
 */
public with sharing virtual class CostCalculatorService {
    @TestVisible
    private static final String FALLBACK_KEY_DEFAULT = 'standard-default';
    @TestVisible
    private static final Decimal DEFAULT_USD_PER_CREDIT = 0.004;
    @TestVisible
    private static final Decimal ZERO = 0;

    // Confidence bands — surfaced to the UI as badges.
    public static final String CONFIDENCE_HIGH = 'HIGH';
    public static final String CONFIDENCE_ESTIMATED = 'ESTIMATED';
    public static final String CONFIDENCE_FALLBACK = 'FALLBACK';
    public static final String CONFIDENCE_NOT_COSTED = 'NOT_COSTED';

    // Tier identifiers (must match FluentMetric_Rate_Card__mdt.Tier__c picklist).
    private static final String TIER_BASIC = 'Basic';
    private static final String TIER_STANDARD = 'Standard';
    private static final String TIER_ADVANCED = 'Advanced';

    // Defaults if settings fields are null — mirror Salesforce public rates.
    private static final Decimal DEFAULT_TIER_BASIC_FC = 2;
    private static final Decimal DEFAULT_TIER_STANDARD_FC = 4;
    private static final Decimal DEFAULT_TIER_ADVANCED_FC = 16;
    private static final Decimal DEFAULT_ACTION_FLAT_FC = 20;
    private static final Long DEFAULT_PROMPT_TOKEN_THRESHOLD = 2000;
    private static final Long DEFAULT_ACTION_TOKEN_THRESHOLD = 10000;

    /** Transaction-scoped rate card cache. Key: lowercased Model__c. */
    @TestVisible
    private static Map<String, FluentMetric_Rate_Card__mdt> rateCardByModel;

    /** Transaction-scoped settings cache. */
    @TestVisible
    private static FluentMetric_Cost_Settings__c settingsCache;

    /** Result DTO consumed by LWCs and the AiInsightsService callers. */
    public class CostResult {
        @AuraEnabled
        public Long flexCredits;
        @AuraEnabled
        public Decimal baseUsd;
        @AuraEnabled
        public Decimal discountedUsd;
        @AuraEnabled
        public Boolean usedFallback;
        @AuraEnabled
        public String confidence;

        public CostResult() {
            this.flexCredits = 0L;
            this.baseUsd = 0;
            this.discountedUsd = 0;
            this.usedFallback = false;
            this.confidence = CONFIDENCE_HIGH;
        }

        public CostResult(Long flexCredits, Decimal baseUsd, Decimal discountedUsd, Boolean usedFallback) {
            this(flexCredits, baseUsd, discountedUsd, usedFallback, CONFIDENCE_HIGH);
        }

        public CostResult(
            Long flexCredits,
            Decimal baseUsd,
            Decimal discountedUsd,
            Boolean usedFallback,
            String confidence
        ) {
            this.flexCredits = flexCredits == null ? 0L : flexCredits;
            this.baseUsd = baseUsd == null ? 0 : baseUsd;
            this.discountedUsd = discountedUsd == null ? 0 : discountedUsd;
            this.usedFallback = usedFallback == true;
            this.confidence = String.isBlank(confidence) ? CONFIDENCE_HIGH : confidence;
        }
    }

    // ───────────────────────── Public API ─────────────────────────

    /**
     * Compute cost for N prompt invocations against a given model.
     * Uses tier × token-overage × requestCount math. `totalTokens` is the
     * SUM across all `requestCount` invocations — per-invocation overage
     * is approximated as `ceil(totalTokens / requestCount / threshold)`.
     */
    public virtual CostResult costForAggregate(String model, Integer requestCount, Long totalTokens) {
        if (requestCount == null || requestCount <= 0) {
            return new CostResult();
        }
        if (!isCostMetricsEnabled()) {
            return new CostResult();
        }
        try {
            FluentMetric_Rate_Card__mdt rate = matchRateCard(model);
            if (rate == null) {
                return new CostResult();
            }
            if (rate.Is_Unmetered__c == true) {
                // Unmetered models (Salesforce-internal classifiers) cost $0
                // deliberately — this is a known-correct pricing answer, not
                // a NOT_COSTED failure. Mark HIGH so it doesn't drag the
                // aggregate confidence down.
                return new CostResult(0L, 0, 0, false, CONFIDENCE_HIGH);
            }

            Decimal tierRate = tierRateFor(rate.Tier__c);
            Integer overageMultiplier = overageMultiplierFor(totalTokens, requestCount, promptTokenThreshold());
            Decimal totalFcDecimal = tierRate * overageMultiplier * requestCount;
            Long fc = totalFcDecimal.longValue();
            Decimal baseUsd = (totalFcDecimal * flexCreditUsdRate()).setScale(4);

            Boolean usedFallback = rate.Is_Default_Fallback__c == true;
            String confidence = resolveConfidence(model, rate);
            return new CostResult(fc, baseUsd, applyDiscount(baseUsd), usedFallback, confidence);
        } catch (Exception e) {
            return new CostResult();
        }
    }

    /**
     * Price a batch of Agentforce Actions at the flat Action_Flat_FC__c rate.
     * Callers must supply real Action counts — typically joined from
     * `ssot__AiAgentInteractionStep__dlm` where step_type = 'ACTION_STEP'.
     * When STDM isn't available, callers should NOT invoke this method and
     * instead flag bot-origin rows as NOT_COSTED.
     */
    public virtual CostResult costForAgentforceActions(Integer actionCount, Long totalActionTokens) {
        if (actionCount == null || actionCount <= 0) {
            return new CostResult();
        }
        if (!isCostMetricsEnabled()) {
            return new CostResult();
        }
        try {
            Decimal flatRate = actionFlatFc();
            Integer overageMultiplier = overageMultiplierFor(totalActionTokens, actionCount, actionTokenThreshold());
            Decimal totalFcDecimal = flatRate * overageMultiplier * actionCount;
            Long fc = totalFcDecimal.longValue();
            Decimal baseUsd = (totalFcDecimal * flexCreditUsdRate()).setScale(4);
            return new CostResult(fc, baseUsd, applyDiscount(baseUsd), false, CONFIDENCE_HIGH);
        } catch (Exception e) {
            return new CostResult();
        }
    }

    /**
     * Build a zero-cost result explicitly marked NOT_COSTED. Intended for
     * Agentforce-origin rows when STDM isn't available — the UI will render
     * a "enable STDM to see Agentforce costs" inline link.
     */
    public virtual CostResult notCosted() {
        return new CostResult(0L, 0, 0, false, CONFIDENCE_NOT_COSTED);
    }

    /**
     * Master opt-in gate. Reads `Enable_Cost_Metrics__c` from the hierarchy
     * custom setting. Defaults to FALSE so fresh installs don't surface cost
     * numbers until an admin has reviewed the rate-card disclaimer.
     */
    public virtual Boolean isCostMetricsEnabled() {
        try {
            FluentMetric_Cost_Settings__c s = getSettings();
            return s != null && s.Enable_Cost_Metrics__c == true;
        } catch (Exception e) {
            return false;
        }
    }

    /**
     * Sum cost for a list of raw GenAIGatewayRequest__dlm SObjects. Groups
     * by model__c so each model is priced from its own rate card, then sums.
     * Per-row tokens are summed per model so each bucket's overage multiplier
     * is computed from the real total, not averaged.
     */
    public virtual CostResult costForRequests(List<SObject> requests) {
        if (requests == null || requests.isEmpty()) {
            return new CostResult();
        }
        try {
            Map<String, Integer> countsByModel = new Map<String, Integer>();
            Map<String, Long> tokensByModel = new Map<String, Long>();
            for (SObject r : requests) {
                if (r == null) {
                    continue;
                }
                String m = safeGetString(r, 'model__c');
                Integer prev = countsByModel.get(m);
                countsByModel.put(m, (prev == null ? 0 : prev) + 1);
                Long tt = safeGetLong(r, 'totalTokens__c');
                Long prevTokens = tokensByModel.get(m);
                tokensByModel.put(m, (prevTokens == null ? 0L : prevTokens) + (tt == null ? 0L : tt));
            }

            Long totalFc = 0L;
            Decimal totalBase = 0;
            Decimal totalDiscounted = 0;
            Boolean anyFallback = false;
            String aggregateConfidence = CONFIDENCE_HIGH;

            for (String m : countsByModel.keySet()) {
                CostResult partial = costForAggregate(m, countsByModel.get(m), tokensByModel.get(m));
                totalFc += (partial.flexCredits == null ? 0L : partial.flexCredits);
                totalBase += (partial.baseUsd == null ? 0 : partial.baseUsd);
                totalDiscounted += (partial.discountedUsd == null ? 0 : partial.discountedUsd);
                if (partial.usedFallback == true) {
                    anyFallback = true;
                }
                aggregateConfidence = worstConfidence(aggregateConfidence, partial.confidence);
            }

            return new CostResult(totalFc, totalBase, totalDiscounted, anyFallback, aggregateConfidence);
        } catch (Exception e) {
            return new CostResult();
        }
    }

    /**
     * Read the hierarchy custom setting once per transaction. Returns a
     * sensible default when no org-level record exists. NEVER throws.
     */
    public virtual FluentMetric_Cost_Settings__c getSettings() {
        if (settingsCache != null) {
            return settingsCache;
        }
        FluentMetric_Cost_Settings__c s;
        try {
            s = FluentMetric_Cost_Settings__c.getOrgDefaults();
        } catch (Exception e) {
            s = null;
        }
        if (s == null) {
            s = new FluentMetric_Cost_Settings__c();
        }
        if (s.Flex_Credit_USD_Rate__c == null) {
            s.Flex_Credit_USD_Rate__c = DEFAULT_USD_PER_CREDIT;
        }
        if (s.Discount_Percent__c == null) {
            s.Discount_Percent__c = 0;
        }
        if (String.isBlank(s.Default_Fallback_Model__c)) {
            s.Default_Fallback_Model__c = 'Standard-Default';
        }
        settingsCache = s;
        return settingsCache;
    }

    /**
     * Apply the org's discount percent to a base USD amount. Public so LWCs
     * and tests can reuse the exact same arithmetic.
     */
    public virtual Decimal applyDiscount(Decimal baseCost) {
        if (baseCost == null) {
            return 0;
        }
        Decimal pct = getSettings().Discount_Percent__c;
        if (pct == null || pct <= 0) {
            return baseCost.setScale(4);
        }
        if (pct >= 100) {
            return 0;
        }
        Decimal multiplier = (100 - pct) / 100;
        return (baseCost * multiplier).setScale(4);
    }

    // ───────────────────────── Tier / threshold lookups ─────────────────────

    @TestVisible
    protected virtual Decimal tierRateFor(String tier) {
        FluentMetric_Cost_Settings__c s = getSettings();
        if (tier == TIER_BASIC) {
            return s.Tier_Basic_FC__c == null ? DEFAULT_TIER_BASIC_FC : s.Tier_Basic_FC__c;
        }
        if (tier == TIER_ADVANCED) {
            return s.Tier_Advanced_FC__c == null ? DEFAULT_TIER_ADVANCED_FC : s.Tier_Advanced_FC__c;
        }
        // Standard is the default for null, blank, or unknown tier strings —
        // matches "when in doubt, price at Standard" fallback behavior.
        return s.Tier_Standard_FC__c == null ? DEFAULT_TIER_STANDARD_FC : s.Tier_Standard_FC__c;
    }

    @TestVisible
    protected virtual Decimal actionFlatFc() {
        FluentMetric_Cost_Settings__c s = getSettings();
        return s.Action_Flat_FC__c == null ? DEFAULT_ACTION_FLAT_FC : s.Action_Flat_FC__c;
    }

    @TestVisible
    protected virtual Long promptTokenThreshold() {
        FluentMetric_Cost_Settings__c s = getSettings();
        Decimal v = s.Prompt_Token_Threshold__c;
        return v == null ? DEFAULT_PROMPT_TOKEN_THRESHOLD : v.longValue();
    }

    @TestVisible
    protected virtual Long actionTokenThreshold() {
        FluentMetric_Cost_Settings__c s = getSettings();
        Decimal v = s.Action_Token_Threshold__c;
        return v == null ? DEFAULT_ACTION_TOKEN_THRESHOLD : v.longValue();
    }

    private Decimal flexCreditUsdRate() {
        Decimal rate = getSettings().Flex_Credit_USD_Rate__c;
        return rate == null ? DEFAULT_USD_PER_CREDIT : rate;
    }

    /**
     * Compute the overage multiplier for a bucket of `count` invocations
     * that together consumed `totalTokens`. The rule is per-invocation:
     * crossing the threshold re-charges the base fee. For aggregated data
     * we approximate with `ceil(avgTokensPerInvocation / threshold) × count`,
     * then divide back out to produce a single multiplier — so the caller's
     * formula `tierRate × multiplier × count` matches real billing.
     *
     * When totalTokens is null or zero, returns 1 (no overage).
     */
    @TestVisible
    protected virtual Integer overageMultiplierFor(Long totalTokens, Integer count, Long threshold) {
        if (
            totalTokens == null ||
            totalTokens <= 0 ||
            threshold == null ||
            threshold <= 0 ||
            count == null ||
            count <= 0
        ) {
            return 1;
        }
        Decimal avgPerInvocation = Decimal.valueOf(totalTokens) / count;
        Decimal raw = avgPerInvocation / threshold;
        Integer multiplier = Math.max(1, (Integer) raw.round(System.RoundingMode.CEILING));
        return multiplier;
    }

    // ───────────────────────── Confidence ─────────────────────────

    /**
     * Classify the match quality for UI badging. HIGH when the model key is
     * an exact rate-card match, ESTIMATED when we had to prefix-walk,
     * FALLBACK when nothing matched and we used the default record.
     */
    @TestVisible
    protected virtual String resolveConfidence(String rawModel, FluentMetric_Rate_Card__mdt rate) {
        if (rate == null) {
            return CONFIDENCE_NOT_COSTED;
        }
        if (rate.Is_Default_Fallback__c == true) {
            return CONFIDENCE_FALLBACK;
        }
        if (String.isBlank(rawModel) || String.isBlank(rate.Model__c)) {
            return CONFIDENCE_ESTIMATED;
        }
        String rawLc = rawModel.toLowerCase().trim();
        String rateLc = rate.Model__c.toLowerCase().trim();
        return rawLc == rateLc ? CONFIDENCE_HIGH : CONFIDENCE_ESTIMATED;
    }

    /**
     * When summing buckets, the aggregate confidence is the "worst" of any
     * contributing bucket — NOT_COSTED > FALLBACK > ESTIMATED > HIGH.
     */
    @TestVisible
    protected virtual String worstConfidence(String a, String b) {
        if (a == CONFIDENCE_NOT_COSTED || b == CONFIDENCE_NOT_COSTED) {
            return CONFIDENCE_NOT_COSTED;
        }
        if (a == CONFIDENCE_FALLBACK || b == CONFIDENCE_FALLBACK) {
            return CONFIDENCE_FALLBACK;
        }
        if (a == CONFIDENCE_ESTIMATED || b == CONFIDENCE_ESTIMATED) {
            return CONFIDENCE_ESTIMATED;
        }
        return CONFIDENCE_HIGH;
    }

    // ───────────────────────── Internals ─────────────────────────

    @TestVisible
    protected virtual Map<String, FluentMetric_Rate_Card__mdt> loadRateCards() {
        if (rateCardByModel != null) {
            return rateCardByModel;
        }
        Map<String, FluentMetric_Rate_Card__mdt> loaded = new Map<String, FluentMetric_Rate_Card__mdt>();
        try {
            for (FluentMetric_Rate_Card__mdt rc : [
                SELECT
                    Id,
                    DeveloperName,
                    Model__c,
                    Provider__c,
                    Tier__c,
                    Flex_Credits_Per_Call__c,
                    USD_Per_Call__c,
                    Is_Default_Fallback__c,
                    Is_Unmetered__c
                FROM FluentMetric_Rate_Card__mdt
            ]) {
                if (String.isBlank(rc.Model__c)) {
                    continue;
                }
                loaded.put(rc.Model__c.toLowerCase().trim(), rc);
            }
        } catch (Exception e) {
            // CMDT should always be queryable — never throw from here.
        }
        rateCardByModel = loaded;
        return rateCardByModel;
    }

    /**
     * Resolve a raw model string to a rate card.
     *   1. exact lowercase match
     *   2. prefix match after stripping date suffix (-YYYY-MM-DD)
     *   3. prefix match after stripping common version tags (-preview, -turbo, -mini)
     *   4. prefix walk on '-' boundaries
     *   5. Is_Default_Fallback__c record
     *   6. synthetic zero-cost fallback
     */
    @TestVisible
    protected virtual FluentMetric_Rate_Card__mdt matchRateCard(String rawModel) {
        Map<String, FluentMetric_Rate_Card__mdt> cache = loadRateCards();

        if (!String.isBlank(rawModel)) {
            String lc = rawModel.toLowerCase().trim();

            if (cache.containsKey(lc)) {
                return cache.get(lc);
            }

            String stripped = lc.replaceAll('-\\d{4}-\\d{2}-\\d{2}$', '');
            if (stripped != lc && cache.containsKey(stripped)) {
                return cache.get(stripped);
            }

            for (String suffix : new List<String>{ '-preview', '-turbo', '-mini' }) {
                if (lc.endsWith(suffix)) {
                    String base = lc.substring(0, lc.length() - suffix.length());
                    if (cache.containsKey(base)) {
                        return cache.get(base);
                    }
                }
            }

            Integer idx = stripped.lastIndexOf('-');
            while (idx > 0) {
                String prefix = stripped.substring(0, idx);
                if (cache.containsKey(prefix)) {
                    return cache.get(prefix);
                }
                idx = prefix.lastIndexOf('-');
            }
        }

        for (FluentMetric_Rate_Card__mdt rc : cache.values()) {
            if (rc.Is_Default_Fallback__c == true) {
                return rc;
            }
        }

        FluentMetric_Rate_Card__mdt synthetic = new FluentMetric_Rate_Card__mdt();
        synthetic.Model__c = 'Synthetic-Zero';
        synthetic.Tier__c = TIER_STANDARD;
        synthetic.Flex_Credits_Per_Call__c = 0;
        synthetic.USD_Per_Call__c = 0;
        synthetic.Is_Default_Fallback__c = true;
        return synthetic;
    }

    @TestVisible
    protected virtual String normalizeModelKey(String raw) {
        if (String.isBlank(raw)) {
            return '';
        }
        String lc = raw.toLowerCase().trim();
        lc = lc.replaceAll('-\\d{4}-\\d{2}-\\d{2}$', '');
        Map<String, FluentMetric_Rate_Card__mdt> cache = loadRateCards();
        if (!cache.containsKey(lc)) {
            for (String suffix : new List<String>{ '-preview', '-turbo', '-mini' }) {
                if (lc.endsWith(suffix)) {
                    String base = lc.substring(0, lc.length() - suffix.length());
                    if (cache.containsKey(base)) {
                        return base;
                    }
                }
            }
        }
        return lc;
    }

    @TestVisible
    private String safeGetString(SObject so, String field) {
        try {
            Object v = so.get(field);
            return v == null ? null : String.valueOf(v);
        } catch (Exception e) {
            return null;
        }
    }

    @TestVisible
    private Long safeGetLong(SObject so, String field) {
        try {
            Object v = so.get(field);
            if (v == null) {
                return null;
            }
            if (v instanceof Decimal) {
                return ((Decimal) v).longValue();
            }
            if (v instanceof Integer) {
                return (Long) ((Integer) v);
            }
            if (v instanceof Long) {
                return (Long) v;
            }
            return Long.valueOf(String.valueOf(v));
        } catch (Exception e) {
            return null;
        }
    }

    /** Test hook: reset the transaction caches between test methods. */
    @TestVisible
    private static void resetCachesForTest() {
        rateCardByModel = null;
        settingsCache = null;
    }
}
