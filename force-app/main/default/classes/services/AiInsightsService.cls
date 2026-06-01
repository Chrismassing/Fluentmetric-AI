/**
 * Business-logic layer for the FluentMetric AI dashboards.
 *
 * Orchestrates DAO calls, aggregates results in Apex (DMOs cannot ORDER BY
 * aggregates or use parent-child subqueries), resolves identifiers to
 * human-readable labels via UserResolverService, and returns LWC-friendly DTOs.
 *
 * Dependency injection:
 *   - Primary constructor accepts `(IAiInsightsDAO, UserResolverService)` so
 *     tests can pass `AiInsightsDAOMock` and avoid DMO queries
 *   - Zero-arg constructor wires the live DAO + resolver for `@AuraEnabled` use
 *
 * Schema quirks handled (see Documents/LIVE-SCHEMA.md):
 *   - `userId__c` may be the sentinel `"NOT_SET"` — passed through to resolver
 *   - `promptTemplateDevName__c` comes back wrapped in literal double quotes
 *   - `isToxicityDetected__c` is a string ("true"/"false")
 *   - `value__c` on GenAIContentCategory__dlm is a string-encoded decimal
 *   - Token fields are Double — null-coalesced to 0 before summing
 *   - All date filtering uses `timestamp__c`
 */
public with sharing virtual class AiInsightsService {
    @TestVisible
    private static final String FEEDBACK_POSITIVE_ACCEPTED = 'accepted';
    @TestVisible
    private static final String FEEDBACK_POSITIVE_THUMBS_UP = 'thumbs_up';
    @TestVisible
    private static final String FEEDBACK_NEGATIVE_REJECTED = 'rejected';
    @TestVisible
    private static final String FEEDBACK_NEGATIVE_THUMBS_DOWN = 'thumbs_down';
    @TestVisible
    private static final Decimal SAFETY_FLAG_THRESHOLD = 0.5;
    @TestVisible
    private static final Integer TOP_N_DEFAULT = 10;
    @TestVisible
    private static final Integer OUTPUT_TRUNCATE_LEN = 280;
    @TestVisible
    private static final String SYSTEM_SENTINEL = 'NOT_SET';
    @TestVisible
    private static final String CACHE_PARTITION_NAME = 'local.FluentMetric_AI';

    @TestVisible
    private final IAiInsightsDAO dao;
    @TestVisible
    private final UserResolverService resolver;
    @TestVisible
    private final IEntitlementService entitlement;

    public AiInsightsService() {
        this(new AiInsightsDAO(), new UserResolverService(), new EntitlementService());
    }

    public AiInsightsService(IAiInsightsDAO dao, UserResolverService resolver) {
        this(dao, resolver, new EntitlementService());
    }

    public AiInsightsService(IAiInsightsDAO dao, UserResolverService resolver, IEntitlementService entitlement) {
        this.dao = dao;
        this.resolver = resolver;
        this.entitlement = entitlement;
    }

    // ───────────────────────── Overview ─────────────────────────

    public virtual UsageOverviewDTO getOverview(DateRangeFilter filter) {
        validateFilter(filter);
        UsageOverviewDTO out = new UsageOverviewDTO();
        out.dateRangeLabel = formatRangeLabel(filter);

        // Aggregate totals + counts from the DMO server-side — avoids the 50k heap limit
        AggregateResult totals = dao.getRequestTotals(filter.startDate, filter.endDate);
        if (totals != null) {
            out.totalRequests = toInteger(totals.get('cnt'));
            out.totalInputTokens = toLong(totals.get('pt'));
            out.totalOutputTokens = toLong(totals.get('ct'));
        }
        out.uniqueUsers = dao.countDistinctUsers(filter.startDate, filter.endDate);
        out.uniquePromptTemplates = dao.countDistinctPromptTemplates(filter.startDate, filter.endDate);

        // Feedback — separate DMO, typically orders of magnitude smaller than requests
        Integer fbTotal = 0;
        Integer fbPositive = 0;
        try {
            List<SObject> feedback = dao.getFeedbackForDateRange(filter.startDate, filter.endDate);
            for (SObject f : feedback) {
                fbTotal++;
                if (isPositiveFeedback(f)) {
                    fbPositive++;
                }
            }
        } catch (Exception fbEx) {
            // If feedback volume is huge or inaccessible, fall back to zero rather than fail the dashboard
        }
        out.feedbackCount = fbTotal;
        out.acceptanceRate = fbTotal == 0 ? 0 : ((Decimal) fbPositive / fbTotal).setScale(4);

        // Toxic flag count — use the Quality DMO's own timestamp rather than joining from requests.
        // Volume is typically tiny (only flagged rows get scored).
        out.toxicFlagCount = dao.countToxicFlagsByDateRange(filter.startDate, filter.endDate);

        // Highlights — who's winning, what's hot. All failure paths are
        // isolated so the main KPI strip still renders even if one highlight
        // can't be computed.
        populateHighlights(out, filter);

        // Cost analytics (Phase 3.5) — sum per-model LLM costs into the org total,
        // add Agentforce action FC when STDM is available. Confidence is the
        // weakest band seen across components (HIGH > ESTIMATED > FALLBACK > NOT_COSTED).
        try {
            CostCalculatorService cost = new CostCalculatorService();
            List<AggregateResult> modelAggs = dao.getRequestAggregatesByModel(filter.startDate, filter.endDate);
            Long totalFc = 0L;
            Decimal totalBase = 0;
            Decimal totalDiscounted = 0;
            String rolledConfidence = CostCalculatorService.CONFIDENCE_HIGH;
            if (modelAggs != null) {
                for (AggregateResult a : modelAggs) {
                    String gkey = (String) a.get('gkey');
                    Integer cnt = toInteger(a.get('cnt'));
                    Long tt = toLong(a.get('tt'));
                    CostCalculatorService.CostResult cr = cost.costForAggregate(gkey, cnt, tt);
                    totalFc += cr.flexCredits == null ? 0L : cr.flexCredits;
                    totalBase += cr.baseUsd == null ? 0 : cr.baseUsd;
                    totalDiscounted += cr.discountedUsd == null ? 0 : cr.discountedUsd;
                    rolledConfidence = weakerConfidence(rolledConfidence, cr.confidence);
                }
            }

            // Agentforce actions — flat 20 FC each (× overage) when STDM is reachable.
            Integer actionCount = 0;
            Long actionFc = 0L;
            Decimal actionBase = 0;
            Decimal actionDiscounted = 0;
            String actionConfidence = CostCalculatorService.CONFIDENCE_NOT_COSTED;
            if (dao.isStdmAvailable(filter.startDate, filter.endDate)) {
                actionCount = dao.countAgentforceActionsByDateRange(filter.startDate, filter.endDate);
                if (actionCount != null && actionCount > 0) {
                    CostCalculatorService.CostResult ar = cost.costForAgentforceActions(actionCount, null);
                    actionFc = ar.flexCredits == null ? 0L : ar.flexCredits;
                    actionBase = ar.baseUsd == null ? 0 : ar.baseUsd;
                    actionDiscounted = ar.discountedUsd == null ? 0 : ar.discountedUsd;
                    actionConfidence = ar.confidence;
                } else {
                    actionConfidence = CostCalculatorService.CONFIDENCE_HIGH;
                }
            }

            out.estimatedFlexCredits = totalFc + actionFc;
            out.estimatedBaseUsd = (totalBase + actionBase).setScale(4);
            out.estimatedUsdAfterDiscount = (totalDiscounted + actionDiscounted).setScale(4);
            out.agentforceActionCount = actionCount == null ? 0 : actionCount;
            out.agentforceFlexCredits = actionFc;
            out.agentforceUsd = actionDiscounted.setScale(4);
            out.costConfidence = weakerConfidence(rolledConfidence, actionConfidence);
            out.costSource = CostCalculatorService.SOURCE_ESTIMATE;

            // Wallet-first override: when Digital Wallet is provisioned and
            // `Enable_Wallet_Costs__c` is on, replace the headline FC with the
            // Wallet actual. Wallet's `unitsconsumed__c` already includes both
            // LLM and Agentforce action consumption, so we DO NOT add the
            // Agentforce action FC on top — the breakdown stays in the
            // dedicated `agentforceFlexCredits` field for reference, but the
            // headline total comes purely from Wallet.
            if (cost.isWalletPreferred()) {
                CostCalculatorService.CostResult wallet = cost.costForWindow(filter.startDate, filter.endDate, null);
                if (
                    wallet != null &&
                    wallet.confidence == CostCalculatorService.CONFIDENCE_ACTUAL &&
                    wallet.flexCredits > 0
                ) {
                    out.estimatedFlexCredits = wallet.flexCredits;
                    out.estimatedBaseUsd = wallet.baseUsd == null ? 0 : wallet.baseUsd;
                    out.estimatedUsdAfterDiscount = wallet.discountedUsd == null ? 0 : wallet.discountedUsd;
                    out.costConfidence = CostCalculatorService.CONFIDENCE_ACTUAL;
                    out.costSource = CostCalculatorService.SOURCE_WALLET;
                }
            }
        } catch (Exception costEx) {
            // Never break the dashboard on cost errors — DTO already has zeros from constructor.
        }

        // Adoption snapshot (Phase 3.2). Pull active user IDs from the per-user
        // aggregate already computed by `populateHighlights` is too late — that
        // method swallows the list. Re-run the cheap aggregate so we have a
        // crisp set of active userIds for the entitled-population denominator.
        try {
            Set<String> activeUidStrings = new Set<String>();
            List<AggregateResult> userAggs = dao.getRequestAggregatesByUser(filter.startDate, filter.endDate);
            if (userAggs != null) {
                for (AggregateResult a : userAggs) {
                    String uid = (String) a.get('gkey');
                    if (String.isNotBlank(uid)) {
                        activeUidStrings.add(uid);
                    }
                }
            }
            EntitlementSnapshotDTO snap = entitlement.getSnapshot(activeUidStrings);
            if (snap != null) {
                out.entitledUserCount = snap.entitledCount == null ? 0 : snap.entitledCount;
                out.totalActiveOrgUsers = snap.totalActiveOrgUsers == null ? 0 : snap.totalActiveOrgUsers;
                out.adoptionRate = snap.adoptionRate == null ? 0 : snap.adoptionRate;
                out.entitledFallback = snap.entitledFallback == null ? true : snap.entitledFallback;
            }
        } catch (Exception entEx) {
            // Adoption snapshot failures keep the overview rendering — DTO
            // defaults already encode the fallback condition.
        }

        // WoW deltas (Phase 3.2) — latest week vs. prior week. Cheap two-call
        // total since we only need the last 14 days regardless of the active
        // filter. Each block isolated so one broken delta doesn't kill the
        // others.
        try {
            populateOverviewWowDeltas(out);
        } catch (Exception wowEx) {
            // Leave defaults (0).
        }

        return out;
    }

    @TestVisible
    private void populateOverviewWowDeltas(UsageOverviewDTO out) {
        DateTime now = DateTime.now();
        DateTime latestStart = now.addDays(-7);
        DateTime priorStart = now.addDays(-14);
        DateTime priorEnd = latestStart.addSeconds(-1);

        AggregateResult latestTot = null;
        AggregateResult priorTot = null;
        try {
            latestTot = dao.getRequestTotals(latestStart, now);
        } catch (Exception e) {
        }
        try {
            priorTot = dao.getRequestTotals(priorStart, priorEnd);
        } catch (Exception e) {
        }
        Integer latestRequests = latestTot == null ? 0 : toInteger(latestTot.get('cnt'));
        Integer priorRequests = priorTot == null ? 0 : toInteger(priorTot.get('cnt'));
        Long latestTokens = latestTot == null ? 0L : (toLong(latestTot.get('pt')) + toLong(latestTot.get('ct')));
        Long priorTokens = priorTot == null ? 0L : (toLong(priorTot.get('pt')) + toLong(priorTot.get('ct')));

        Integer latestUsers = 0;
        Integer priorUsers = 0;
        try {
            latestUsers = dao.getDistinctUserCountInWindow(latestStart, now);
        } catch (Exception e) {
        }
        try {
            priorUsers = dao.getDistinctUserCountInWindow(priorStart, priorEnd);
        } catch (Exception e) {
        }

        out.requestsWowPct = wowPct(latestRequests, priorRequests);
        out.usersWowPct = wowPct(latestUsers, priorUsers);
        out.tokensWowPct = wowPct(latestTokens, priorTokens);
    }

    // ───────────────────────── Overview trends ─────────────────────────
    //
    // Side-channel companion to getOverview. Two responsibilities:
    //  1. Prior-window KPIs for ±% delta badges (same metric definitions
    //     as getOverview, evaluated over the immediately preceding window
    //     of equal length).
    //  2. Daily-bucket sparkline series (requests / tokens / toxic flags)
    //     for inline SVG polylines on the KPI cards.
    //
    // Kept separate from getOverview so:
    //  - The cached getOverview query does not get invalidated by a schema
    //    change here.
    //  - Trend failures degrade gracefully — the LWC falls back to the static
    //    numbers from getOverview if this call errors.
    //  - Prior-window failures do not hide current-window numbers.

    public virtual OverviewTrendsDTO getOverviewTrends(DateRangeFilter filter) {
        validateFilter(filter);
        OverviewTrendsDTO out = new OverviewTrendsDTO();

        DateRangeFilter priorFilter = buildPriorWindowFilter(filter);

        // --- Prior-window KPIs --------------------------------------------
        // Each block is isolated in its own try so one broken DMO doesn't
        // wipe out the delta badges on the other cards.
        try {
            AggregateResult priorTotals = dao.getRequestTotals(priorFilter.startDate, priorFilter.endDate);
            if (priorTotals != null) {
                out.previousTotalRequests = toInteger(priorTotals.get('cnt'));
                Long pt = toLong(priorTotals.get('pt'));
                Long ct = toLong(priorTotals.get('ct'));
                out.previousTotalTokens = (pt == null ? 0L : pt) + (ct == null ? 0L : ct);
            }
        } catch (Exception e) {
            // Prior-totals failed — leave zeros in DTO so the LWC treats as "no prior data".
        }

        try {
            out.previousUniqueUsers = dao.countDistinctUsers(priorFilter.startDate, priorFilter.endDate);
        } catch (Exception e) {
        }

        try {
            Integer fbTotal = 0;
            Integer fbPositive = 0;
            List<SObject> priorFb = dao.getFeedbackForDateRange(priorFilter.startDate, priorFilter.endDate);
            for (SObject f : priorFb) {
                fbTotal++;
                if (isPositiveFeedback(f)) {
                    fbPositive++;
                }
            }
            out.previousFeedbackCount = fbTotal;
            out.previousAcceptanceRate = fbTotal == 0 ? 0 : ((Decimal) fbPositive / fbTotal).setScale(4);
        } catch (Exception e) {
        }

        try {
            // Prior-window toxic count comes from the DAO rather than a direct
            // DMO COUNT(): DAO is mockable, so service tests can seed it, and
            // the current window already hits this method for the daily strip
            // below — reusing the same source keeps numbers consistent.
            List<SObject> priorTox = dao.getToxicFlagTimestamps(priorFilter.startDate, priorFilter.endDate);
            out.previousToxicFlagCount = priorTox == null ? 0 : priorTox.size();
        } catch (Exception e) {
        }

        // --- Daily sparkline series ---------------------------------------
        // Fixed day-granularity: good enough up to 90-day ranges (max 90
        // points per series). For longer ranges the LWC visually skips every
        // Nth point; the series itself stays day-granular.
        Integer days = Math.max(1, daysBetween(filter.startDate, filter.endDate));
        out.daysInWindow = days;
        List<Integer> reqBuckets = new List<Integer>();
        List<Long> tokBuckets = new List<Long>();
        List<Integer> toxBuckets = new List<Integer>();
        for (Integer i = 0; i < days; i++) {
            reqBuckets.add(0);
            tokBuckets.add(0L);
            toxBuckets.add(0);
        }

        try {
            List<SObject> rows = dao.getRequestTimestampsAndTokens(filter.startDate, filter.endDate);
            for (SObject row : rows) {
                Integer idx = dayIndex(row.get('timestamp__c'), filter.startDate, days);
                if (idx < 0) {
                    continue;
                }
                reqBuckets[idx] = reqBuckets[idx] + 1;
                Long tt = toLong(row.get('totalTokens__c'));
                tokBuckets[idx] = tokBuckets[idx] + (tt == null ? 0L : tt);
            }
        } catch (Exception e) {
            // Sparkline data unavailable — DTO already seeded with zeros.
        }

        try {
            List<SObject> toxRows = dao.getToxicFlagTimestamps(filter.startDate, filter.endDate);
            for (SObject row : toxRows) {
                Integer idx = dayIndex(row.get('timestamp__c'), filter.startDate, days);
                if (idx < 0) {
                    continue;
                }
                toxBuckets[idx] = toxBuckets[idx] + 1;
            }
        } catch (Exception e) {
        }

        out.dailyRequests = reqBuckets;
        out.dailyTokens = tokBuckets;
        out.dailyToxicFlags = toxBuckets;
        return out;
    }

    /**
     * Prior-window filter: same length, ending immediately before the main
     * window starts. Edge case: when start == end (degenerate 0-length
     * range), we pad to at least one millisecond so the prior window is
     * well-formed.
     */
    @TestVisible
    private static DateRangeFilter buildPriorWindowFilter(DateRangeFilter filter) {
        Long windowMillis = filter.endDate.getTime() - filter.startDate.getTime();
        if (windowMillis <= 0) {
            windowMillis = 1L;
        }
        DateTime priorEnd = DateTime.newInstance(filter.startDate.getTime() - 1L);
        DateTime priorStart = DateTime.newInstance(priorEnd.getTime() - windowMillis);
        return new DateRangeFilter(priorStart, priorEnd);
    }

    /**
     * Integer day count between two DateTimes (ceil). Always ≥ 1 so the
     * sparkline has at least one bucket even for intra-day ranges.
     */
    @TestVisible
    private static Integer daysBetween(DateTime a, DateTime b) {
        if (a == null || b == null) {
            return 1;
        }
        Long ms = b.getTime() - a.getTime();
        if (ms < 0) {
            ms = -ms;
        }
        Long days = (ms / (24L * 60L * 60L * 1000L)) + 1L;
        if (days > 366L) {
            days = 366L;
        }
        return days.intValue();
    }

    /**
     * Map a row timestamp to its day-bucket index (0 = first day in window).
     * Returns -1 when the timestamp is outside the window or unparseable.
     */
    @TestVisible
    private static Integer dayIndex(Object rawTs, DateTime rangeStart, Integer totalDays) {
        if (rawTs == null || rangeStart == null || totalDays == null || totalDays <= 0) {
            return -1;
        }
        DateTime ts;
        if (rawTs instanceof DateTime) {
            ts = (DateTime) rawTs;
        } else {
            try {
                ts = DateTime.valueOf(String.valueOf(rawTs));
            } catch (Exception e) {
                return -1;
            }
        }
        Long deltaMs = ts.getTime() - rangeStart.getTime();
        if (deltaMs < 0) {
            return -1;
        }
        Long idx = deltaMs / (24L * 60L * 60L * 1000L);
        if (idx >= totalDays) {
            return totalDays - 1;
        }
        return idx.intValue();
    }

    @TestVisible
    private void populateHighlights(UsageOverviewDTO out, DateRangeFilter filter) {
        // Top user: max requestCount from the user aggregates
        try {
            List<AggregateResult> userAggs = dao.getRequestAggregatesByUser(filter.startDate, filter.endDate);
            String topUid;
            Integer topUserCnt = -1;
            for (AggregateResult a : userAggs) {
                Integer cnt = toInteger(a.get('cnt'));
                if (cnt > topUserCnt) {
                    topUserCnt = cnt;
                    topUid = (String) a.get('gkey');
                }
            }
            if (topUid != null) {
                Map<String, String> names = resolver.resolveUserNames(new Set<String>{ topUid });
                out.topUserName = names.get(topUid);
                out.topUserRequestCount = topUserCnt;
            }
        } catch (Exception e) {
            // Skip this highlight
        }

        // Top prompt: max invocationCount from the prompt aggregates
        try {
            List<AggregateResult> promptAggs = dao.getRequestAggregatesByPrompt(filter.startDate, filter.endDate);
            String topPdn;
            Integer topPromptCnt = -1;
            for (AggregateResult a : promptAggs) {
                String pdn = (String) a.get('gkey');
                if (String.isBlank(pdn)) {
                    continue;
                }
                Integer cnt = toInteger(a.get('cnt'));
                if (cnt > topPromptCnt) {
                    topPromptCnt = cnt;
                    topPdn = pdn;
                }
            }
            if (topPdn != null) {
                Map<String, String> labels = resolver.resolvePromptTemplateLabels(new Set<String>{ topPdn });
                out.topPromptLabel = labels.get(topPdn);
                out.topPromptInvocations = topPromptCnt;
            }
        } catch (Exception e) {
            // Skip this highlight
        }

        // Top model: max totalTokens from the model aggregates
        try {
            List<AggregateResult> modelAggs = dao.getRequestAggregatesByModel(filter.startDate, filter.endDate);
            String topModel;
            Long topTokens = -1L;
            for (AggregateResult a : modelAggs) {
                Long tt = toLong(a.get('tt'));
                if (tt > topTokens) {
                    topTokens = tt;
                    topModel = (String) a.get('gkey');
                }
            }
            if (topModel != null) {
                out.topModelName = topModel;
                out.topModelTotalTokens = topTokens;
            }
        } catch (Exception e) {
            // Skip this highlight
        }

        // Top feature: max requestCount from the feature aggregates
        try {
            List<AggregateResult> featureAggs = dao.getRequestAggregatesByFeature(filter.startDate, filter.endDate);
            String topFeature;
            Integer topFeatureCnt = -1;
            for (AggregateResult a : featureAggs) {
                String f = (String) a.get('gkey');
                if (String.isBlank(f)) {
                    continue;
                }
                Integer cnt = toInteger(a.get('cnt'));
                if (cnt > topFeatureCnt) {
                    topFeatureCnt = cnt;
                    topFeature = f;
                }
            }
            if (topFeature != null) {
                out.topFeatureName = topFeature;
                out.topFeatureRequestCount = topFeatureCnt;
            }
        } catch (Exception e) {
            // Skip this highlight
        }
    }

    // ───────────────────────── Usage by User ─────────────────────

    public virtual List<UserUsageDTO> getUsageByUser(DateRangeFilter filter) {
        validateFilter(filter);

        // Server-side aggregates — one row per user, scales to any org volume
        List<AggregateResult> userAggs = dao.getRequestAggregatesByUser(filter.startDate, filter.endDate);
        if (userAggs.isEmpty()) {
            return new List<UserUsageDTO>();
        }

        // Seed per-user metrics from the aggregate result set
        Map<String, UserUsageDTO> dtoByUser = new Map<String, UserUsageDTO>();
        Set<String> userIds = new Set<String>();
        for (AggregateResult a : userAggs) {
            String uid = (String) a.get('gkey');
            if (uid == null) {
                uid = SYSTEM_SENTINEL;
            }
            UserUsageDTO dto = new UserUsageDTO();
            dto.userId = uid;
            dto.requestCount = toInteger(a.get('cnt'));
            dto.totalTokens = toLong(a.get('tt'));
            dto.firstUsed = (DateTime) a.get('minTs');
            dto.lastUsed = (DateTime) a.get('maxTs');
            dtoByUser.put(uid, dto);
            userIds.add(uid);
        }

        // Per-user top prompts — one grouped query, no raw rows pulled
        Map<String, Map<String, Integer>> promptCountByUser = new Map<String, Map<String, Integer>>();
        Set<String> allPromptDevNames = new Set<String>();
        try {
            List<AggregateResult> userPromptAggs = dao.getRequestAggregatesByUserAndPrompt(
                filter.startDate,
                filter.endDate
            );
            for (AggregateResult a : userPromptAggs) {
                String uid = (String) a.get('uid');
                if (uid == null) {
                    uid = SYSTEM_SENTINEL;
                }
                String pdn = (String) a.get('pdn');
                if (String.isBlank(pdn)) {
                    continue;
                }
                Integer cnt = toInteger(a.get('cnt'));
                if (!promptCountByUser.containsKey(uid)) {
                    promptCountByUser.put(uid, new Map<String, Integer>());
                }
                promptCountByUser.get(uid).put(pdn, cnt);
                allPromptDevNames.add(pdn);
            }
        } catch (Exception aggEx) {
            // Multi-column aggregate may be unavailable on older API versions — fall back to skipping top prompts
        }

        // Per-user feedback ratio — feedback volume is typically tiny vs. requests
        Map<String, Integer> posByUser = new Map<String, Integer>();
        Map<String, Integer> negByUser = new Map<String, Integer>();
        try {
            List<SObject> feedback = dao.getFeedbackForDateRange(filter.startDate, filter.endDate);
            for (SObject f : feedback) {
                String uid = (String) f.get('userId__c');
                if (uid == null) {
                    uid = SYSTEM_SENTINEL;
                }
                if (!dtoByUser.containsKey(uid)) {
                    // Feedback from a user with no requests in range — ignore
                    continue;
                }
                if (isPositiveFeedback(f)) {
                    posByUser.put(uid, (posByUser.get(uid) == null ? 0 : posByUser.get(uid)) + 1);
                } else if (isNegativeFeedback(f)) {
                    negByUser.put(uid, (negByUser.get(uid) == null ? 0 : negByUser.get(uid)) + 1);
                }
            }
        } catch (Exception fbEx) {
            // If feedback is huge or inaccessible, show 0/0 rather than fail the whole dashboard
        }

        // Resolve names (cached) — one SOQL across all users
        Map<String, UserResolverService.ResolvedUser> resolved = resolver.resolveUsersDetailed(userIds);
        // Resolve prompt labels (cached)
        Map<String, String> promptLabels = allPromptDevNames.isEmpty()
            ? new Map<String, String>()
            : resolver.resolvePromptTemplateLabels(allPromptDevNames);

        for (String uid : dtoByUser.keySet()) {
            UserUsageDTO dto = dtoByUser.get(uid);
            UserResolverService.ResolvedUser ru = resolved.get(uid);
            if (ru != null) {
                dto.userName = ru.name;
                dto.profileName = ru.profileName;
                dto.department = ru.department;
            } else {
                dto.userName = uid;
            }
            dto.positiveFeedbackCount = posByUser.get(uid) == null ? 0 : posByUser.get(uid);
            dto.negativeFeedbackCount = negByUser.get(uid) == null ? 0 : negByUser.get(uid);
            Integer fbTotal = dto.positiveFeedbackCount + dto.negativeFeedbackCount;
            dto.feedbackRatio = fbTotal == 0 ? 0 : ((Decimal) dto.positiveFeedbackCount / fbTotal).setScale(4);

            Map<String, Integer> promptCounts = promptCountByUser.get(uid);
            if (promptCounts != null && !promptCounts.isEmpty()) {
                for (String dn : topNKeys(promptCounts, 3)) {
                    dto.topPrompts.add(promptLabels.get(dn) == null ? dn : promptLabels.get(dn));
                }
            }
        }

        // Cost analytics (Phase 3.5) — sum per-user-per-model costs into each user's total.
        try {
            CostCalculatorService cost = new CostCalculatorService();
            List<AggregateResult> userModelAggs = dao.getRequestAggregatesByUserAndModel(
                filter.startDate,
                filter.endDate
            );
            Map<String, Long> fcByUser = new Map<String, Long>();
            Map<String, Decimal> usdByUser = new Map<String, Decimal>();
            Map<String, Boolean> fallbackByUser = new Map<String, Boolean>();
            Map<String, String> confidenceByUser = new Map<String, String>();
            for (AggregateResult a : userModelAggs) {
                String uid = (String) a.get('uid');
                if (uid == null) {
                    uid = SYSTEM_SENTINEL;
                }
                if (!dtoByUser.containsKey(uid)) {
                    continue;
                }
                String modelKey = (String) a.get('pdn');
                Integer cnt = toInteger(a.get('cnt'));
                Long tt = toLong(a.get('tt'));
                CostCalculatorService.CostResult cr = cost.costForAggregate(modelKey, cnt, tt);
                fcByUser.put(
                    uid,
                    (fcByUser.get(uid) == null ? 0L : fcByUser.get(uid)) +
                    (cr.flexCredits == null ? 0L : cr.flexCredits)
                );
                usdByUser.put(
                    uid,
                    (usdByUser.get(uid) == null ? (Decimal) 0 : usdByUser.get(uid)) +
                    (cr.discountedUsd == null ? (Decimal) 0 : cr.discountedUsd)
                );
                if (cr.usedFallback == true) {
                    fallbackByUser.put(uid, true);
                }
                confidenceByUser.put(uid, weakerConfidence(confidenceByUser.get(uid), cr.confidence));
            }
            for (String uid : dtoByUser.keySet()) {
                UserUsageDTO dto = dtoByUser.get(uid);
                dto.estimatedFlexCredits = fcByUser.get(uid) == null ? 0L : fcByUser.get(uid);
                Decimal u = usdByUser.get(uid);
                dto.estimatedUsd = u == null ? 0 : u.setScale(4);
                dto.costUsedFallback = fallbackByUser.get(uid) == true;
                dto.costConfidence = confidenceByUser.get(uid) == null
                    ? CostCalculatorService.CONFIDENCE_HIGH
                    : confidenceByUser.get(uid);
            }
        } catch (Exception costEx) {
            // Zeroes already set in DTO constructor — swallow to protect dashboard.
        }

        List<UserUsageDTO> results = dtoByUser.values();
        results.sort(new UserUsageByCountDesc());
        return results;
    }

    // ───────────────────────── Usage by Prompt ───────────────────

    /**
     * Server-side aggregate refactor (2026-04-29). Previously this method
     * pulled every request row in the range, grouped in Apex, and walked the
     * Request → Response → Generation → Feedback/Quality chain per prompt —
     * which on busy orgs hit the 50k SOQL limit. It now runs three bounded
     * aggregate queries (per prompt, per user-and-prompt, and one feedback
     * scan) plus one name-resolution call.
     *
     * Phase 2.2 update — acceptance attribution is now two-tier:
     *   - Top-N highest-volume prompts get a SAMPLED rate via a bounded
     *     Request → Response → Generation → Feedback chain walk
     *     (configurable via `FluentMetric_Cost_Settings__c.Top_N_Prompt_Acceptance_Sample__c`,
     *     default 25, sample size 500 requests per prompt). Hard ceiling
     *     keeps total SOQL ≤ 4N + dashboard overhead under the 100-query
     *     transaction limit.
     *   - Tail prompts (rank > N) keep the cheaper feature-correlation path
     *     and are tagged `acceptanceSource = 'CORRELATED'`.
     *   - Prompts with no clean attribution stay null with
     *     `acceptanceSource = null` so the LWC can render '—'.
     *
     * Compromises (v1 — see BUILD-LOG for rationale):
     *   - Per-prompt toxicFlagCount is left at 0. GenAIContentQuality__dlm
     *     has no prompt linkage and the full chain walk on every prompt is
     *     what triggered the original scale bug. Future work: narrower
     *     chain walk that piggybacks on the top-N sample.
     */
    public virtual List<PromptUsageDTO> getUsageByPrompt(DateRangeFilter filter) {
        validateFilter(filter);

        List<AggregateResult> promptAggs = dao.getRequestAggregatesByPrompt(filter.startDate, filter.endDate);
        if (promptAggs == null || promptAggs.isEmpty()) {
            return new List<PromptUsageDTO>();
        }

        // Seed per-prompt DTOs from aggregate rows — null/blank prompt dev names drop out
        Map<String, PromptUsageDTO> dtoByPrompt = new Map<String, PromptUsageDTO>();
        Map<String, String> promptToFeature = new Map<String, String>();
        for (AggregateResult a : promptAggs) {
            String pdn = (String) a.get('gkey');
            if (String.isBlank(pdn)) {
                continue;
            }
            PromptUsageDTO dto = new PromptUsageDTO();
            dto.promptDevName = pdn;
            dto.invocationCount = toInteger(a.get('cnt'));
            Long inputSum = toLong(a.get('pt'));
            Long outputSum = toLong(a.get('ct'));
            dto.totalTokens = toLong(a.get('tt'));
            dto.avgInputTokens = dto.invocationCount == 0 ? 0L : inputSum / dto.invocationCount;
            dto.avgOutputTokens = dto.invocationCount == 0 ? 0L : outputSum / dto.invocationCount;
            dto.firstUsed = (DateTime) a.get('minTs');
            dto.lastUsed = (DateTime) a.get('maxTs');
            // toxicFlagCount left at 0 — see method-level Compromises note.
            dto.toxicFlagCount = 0;
            // acceptanceRate null signals "not attributable" — LWC should render as '—'
            dto.acceptanceRate = null;
            dtoByPrompt.put(pdn, dto);
        }

        if (dtoByPrompt.isEmpty()) {
            return new List<PromptUsageDTO>();
        }

        // Per-prompt unique user counts — pivot the (user, prompt) aggregate in Apex
        try {
            List<AggregateResult> userPromptAggs = dao.getRequestAggregatesByUserAndPrompt(
                filter.startDate,
                filter.endDate
            );
            Map<String, Set<String>> usersByPrompt = new Map<String, Set<String>>();
            for (AggregateResult a : userPromptAggs) {
                String pdn = (String) a.get('pdn');
                if (String.isBlank(pdn) || !dtoByPrompt.containsKey(pdn)) {
                    continue;
                }
                String uid = (String) a.get('uid');
                if (uid == null) {
                    uid = SYSTEM_SENTINEL;
                }
                if (!usersByPrompt.containsKey(pdn)) {
                    usersByPrompt.put(pdn, new Set<String>());
                }
                usersByPrompt.get(pdn).add(uid);
            }
            for (String pdn : usersByPrompt.keySet()) {
                dtoByPrompt.get(pdn).uniqueUserCount = usersByPrompt.get(pdn).size();
            }
        } catch (Exception ex) {
            // Older APIs may reject multi-column GROUP BY — leave uniqueUserCount at 0
        }

        // Best-effort feature attribution per prompt: if a prompt has exactly one
        // feature, carry it and use it for best-effort feedback correlation.
        try {
            List<AggregateResult> featureAggs = dao.getRequestAggregatesByPromptAndFeature(
                filter.startDate,
                filter.endDate
            );
            Map<String, Set<String>> featuresByPrompt = new Map<String, Set<String>>();
            for (AggregateResult a : featureAggs) {
                String pdn = (String) a.get('pdn');
                String feat = (String) a.get('feat');
                if (String.isBlank(pdn) || !dtoByPrompt.containsKey(pdn)) {
                    continue;
                }
                if (!featuresByPrompt.containsKey(pdn)) {
                    featuresByPrompt.put(pdn, new Set<String>());
                }
                if (String.isNotBlank(feat)) {
                    featuresByPrompt.get(pdn).add(feat);
                }
            }
            for (String pdn : featuresByPrompt.keySet()) {
                Set<String> feats = featuresByPrompt.get(pdn);
                if (feats.size() == 1) {
                    String soleFeat = new List<String>(feats)[0];
                    dtoByPrompt.get(pdn).featureName = soleFeat;
                    promptToFeature.put(pdn, soleFeat);
                }
            }
        } catch (Exception ex) {
            // Feature attribution is optional — continue without it
        }

        // Best-effort per-prompt feedback via feature correlation. Prompts that
        // don't map cleanly to a single feature keep acceptanceRate = null.
        // Source = 'CORRELATED' until Phase 2.2's top-N pass overwrites it.
        if (!promptToFeature.isEmpty()) {
            try {
                Map<String, Integer> posByFeature = new Map<String, Integer>();
                Map<String, Integer> totalByFeature = new Map<String, Integer>();
                List<SObject> feedback = dao.getFeedbackForDateRange(filter.startDate, filter.endDate);
                for (SObject f : feedback) {
                    String feat = (String) f.get('feature__c');
                    if (String.isBlank(feat)) {
                        continue;
                    }
                    totalByFeature.put(feat, (totalByFeature.get(feat) == null ? 0 : totalByFeature.get(feat)) + 1);
                    if (isPositiveFeedback(f)) {
                        posByFeature.put(feat, (posByFeature.get(feat) == null ? 0 : posByFeature.get(feat)) + 1);
                    }
                }
                for (String pdn : promptToFeature.keySet()) {
                    String feat = promptToFeature.get(pdn);
                    Integer total = totalByFeature.get(feat) == null ? 0 : totalByFeature.get(feat);
                    if (total == 0) {
                        continue;
                    }
                    Integer pos = posByFeature.get(feat) == null ? 0 : posByFeature.get(feat);
                    PromptUsageDTO promptDto = dtoByPrompt.get(pdn);
                    promptDto.acceptanceRate = ((Decimal) pos / total).setScale(4);
                    promptDto.acceptanceSource = 'CORRELATED';
                }
            } catch (Exception ex) {
                // Leave acceptanceRate null if feedback scan failed
            }
        }

        // Phase 2.2 — bounded top-N chain walk. Sort prompts by invocation
        // count, take the top N, and walk Request → Response → Generation →
        // Feedback for each. SOQL budget: 4 calls × N prompts. With N=25
        // (default), that's ≤100 queries plus the dashboard's existing
        // overhead — well inside the per-transaction limit.
        Integer topN = readTopNPromptAcceptanceSample();
        if (topN > 0) {
            try {
                List<PromptUsageDTO> ranked = new List<PromptUsageDTO>(dtoByPrompt.values());
                ranked.sort(new PromptUsageByCountDesc());
                Integer cap = Math.min(topN, ranked.size());
                for (Integer i = 0; i < cap; i++) {
                    // Bail when the chain walk's 4 SOQL plus a 1-query buffer
                    // would breach the per-transaction limit. Preserves
                    // headroom for any caller that runs additional queries
                    // after getUsageByPrompt.
                    if (Limits.getLimitQueries() - Limits.getQueries() < 5) {
                        break;
                    }
                    PromptUsageDTO promptDto = ranked[i];
                    if (promptDto.invocationCount == null || promptDto.invocationCount == 0) {
                        continue;
                    }
                    Decimal rate = sampleAcceptanceForPrompt(promptDto.promptDevName, filter);
                    if (rate != null) {
                        promptDto.acceptanceRate = rate;
                        promptDto.acceptanceSource = 'SAMPLED';
                    }
                }
            } catch (Exception ex) {
                // Top-N walk best-effort — preserve whatever the correlation
                // pass produced rather than zeroing it out.
            }
        }

        // Resolve prompt labels
        Map<String, String> labels = resolver.resolvePromptTemplateLabels(dtoByPrompt.keySet());
        for (String pdn : dtoByPrompt.keySet()) {
            dtoByPrompt.get(pdn).promptLabel = labels.get(pdn) == null ? pdn : labels.get(pdn);
        }

        // Cost analytics (Phase 2.1) — true prompt×model aggregation. For each
        // (prompt, model) pair we ask CostCalculatorService for a CostResult,
        // sum FC + USD into the prompt's totals, and roll confidence down to
        // the weakest band seen across that prompt's models. If the
        // prompt×model DAO call throws or returns nothing, fall back to the
        // legacy single-call estimate so the dashboard never zeroes out.
        try {
            CostCalculatorService cost = new CostCalculatorService();
            List<AggregateResult> promptModelAggs = dao.getRequestAggregatesByPromptAndModel(
                filter.startDate,
                filter.endDate
            );
            Map<String, Long> fcByPrompt = new Map<String, Long>();
            Map<String, Decimal> usdByPrompt = new Map<String, Decimal>();
            Map<String, Boolean> fallbackByPrompt = new Map<String, Boolean>();
            Map<String, String> confidenceByPrompt = new Map<String, String>();
            Set<String> coveredPrompts = new Set<String>();
            if (promptModelAggs != null) {
                for (AggregateResult a : promptModelAggs) {
                    String pdn = (String) a.get('pdn');
                    if (String.isBlank(pdn) || !dtoByPrompt.containsKey(pdn)) {
                        continue;
                    }
                    String modelKey = (String) a.get('mdl');
                    Integer cnt = toInteger(a.get('cnt'));
                    Long tt = toLong(a.get('tt'));
                    CostCalculatorService.CostResult cr = cost.costForAggregate(modelKey, cnt, tt);
                    fcByPrompt.put(
                        pdn,
                        (fcByPrompt.get(pdn) == null ? 0L : fcByPrompt.get(pdn)) +
                        (cr.flexCredits == null ? 0L : cr.flexCredits)
                    );
                    usdByPrompt.put(
                        pdn,
                        (usdByPrompt.get(pdn) == null ? (Decimal) 0 : usdByPrompt.get(pdn)) +
                        (cr.discountedUsd == null ? (Decimal) 0 : cr.discountedUsd)
                    );
                    if (cr.usedFallback == true) {
                        fallbackByPrompt.put(pdn, true);
                    }
                    confidenceByPrompt.put(pdn, weakerConfidence(confidenceByPrompt.get(pdn), cr.confidence));
                    coveredPrompts.add(pdn);
                }
            }
            for (PromptUsageDTO dto : dtoByPrompt.values()) {
                if (coveredPrompts.contains(dto.promptDevName)) {
                    dto.estimatedFlexCredits = fcByPrompt.get(dto.promptDevName) == null
                        ? 0L
                        : fcByPrompt.get(dto.promptDevName);
                    Decimal u = usdByPrompt.get(dto.promptDevName);
                    dto.estimatedUsd = u == null ? 0 : u.setScale(4);
                    dto.costUsedFallback = fallbackByPrompt.get(dto.promptDevName) == true;
                    dto.costConfidence = confidenceByPrompt.get(dto.promptDevName) == null
                        ? CostCalculatorService.CONFIDENCE_HIGH
                        : confidenceByPrompt.get(dto.promptDevName);
                } else {
                    // Prompt not in prompt×model aggregate (rare — e.g. all
                    // requests had a null model). Single-call estimate.
                    CostCalculatorService.CostResult cr = cost.costForAggregate(
                        null,
                        dto.invocationCount,
                        dto.totalTokens
                    );
                    dto.estimatedFlexCredits = cr.flexCredits == null ? 0L : cr.flexCredits;
                    dto.estimatedUsd = cr.discountedUsd == null ? 0 : cr.discountedUsd.setScale(4);
                    dto.costUsedFallback = cr.usedFallback == true;
                    dto.costConfidence = cr.confidence == null ? CostCalculatorService.CONFIDENCE_HIGH : cr.confidence;
                }
            }
        } catch (Exception costEx) {
            // Swallow — zeros from constructor remain.
        }

        List<PromptUsageDTO> results = dtoByPrompt.values();
        results.sort(new PromptUsageByCountDesc());
        return results;
    }

    // ───────────────────────── Prompt Outputs ────────────────────

    public virtual List<PromptOutputDTO> getPromptOutputs(
        String promptDevName,
        DateRangeFilter filter,
        Integer limitCount
    ) {
        validateFilter(filter);
        if (String.isBlank(promptDevName)) {
            throw new IllegalArgumentException('promptDevName is required');
        }
        Integer effectiveLimit = (limitCount == null || limitCount <= 0) ? 25 : limitCount;

        List<SObject> requests = dao.getRequestsByPromptTemplate(promptDevName, filter.startDate, filter.endDate);
        if (requests.isEmpty()) {
            return new List<PromptOutputDTO>();
        }

        Set<String> requestIds = collectBusinessKeys(requests, 'gatewayRequestId__c');
        List<SObject> responses = requestIds.isEmpty() ? new List<SObject>() : dao.getResponsesForRequests(requestIds);
        Map<String, String> responseToRequest = new Map<String, String>();
        for (SObject resp : responses) {
            responseToRequest.put(
                (String) resp.get('generationResponseId__c'),
                (String) resp.get('generationRequestId__c')
            );
        }
        Set<String> responseIds = responseToRequest.keySet();
        List<SObject> generations = responseIds.isEmpty()
            ? new List<SObject>()
            : dao.getGenerationsForResponses(responseIds);
        Map<String, String> generationToRequest = new Map<String, String>();
        Map<String, SObject> generationById = new Map<String, SObject>();
        for (SObject g : generations) {
            String genId = (String) g.get('generationId__c');
            String respId = (String) g.get('generationResponseId__c');
            String reqId = responseToRequest.get(respId);
            if (reqId != null && genId != null) {
                generationToRequest.put(genId, reqId);
                generationById.put(genId, g);
            }
        }

        Set<String> generationIds = generationById.keySet();
        Map<String, SObject> feedbackByGenId = new Map<String, SObject>();
        if (!generationIds.isEmpty()) {
            for (SObject f : dao.getFeedbackForGenerations(generationIds)) {
                feedbackByGenId.put((String) f.get('generationId__c'), f);
            }
        }
        Map<String, Boolean> toxicByGenId = new Map<String, Boolean>();
        if (!generationIds.isEmpty()) {
            for (SObject q : dao.getContentQualityForGenerations(generationIds)) {
                String genId = (String) q.get('parent__c');
                if (genId == null) {
                    continue;
                }
                Boolean isTox = parseBool(q.get('isToxicityDetected__c'));
                if (isTox || !toxicByGenId.containsKey(genId)) {
                    toxicByGenId.put(genId, isTox);
                }
            }
        }

        // Resolve user names for all requests
        Set<String> userIds = new Set<String>();
        Map<String, SObject> requestByKey = new Map<String, SObject>();
        for (SObject r : requests) {
            String rid = (String) r.get('gatewayRequestId__c');
            if (rid != null) {
                requestByKey.put(rid, r);
            }
            String uid = (String) r.get('userId__c');
            if (String.isNotBlank(uid)) {
                userIds.add(uid);
            }
        }
        Map<String, String> userNames = resolver.resolveUserNames(userIds);

        List<PromptOutputDTO> outputs = new List<PromptOutputDTO>();
        for (String genId : generationToRequest.keySet()) {
            String reqId = generationToRequest.get(genId);
            SObject req = requestByKey.get(reqId);
            if (req == null) {
                continue;
            }
            SObject gen = generationById.get(genId);
            PromptOutputDTO o = new PromptOutputDTO();
            o.requestId = reqId;
            String uid = (String) req.get('userId__c');
            o.userName = userNames.get(uid) == null ? uid : userNames.get(uid);
            o.requestDate = (DateTime) req.get('timestamp__c');
            String rawPrompt = (String) req.get('prompt__c');
            String rawGenerated = gen == null ? null : (String) gen.get('responseText__c');
            o.inputPrompt = truncate(rawPrompt, OUTPUT_TRUNCATE_LEN);
            o.generatedText = truncate(rawGenerated, OUTPUT_TRUNCATE_LEN);
            o.inputPromptFull = rawPrompt;
            o.generatedTextFull = rawGenerated;
            o.model = (String) req.get('model__c');
            o.inputTokens = toInteger(req.get('promptTokens__c'));
            o.outputTokens = toInteger(req.get('completionTokens__c'));
            SObject fb = feedbackByGenId.get(genId);
            o.feedbackValue = fb == null ? null : (String) fb.get('feedback__c');
            Boolean tox = toxicByGenId.get(genId);
            o.isToxic = tox == null ? false : tox;
            outputs.add(o);
        }

        // Sort by requestDate DESC and apply limit
        outputs.sort(new PromptOutputByDateDesc());
        if (outputs.size() > effectiveLimit) {
            List<PromptOutputDTO> trimmed = new List<PromptOutputDTO>();
            for (Integer i = 0; i < effectiveLimit; i++) {
                trimmed.add(outputs[i]);
            }
            return trimmed;
        }
        return outputs;
    }

    // ───────────────────────── Entity Details (drill-in) ─────────

    /**
     * Cross-cutting entity drill-in. Every dashboard table row in the app can
     * call this with the row's `entityType` + `entityKey` to get an aggregate
     * header and the most recent raw requests for that entity. The return
     * shape is unified so the LWC drawer renders the same way regardless of
     * whether the user drilled in from Users, Prompts, Tokens, Safety, or
     * Explorer.
     *
     * Aggregate stats are derived by post-filtering the existing `*Aggregate*`
     * DAO rows in Apex. This is safe because the aggregate DAO already caps
     * row count at "one row per distinct group", not per raw request, so the
     * walk is O(groups) not O(requests).
     *
     * Recent requests are pulled with the narrow (LIMIT 500) DAO methods,
     * capped at min(recentLimit, 20) since the LWC panel doesn't render more.
     * Feedback + toxicity rollups are then computed over just that bounded
     * generation set — fast and scale-safe.
     *
     * Entity-type routing:
     *   "User"          → getRecentRequestsByUser + user-scoped aggregates
     *   "PromptTemplate" → getRecentRequestsByPromptTemplate + prompt-scoped aggregates
     *   "Model"         → getRequestsByModel + model-scoped aggregates
     *   "Feature"       → getRequestsByFeature + feature-scoped aggregates
     * Anything else throws IllegalArgumentException.
     */
    public virtual EntityDetailsDTO getEntityDetails(
        String entityType,
        String entityKey,
        DateRangeFilter filter,
        Integer recentLimit
    ) {
        return getEntityDetails(entityType, entityKey, filter, recentLimit, null);
    }

    public virtual EntityDetailsDTO getEntityDetails(
        String entityType,
        String entityKey,
        DateRangeFilter filter,
        Integer recentLimit,
        FilterCriteria criteria
    ) {
        validateFilter(filter);
        if (String.isBlank(entityType)) {
            throw new IllegalArgumentException('entityType is required');
        }
        if (String.isBlank(entityKey)) {
            throw new IllegalArgumentException('entityKey is required');
        }

        String normalizedType = entityType.toLowerCase();
        Integer effectiveLimit = (recentLimit == null || recentLimit <= 0) ? 20 : Math.min(recentLimit, 20);

        EntityDetailsDTO out = new EntityDetailsDTO();
        out.entityType = entityType;
        out.entityKey = entityKey;

        // ── Aggregate header — post-filter the per-dimension aggregate rows ──
        AggregateResult matched = findMatchingAggregate(normalizedType, entityKey, filter, criteria);
        if (matched != null) {
            out.requestCount = toInteger(matched.get('cnt'));
            out.totalInputTokens = toLong(matched.get('pt'));
            out.totalOutputTokens = toLong(matched.get('ct'));
            out.totalTokens = toLong(matched.get('tt'));
            out.firstUsed = (DateTime) matched.get('minTs');
            out.lastUsed = (DateTime) matched.get('maxTs');
            out.avgTokensPerRequest = out.requestCount == 0
                ? 0
                : ((Decimal) out.totalTokens / out.requestCount).setScale(2);
        }

        // Unique-user / unique-prompt counts via the user×prompt pivot aggregate
        populateEntityUniqueCounts(out, normalizedType, entityKey, filter, criteria);

        // ── Recent requests (bounded) ──────────────────────────────────────
        List<SObject> recentRows = fetchRecentRequestsForEntity(
            normalizedType,
            entityKey,
            filter,
            effectiveLimit,
            criteria
        );
        if (!recentRows.isEmpty()) {
            out.recentRequests = hydrateRecentRequests(recentRows, effectiveLimit);
        }

        // ── Feedback + toxicity over the recent generation set ─────────────
        populateEntityFeedbackAndToxicity(out);

        // ── Entity label resolution ────────────────────────────────────────
        out.entityLabel = resolveEntityLabel(normalizedType, entityKey);

        // Cost analytics (Phase 3.5) — exact model match for Model entity,
        // Standard-tier fallback for everything else in v1.
        try {
            CostCalculatorService cost = new CostCalculatorService();
            String modelKey = normalizedType == 'model' ? entityKey : null;
            CostCalculatorService.CostResult cr = cost.costForAggregate(modelKey, out.requestCount, out.totalTokens);
            out.estimatedFlexCredits = cr.flexCredits == null ? 0L : cr.flexCredits;
            out.estimatedUsd = cr.discountedUsd == null ? 0 : cr.discountedUsd.setScale(4);
            out.costUsedFallback = cr.usedFallback == true;
            out.costConfidence = cr.confidence == null ? CostCalculatorService.CONFIDENCE_HIGH : cr.confidence;
        } catch (Exception costEx) {
            // DTO constructor zeroes remain.
        }

        return out;
    }

    /**
     * Post-filter the per-dimension aggregate DAO rows to find the single
     * aggregate matching `entityKey`. Returns null if no match — callers
     * handle that by leaving the aggregate header at its zero defaults.
     */
    @TestVisible
    private AggregateResult findMatchingAggregate(
        String normalizedType,
        String entityKey,
        DateRangeFilter filter,
        FilterCriteria criteria
    ) {
        // When dimension filters are active, run a targeted aggregate query
        // scoped to the entity anchor + the active filter dimensions so the
        // KPI header reflects the filtered subset, not the full entity window.
        if (criteria != null && hasDimensionFilters(criteria) && normalizedType != 'timebucket') {
            String anchorField = anchorFieldForType(normalizedType);
            if (anchorField != null) {
                try {
                    return dao.getRequestAggregateForEntity(normalizeCriteria(criteria), anchorField, entityKey);
                } catch (Exception e) {
                    return null;
                }
            }
        }
        List<AggregateResult> aggs;
        try {
            if (normalizedType == 'user') {
                aggs = dao.getRequestAggregatesByUser(filter.startDate, filter.endDate);
            } else if (normalizedType == 'prompttemplate') {
                aggs = dao.getRequestAggregatesByPrompt(filter.startDate, filter.endDate);
            } else if (normalizedType == 'model') {
                aggs = dao.getRequestAggregatesByModel(filter.startDate, filter.endDate);
            } else if (normalizedType == 'feature') {
                aggs = dao.getRequestAggregatesByFeature(filter.startDate, filter.endDate);
            } else if (normalizedType == 'timebucket') {
                // Day / Week drill-in — the filter IS the bucket. Just grab
                // the overall totals in the passed range.
                AggregateResult totals = dao.getRequestTotals(filter.startDate, filter.endDate);
                return totals;
            } else {
                throw new IllegalArgumentException('Unsupported entityType: ' + normalizedType);
            }
        } catch (IllegalArgumentException iae) {
            throw iae;
        } catch (Exception e) {
            return null;
        }
        if (aggs == null) {
            return null;
        }
        for (AggregateResult a : aggs) {
            String gkey = (String) a.get('gkey');
            // For User the null/blank aggregate key maps to the NOT_SET sentinel
            if (gkey == null && normalizedType == 'user') {
                gkey = SYSTEM_SENTINEL;
            }
            if (entityKey.equals(gkey)) {
                return a;
            }
        }
        return null;
    }

    /**
     * Fill `uniqueUserCount` / `uniquePromptCount` on the DTO using the
     * user×prompt pivot aggregate. Each entity type only surfaces the count
     * that actually varies — the other is left null so the LWC can hide it.
     */
    @TestVisible
    private void populateEntityUniqueCounts(
        EntityDetailsDTO out,
        String normalizedType,
        String entityKey,
        DateRangeFilter filter,
        FilterCriteria criteria
    ) {
        try {
            // When dimension filters are active, use the targeted DAO method that
            // groups by the related field within the filter-scoped anchor set.
            // Row count = distinct related-entity count in the filtered subset.
            if (criteria != null && hasDimensionFilters(criteria) && normalizedType != 'timebucket') {
                String anchorField = anchorFieldForType(normalizedType);
                if (anchorField != null) {
                    String countField = (normalizedType == 'user') ? 'promptTemplateDevName__c' : 'userId__c';
                    List<AggregateResult> rows = dao.getRelatedEntityAggregates(
                        normalizeCriteria(criteria),
                        anchorField,
                        entityKey,
                        countField
                    );
                    if (normalizedType == 'user') {
                        out.uniquePromptCount = rows.size();
                    } else {
                        out.uniqueUserCount = rows.size();
                    }
                    return;
                }
            }
            if (normalizedType == 'user') {
                // For a user drill-in, count the distinct prompts that user used
                List<AggregateResult> userPromptAggs = dao.getRequestAggregatesByUserAndPrompt(
                    filter.startDate,
                    filter.endDate
                );
                Set<String> prompts = new Set<String>();
                for (AggregateResult a : userPromptAggs) {
                    String uid = (String) a.get('uid');
                    if (uid == null) {
                        uid = SYSTEM_SENTINEL;
                    }
                    if (!entityKey.equals(uid)) {
                        continue;
                    }
                    String pdn = (String) a.get('pdn');
                    if (String.isNotBlank(pdn)) {
                        prompts.add(pdn);
                    }
                }
                out.uniquePromptCount = prompts.size();
            } else if (normalizedType == 'prompttemplate') {
                List<AggregateResult> userPromptAggs = dao.getRequestAggregatesByUserAndPrompt(
                    filter.startDate,
                    filter.endDate
                );
                Set<String> users = new Set<String>();
                for (AggregateResult a : userPromptAggs) {
                    String pdn = (String) a.get('pdn');
                    if (!entityKey.equals(pdn)) {
                        continue;
                    }
                    String uid = (String) a.get('uid');
                    if (uid == null) {
                        uid = SYSTEM_SENTINEL;
                    }
                    users.add(uid);
                }
                out.uniqueUserCount = users.size();
            } else if (normalizedType == 'model') {
                List<AggregateResult> userModelAggs = dao.getRequestAggregatesByUserAndModel(
                    filter.startDate,
                    filter.endDate
                );
                Set<String> users = new Set<String>();
                for (AggregateResult a : userModelAggs) {
                    String modelKey = (String) a.get('pdn');
                    if (!entityKey.equals(modelKey)) {
                        continue;
                    }
                    String uid = (String) a.get('uid');
                    if (uid == null) {
                        uid = SYSTEM_SENTINEL;
                    }
                    users.add(uid);
                }
                out.uniqueUserCount = users.size();
            } else if (normalizedType == 'feature') {
                List<AggregateResult> userFeatureAggs = dao.getRequestAggregatesByUserAndFeature(
                    filter.startDate,
                    filter.endDate
                );
                Set<String> users = new Set<String>();
                for (AggregateResult a : userFeatureAggs) {
                    String featureKey = (String) a.get('pdn');
                    if (!entityKey.equals(featureKey)) {
                        continue;
                    }
                    String uid = (String) a.get('uid');
                    if (uid == null) {
                        uid = SYSTEM_SENTINEL;
                    }
                    users.add(uid);
                }
                out.uniqueUserCount = users.size();
            }
        } catch (Exception e) {
            // Unique counts are supplementary — leave null on failure
        }
    }

    @TestVisible
    private List<SObject> fetchRecentRequestsForEntity(
        String normalizedType,
        String entityKey,
        DateRangeFilter filter,
        Integer effectiveLimit
    ) {
        return fetchRecentRequestsForEntity(normalizedType, entityKey, filter, effectiveLimit, null);
    }

    @TestVisible
    private List<SObject> fetchRecentRequestsForEntity(
        String normalizedType,
        String entityKey,
        DateRangeFilter filter,
        Integer effectiveLimit,
        FilterCriteria criteria
    ) {
        // When dimension filters are active, use the criteria-aware DAO path
        // so the recent-request list honours the same model/feature/user
        // selections the user set in the filter rail.
        if (criteria != null && hasDimensionFilters(criteria) && normalizedType != 'timebucket') {
            String anchorField = anchorFieldForType(normalizedType);
            if (anchorField != null) {
                FilterCriteria fullCriteria = normalizeCriteria(criteria);
                return dao.getRecentRequestsWithCriteria(fullCriteria, anchorField, entityKey, effectiveLimit);
            }
        }
        try {
            if (normalizedType == 'user') {
                return dao.getRecentRequestsByUser(entityKey, filter.startDate, filter.endDate, effectiveLimit);
            } else if (normalizedType == 'prompttemplate') {
                return dao.getRecentRequestsByPromptTemplate(
                    entityKey,
                    filter.startDate,
                    filter.endDate,
                    effectiveLimit
                );
            } else if (normalizedType == 'model') {
                return dao.getRequestsByModel(entityKey, filter.startDate, filter.endDate, effectiveLimit);
            } else if (normalizedType == 'feature') {
                return dao.getRequestsByFeature(entityKey, filter.startDate, filter.endDate, effectiveLimit);
            } else if (normalizedType == 'timebucket') {
                // Fetch the most-recent requests in the bucket. dao.getRequestsByDateRange
                // already caps at LIMIT 50000 and orders DESC by timestamp —
                // slice to effectiveLimit after retrieval to keep the drill
                // view bounded.
                List<SObject> all = dao.getRequestsByDateRange(filter.startDate, filter.endDate);
                if (all.size() <= effectiveLimit) {
                    return all;
                }
                List<SObject> capped = new List<SObject>();
                for (Integer i = 0; i < effectiveLimit; i++) {
                    capped.add(all[i]);
                }
                return capped;
            }
            throw new IllegalArgumentException('Unsupported entityType: ' + normalizedType);
        } catch (IllegalArgumentException iae) {
            throw iae;
        } catch (Exception e) {
            return new List<SObject>();
        }
    }

    /**
     * Walk Request → Response → Generation for the bounded request list,
     * hydrate each into a `PromptOutputDTO`, cap at `effectiveLimit`.
     * Mirrors `getPromptOutputs` but scoped to the already-narrow request set.
     */
    @TestVisible
    private List<PromptOutputDTO> hydrateRecentRequests(List<SObject> requests, Integer effectiveLimit) {
        if (requests == null || requests.isEmpty()) {
            return new List<PromptOutputDTO>();
        }

        Set<String> requestIds = collectBusinessKeys(requests, 'gatewayRequestId__c');
        List<SObject> responses = requestIds.isEmpty() ? new List<SObject>() : dao.getResponsesForRequests(requestIds);
        Map<String, String> responseToRequest = new Map<String, String>();
        for (SObject resp : responses) {
            responseToRequest.put(
                (String) resp.get('generationResponseId__c'),
                (String) resp.get('generationRequestId__c')
            );
        }
        Set<String> responseIds = responseToRequest.keySet();
        List<SObject> generations = responseIds.isEmpty()
            ? new List<SObject>()
            : dao.getGenerationsForResponses(responseIds);
        Map<String, String> generationToRequest = new Map<String, String>();
        Map<String, SObject> generationById = new Map<String, SObject>();
        for (SObject g : generations) {
            String genId = (String) g.get('generationId__c');
            String respId = (String) g.get('generationResponseId__c');
            String reqId = responseToRequest.get(respId);
            if (reqId != null && genId != null) {
                generationToRequest.put(genId, reqId);
                generationById.put(genId, g);
            }
        }

        Set<String> generationIds = generationById.keySet();
        Map<String, SObject> feedbackByGenId = new Map<String, SObject>();
        if (!generationIds.isEmpty()) {
            for (SObject f : dao.getFeedbackForGenerations(generationIds)) {
                feedbackByGenId.put((String) f.get('generationId__c'), f);
            }
        }
        Map<String, Boolean> toxicByGenId = new Map<String, Boolean>();
        if (!generationIds.isEmpty()) {
            for (SObject q : dao.getContentQualityForGenerations(generationIds)) {
                String genId = (String) q.get('parent__c');
                if (genId == null) {
                    continue;
                }
                Boolean isTox = parseBool(q.get('isToxicityDetected__c'));
                if (isTox || !toxicByGenId.containsKey(genId)) {
                    toxicByGenId.put(genId, isTox);
                }
            }
        }

        // Resolve user names for all requests in the set
        Set<String> userIds = new Set<String>();
        Map<String, SObject> requestByKey = new Map<String, SObject>();
        for (SObject r : requests) {
            String rid = (String) r.get('gatewayRequestId__c');
            if (rid != null) {
                requestByKey.put(rid, r);
            }
            String uid = (String) r.get('userId__c');
            if (String.isNotBlank(uid)) {
                userIds.add(uid);
            }
        }
        Map<String, String> userNames = userIds.isEmpty()
            ? new Map<String, String>()
            : resolver.resolveUserNames(userIds);

        List<PromptOutputDTO> outputs = new List<PromptOutputDTO>();
        // If there are requests without a matching generation (no response yet)
        // we still surface them — the drill-in is about "what did this entity
        // do", not "what did the LLM generate". Missing generation text renders
        // as null in the DTO.
        Set<String> hydratedRequestIds = new Set<String>();
        for (String genId : generationToRequest.keySet()) {
            String reqId = generationToRequest.get(genId);
            SObject req = requestByKey.get(reqId);
            if (req == null) {
                continue;
            }
            hydratedRequestIds.add(reqId);
            SObject gen = generationById.get(genId);
            outputs.add(buildPromptOutputDto(req, gen, userNames, feedbackByGenId.get(genId), toxicByGenId.get(genId)));
        }
        // Add request-only rows (no generation yet) so the drill-in isn't empty
        // just because the response chain hasn't landed.
        for (SObject req : requests) {
            String rid = (String) req.get('gatewayRequestId__c');
            if (rid != null && !hydratedRequestIds.contains(rid)) {
                outputs.add(buildPromptOutputDto(req, null, userNames, null, null));
            }
        }

        outputs.sort(new PromptOutputByDateDesc());
        if (outputs.size() > effectiveLimit) {
            List<PromptOutputDTO> trimmed = new List<PromptOutputDTO>();
            for (Integer i = 0; i < effectiveLimit; i++) {
                trimmed.add(outputs[i]);
            }
            return trimmed;
        }
        return outputs;
    }

    @TestVisible
    private PromptOutputDTO buildPromptOutputDto(
        SObject req,
        SObject gen,
        Map<String, String> userNames,
        SObject feedback,
        Boolean isToxic
    ) {
        PromptOutputDTO o = new PromptOutputDTO();
        o.requestId = (String) req.get('gatewayRequestId__c');
        String uid = (String) req.get('userId__c');
        o.userName = userNames != null && userNames.get(uid) != null ? userNames.get(uid) : uid;
        o.requestDate = (DateTime) req.get('timestamp__c');
        String rawPrompt = (String) req.get('prompt__c');
        String rawGenerated = gen == null ? null : (String) gen.get('responseText__c');
        o.inputPrompt = truncate(rawPrompt, OUTPUT_TRUNCATE_LEN);
        o.generatedText = truncate(rawGenerated, OUTPUT_TRUNCATE_LEN);
        o.inputPromptFull = rawPrompt;
        o.generatedTextFull = rawGenerated;
        o.model = (String) req.get('model__c');
        o.inputTokens = toInteger(req.get('promptTokens__c'));
        o.outputTokens = toInteger(req.get('completionTokens__c'));
        o.feedbackValue = feedback == null ? null : (String) feedback.get('feedback__c');
        o.isToxic = isToxic == null ? false : isToxic;
        return o;
    }

    /**
     * Roll up positive/negative feedback and toxicity from the bounded
     * generation set already captured in `recentRequests`. The LWC-visible
     * counts are intentionally "best effort over the recent N" — not
     * global for the entity over the date range. This keeps the query cost
     * O(N) and fast, and the LWC labels the metrics accordingly.
     */
    @TestVisible
    private void populateEntityFeedbackAndToxicity(EntityDetailsDTO out) {
        Integer pos = 0;
        Integer neg = 0;
        Integer tox = 0;
        for (PromptOutputDTO o : out.recentRequests) {
            if (o.isToxic == true) {
                tox++;
            }
            if (String.isNotBlank(o.feedbackValue)) {
                String fv = o.feedbackValue.toLowerCase();
                if (fv == FEEDBACK_POSITIVE_THUMBS_UP || fv == FEEDBACK_POSITIVE_ACCEPTED) {
                    pos++;
                } else if (fv == FEEDBACK_NEGATIVE_THUMBS_DOWN || fv == FEEDBACK_NEGATIVE_REJECTED) {
                    neg++;
                }
            }
        }
        out.positiveFeedbackCount = pos;
        out.negativeFeedbackCount = neg;
        out.toxicFlagCount = tox;
        Integer total = pos + neg;
        // null acceptanceRate signals "no feedback in scope" → LWC renders "—"
        out.acceptanceRate = total == 0 ? null : ((Decimal) pos / total).setScale(4);
    }

    @TestVisible
    private String resolveEntityLabel(String normalizedType, String entityKey) {
        try {
            if (normalizedType == 'user') {
                Map<String, String> names = resolver.resolveUserNames(new Set<String>{ entityKey });
                return names.get(entityKey) == null ? entityKey : names.get(entityKey);
            } else if (normalizedType == 'prompttemplate') {
                Map<String, String> labels = resolver.resolvePromptTemplateLabels(new Set<String>{ entityKey });
                return labels.get(entityKey) == null ? entityKey : labels.get(entityKey);
            }
        } catch (Exception e) {
            // Fall through to raw key
        }
        // Model / Feature have no resolver — the raw key IS the label
        return entityKey;
    }

    // ───────────────────────── Token Consumption ─────────────────

    /**
     * Server-side aggregate refactor (2026-04-29).
     *
     * For `user`, `prompt`, and `model` groupings the method dispatches to a
     * DAO aggregate — one row per group, no raw rows pulled, scales to any
     * org volume. For `day` and `week` groupings the DMO SOQL grammar lacks
     * DATE() / CALENDAR_WEEK() functions, so we fall back to scanning raw
     * request rows. To stay within the 50k-row governor the service enforces
     * a maximum range: 31 days for `day`, 12 weeks (≈84 days) for `week`.
     * Callers asking for a wider window get an IllegalArgumentException.
     */
    public virtual List<TokenConsumptionDTO> getTokenConsumption(DateRangeFilter filter, String groupBy) {
        validateFilter(filter);
        if (String.isBlank(groupBy)) {
            throw new IllegalArgumentException('groupBy is required');
        }
        String normalizedGroupBy = groupBy.toLowerCase();

        Map<String, TokenConsumptionDTO> byKey = new Map<String, TokenConsumptionDTO>();

        if (normalizedGroupBy == 'user') {
            for (AggregateResult a : dao.getRequestAggregatesByUser(filter.startDate, filter.endDate)) {
                String key = (String) a.get('gkey');
                if (key == null) {
                    key = SYSTEM_SENTINEL;
                }
                byKey.put(key, aggregateToTokenDto(key, a));
            }
        } else if (normalizedGroupBy == 'prompt') {
            for (AggregateResult a : dao.getRequestAggregatesByPrompt(filter.startDate, filter.endDate)) {
                String key = (String) a.get('gkey');
                if (String.isBlank(key)) {
                    continue;
                }
                byKey.put(key, aggregateToTokenDto(key, a));
            }
        } else if (normalizedGroupBy == 'model') {
            for (AggregateResult a : dao.getRequestAggregatesByModel(filter.startDate, filter.endDate)) {
                String key = (String) a.get('gkey');
                if (String.isBlank(key)) {
                    continue;
                }
                byKey.put(key, aggregateToTokenDto(key, a));
            }
        } else if (normalizedGroupBy == 'day' || normalizedGroupBy == 'week') {
            // Raw-row fallback with enforced range ceiling — see method JavaDoc.
            Integer maxDays = normalizedGroupBy == 'day' ? 31 : 84;
            Long spanDays = (filter.endDate.getTime() - filter.startDate.getTime()) / (1000L * 60L * 60L * 24L);
            if (spanDays > maxDays) {
                throw new IllegalArgumentException(
                    'Date range too wide for ' + groupBy + ' grouping. Max ' + maxDays + ' days.'
                );
            }
            // DMO SOQL doesn't support DATE()/CALENDAR_WEEK() aggregate grouping.
            // Instead, fan out one COUNT+SUM aggregate query per bucket using
            // `getRequestTotals(start, end)`. Each per-bucket query returns a
            // single AggregateResult row — cheap and scale-safe.
            Integer bucketSizeDays = (normalizedGroupBy == 'day') ? 1 : 7;
            DateTime bucketStart = filter.startDate;
            Integer bucketIndex = 0;
            while (bucketStart < filter.endDate && bucketIndex < 100) {
                DateTime bucketEnd = bucketStart.addDays(bucketSizeDays);
                if (bucketEnd > filter.endDate) {
                    bucketEnd = filter.endDate;
                }
                AggregateResult bucketTotals = dao.getRequestTotals(bucketStart, bucketEnd);
                if (bucketTotals != null && toInteger(bucketTotals.get('cnt')) > 0) {
                    String key = formatBucketKey(bucketStart, normalizedGroupBy);
                    TokenConsumptionDTO dto = new TokenConsumptionDTO();
                    dto.groupKey = key;
                    dto.groupLabel = key;
                    dto.inputTokens = toLong(bucketTotals.get('pt'));
                    dto.outputTokens = toLong(bucketTotals.get('ct'));
                    dto.totalTokens = toLong(bucketTotals.get('tt'));
                    dto.requestCount = toInteger(bucketTotals.get('cnt'));
                    if (dto.requestCount > 0) {
                        dto.avgTokensPerRequest = ((Decimal) dto.totalTokens / dto.requestCount).setScale(1);
                    }
                    byKey.put(key, dto);
                }
                bucketStart = bucketEnd;
                bucketIndex++;
            }
        } else {
            throw new IllegalArgumentException('Unsupported groupBy: ' + groupBy);
        }

        if (byKey.isEmpty()) {
            return new List<TokenConsumptionDTO>();
        }

        // Resolve group labels
        Map<String, String> labelMap = resolveGroupLabels(byKey.keySet(), normalizedGroupBy);
        for (TokenConsumptionDTO dto : byKey.values()) {
            dto.groupLabel = labelMap.containsKey(dto.groupKey) ? labelMap.get(dto.groupKey) : dto.groupKey;
            dto.avgTokensPerRequest = dto.requestCount == 0
                ? 0
                : ((Decimal) dto.totalTokens / dto.requestCount).setScale(2);
        }

        // Cost analytics (Phase 3.5) — exact match for model grouping, fallback for everything else in v1.
        try {
            CostCalculatorService cost = new CostCalculatorService();
            for (TokenConsumptionDTO dto : byKey.values()) {
                String modelKey = normalizedGroupBy == 'model' ? dto.groupKey : null;
                CostCalculatorService.CostResult cr = cost.costForAggregate(
                    modelKey,
                    dto.requestCount,
                    dto.totalTokens
                );
                dto.estimatedUsd = cr.discountedUsd == null ? 0 : cr.discountedUsd.setScale(4);
                dto.costUsedFallback = cr.usedFallback == true;
                dto.costConfidence = cr.confidence == null ? CostCalculatorService.CONFIDENCE_HIGH : cr.confidence;
            }
        } catch (Exception costEx) {
            // Zeros from DTO constructor remain.
        }

        List<TokenConsumptionDTO> rows = new List<TokenConsumptionDTO>(byKey.values());
        rows.sort(new TokenByTotalDesc());

        // Top 10 + "Others" bucket
        if (rows.size() <= TOP_N_DEFAULT) {
            return rows;
        }
        List<TokenConsumptionDTO> trimmed = new List<TokenConsumptionDTO>();
        for (Integer i = 0; i < TOP_N_DEFAULT; i++) {
            trimmed.add(rows[i]);
        }
        TokenConsumptionDTO others = new TokenConsumptionDTO();
        others.groupKey = '__others__';
        others.groupLabel = 'Others';
        for (Integer i = TOP_N_DEFAULT; i < rows.size(); i++) {
            others.inputTokens += rows[i].inputTokens;
            others.outputTokens += rows[i].outputTokens;
            others.totalTokens += rows[i].totalTokens;
            others.requestCount += rows[i].requestCount;
            others.estimatedUsd += rows[i].estimatedUsd == null ? 0 : rows[i].estimatedUsd;
            if (rows[i].costUsedFallback == true) {
                others.costUsedFallback = true;
            }
        }
        others.avgTokensPerRequest = others.requestCount == 0
            ? 0
            : ((Decimal) others.totalTokens / others.requestCount).setScale(2);
        trimmed.add(others);
        return trimmed;
    }

    /** Seed a TokenConsumptionDTO from a request aggregate row. */
    private static TokenConsumptionDTO aggregateToTokenDto(String groupKey, AggregateResult a) {
        TokenConsumptionDTO dto = new TokenConsumptionDTO();
        dto.groupKey = groupKey;
        dto.inputTokens = toLong(a.get('pt'));
        dto.outputTokens = toLong(a.get('ct'));
        dto.totalTokens = toLong(a.get('tt'));
        dto.requestCount = toInteger(a.get('cnt'));
        return dto;
    }

    // ───────────────────────── Cost Consumption ──────────────────
    //
    // Powers the Tableau Edition's GetCostBreakdownAction (v1.1). Returns a
    // per-group cost breakdown so the agent can answer "how much did this
    // cost" / "spend by model". Each row carries the same confidence / source
    // bands users see on the Lightning Overview tile.
    //
    // Pricing path:
    //   1. For each group row, ask CostCalculatorService.costForAggregate(...)
    //      using the model name when grouping by model, or null otherwise (the
    //      null-model path falls back to the Standard tier — same policy used
    //      by getTokenConsumption / runExplorer).
    //   2. After the per-row tier estimate is built, probe the Wallet via
    //      CostCalculatorService.costForWindow(). When Wallet returns ACTUAL
    //      Flex Credits, redistribute the wallet total proportionally by each
    //      row's tier-rate FC share and stamp every row with confidence=ACTUAL
    //      and source=ACTUAL_WALLET. If Wallet is unavailable or returns 0,
    //      leave the per-row tier estimates as-is.
    //
    // Supported groupBy values: model | user | prompt | feature. Anything else
    // (including null/blank) defaults to model.

    public virtual List<CostBreakdownDTO> getCostConsumption(DateRangeFilter filter, String groupBy) {
        validateFilter(filter);
        String normalized = String.isBlank(groupBy) ? 'model' : groupBy.toLowerCase();
        if (normalized != 'model' && normalized != 'user' && normalized != 'prompt' && normalized != 'feature') {
            normalized = 'model';
        }

        // Step 1 — gather per-group aggregates from the appropriate DAO
        // method. We don't fan out a per-row+per-model breakdown here (that's
        // what getOverview / getUsageByUser do); for cost-by-user the agent
        // wants a single number per user, so we approximate by passing each
        // user's totalTokens to the null-model path. Same pattern as
        // runExplorer's TotalCost metric.
        List<AggregateResult> aggs;
        try {
            if (normalized == 'model') {
                aggs = dao.getRequestAggregatesByModel(filter.startDate, filter.endDate);
            } else if (normalized == 'user') {
                aggs = dao.getRequestAggregatesByUser(filter.startDate, filter.endDate);
            } else if (normalized == 'prompt') {
                aggs = dao.getRequestAggregatesByPrompt(filter.startDate, filter.endDate);
            } else {
                aggs = dao.getRequestAggregatesByFeature(filter.startDate, filter.endDate);
            }
        } catch (Exception ex) {
            return new List<CostBreakdownDTO>();
        }
        if (aggs == null || aggs.isEmpty()) {
            return new List<CostBreakdownDTO>();
        }

        CostCalculatorService cost = new CostCalculatorService();
        List<CostBreakdownDTO> rows = new List<CostBreakdownDTO>();
        Set<String> labelKeys = new Set<String>();
        Long totalTierFc = 0L;
        Integer totalRequestCount = 0;

        for (AggregateResult a : aggs) {
            String gkey = (String) a.get('gkey');
            if (String.isBlank(gkey)) {
                if (normalized == 'user') {
                    gkey = SYSTEM_SENTINEL;
                } else {
                    continue;
                }
            }
            Integer cnt = toInteger(a.get('cnt'));
            Long tt = toLong(a.get('tt'));
            String modelArg = (normalized == 'model') ? gkey : null;
            CostCalculatorService.CostResult cr = cost.costForAggregate(modelArg, cnt, tt);

            CostBreakdownDTO dto = new CostBreakdownDTO();
            dto.groupKey = gkey;
            dto.groupLabel = gkey;
            dto.flexCredits = cr.flexCredits == null ? 0L : cr.flexCredits;
            dto.discountedUsd = cr.discountedUsd == null ? 0 : cr.discountedUsd.setScale(4);
            dto.confidence = cr.confidence == null ? CostCalculatorService.CONFIDENCE_HIGH : cr.confidence;
            dto.source = cr.source == null ? CostCalculatorService.SOURCE_ESTIMATE : cr.source;
            rows.add(dto);
            labelKeys.add(gkey);
            totalTierFc += dto.flexCredits;
            totalRequestCount += (cnt == null ? 0 : cnt);
        }

        // Resolve human-readable labels for User / Prompt groupings — model
        // and feature are already self-labeling.
        if (!labelKeys.isEmpty()) {
            try {
                Map<String, String> labels;
                if (normalized == 'user') {
                    labels = resolver.resolveUserNames(labelKeys);
                } else if (normalized == 'prompt') {
                    labels = resolver.resolvePromptTemplateLabels(labelKeys);
                } else {
                    labels = new Map<String, String>();
                }
                for (CostBreakdownDTO dto : rows) {
                    String resolved = labels.get(dto.groupKey);
                    if (String.isNotBlank(resolved)) {
                        dto.groupLabel = resolved;
                    }
                }
            } catch (Exception ex) {
                // Label resolution best-effort — raw keys remain on failure.
            }
        }

        // Step 2 — Wallet-first override. If Wallet has ACTUAL totals for
        // this window, redistribute proportionally across rows. costForWindow
        // expects a List<SObject> fallback, but when Wallet IS available it
        // never reaches the fallback path, so passing null is safe.
        try {
            CostCalculatorService.CostResult walletTotal = cost.costForWindow(filter.startDate, filter.endDate, null);
            if (
                walletTotal != null &&
                walletTotal.confidence == CostCalculatorService.CONFIDENCE_ACTUAL &&
                walletTotal.flexCredits != null &&
                walletTotal.flexCredits > 0
            ) {
                redistributeWalletTotals(rows, walletTotal, totalTierFc);
            }
        } catch (Exception ex) {
            // Wallet probe failure leaves the per-row tier estimates intact.
        }

        return rows;
    }

    /**
     * Redistribute Wallet ACTUAL Flex Credits across the per-row tier
     * estimates by each row's share of the tier-rate FC total. Stamps every
     * row's confidence to ACTUAL and source to ACTUAL_WALLET so the agent
     * surfaces the same badge as the Lightning Overview tile. When the tier
     * total is zero (e.g. cost metrics disabled mid-call), each row gets an
     * even share so the totals still reconcile.
     */
    @TestVisible
    private static void redistributeWalletTotals(
        List<CostBreakdownDTO> rows,
        CostCalculatorService.CostResult walletTotal,
        Long totalTierFc
    ) {
        if (rows == null || rows.isEmpty() || walletTotal == null) {
            return;
        }
        Long walletFc = walletTotal.flexCredits == null ? 0L : walletTotal.flexCredits;
        Decimal walletUsd = walletTotal.discountedUsd == null ? 0 : walletTotal.discountedUsd;
        Integer rowCount = rows.size();

        Long fcAssigned = 0L;
        Decimal usdAssigned = 0;
        for (Integer i = 0; i < rowCount; i++) {
            CostBreakdownDTO dto = rows[i];
            Long rowFc;
            Decimal rowUsd;
            if (i == rowCount - 1) {
                // Last row absorbs rounding remainders so the row-sum matches
                // the wallet headline exactly.
                rowFc = walletFc - fcAssigned;
                rowUsd = walletUsd - usdAssigned;
            } else if (totalTierFc == null || totalTierFc <= 0) {
                rowFc = walletFc / rowCount;
                rowUsd = (walletUsd / rowCount).setScale(4);
            } else {
                Decimal share = (Decimal) (dto.flexCredits == null ? 0L : dto.flexCredits) / totalTierFc;
                rowFc = (walletFc * share).longValue();
                rowUsd = (walletUsd * share).setScale(4);
            }
            dto.flexCredits = rowFc < 0 ? 0L : rowFc;
            dto.discountedUsd = rowUsd == null ? 0 : rowUsd.setScale(4);
            dto.confidence = CostCalculatorService.CONFIDENCE_ACTUAL;
            dto.source = CostCalculatorService.SOURCE_WALLET;
            fcAssigned += dto.flexCredits;
            usdAssigned += dto.discountedUsd;
        }
    }

    // ───────────────────────── Safety Overview ───────────────────

    /**
     * Server-side aggregate refactor (2026-04-29). The previous implementation
     * walked Request → Response → Generation → Quality → Category chains for
     * every generation in the range, which was the primary scale offender.
     *
     * New approach:
     *   - Total generation count comes from `dao.countGenerationsByDateRange`.
     *   - Toxic flag count comes from `dao.countToxicFlagsByDateRange` which
     *     filters Quality directly on its own `timestamp__c`.
     *   - Category score aggregation still pulls raw Category rows filtered
     *     by date. Quality/Category volume is usually orders of magnitude
     *     smaller than Request volume; the DAO guard (LIMIT 50000) combined
     *     with the tiny % of generations that get scored makes this safe for
     *     typical 30-day windows. If a customer hits the limit here, Phase
     *     3.5/4 will promote this to its own server-side aggregate when the
     *     `value__c` column is promoted to a numeric type.
     *   - Recent flagged outputs: query up to 10 toxic Quality rows ordered
     *     by timestamp DESC, then hydrate the parent Generation + Request
     *     rows via business-key IN-clauses. Bounded.
     */
    public virtual ContentSafetyDTO getSafetyOverview(DateRangeFilter filter) {
        validateFilter(filter);
        ContentSafetyDTO out = new ContentSafetyDTO();

        // Total generations and toxic flag counts — independent of request volume
        try {
            out.totalGenerations = dao.countGenerationsByDateRange(filter.startDate, filter.endDate);
        } catch (Exception ex) {
            out.totalGenerations = 0;
        }
        Integer toxic = 0;
        try {
            toxic = dao.countToxicFlagsByDateRange(filter.startDate, filter.endDate);
        } catch (Exception ex) {
            toxic = 0;
        }
        out.toxicCount = toxic;
        out.toxicRate = out.totalGenerations == 0 ? 0 : ((Decimal) toxic / out.totalGenerations).setScale(4);

        // Category score aggregation — see method JavaDoc Compromises note.
        try {
            List<SObject> categories = dao.getContentCategoriesByDate(filter.startDate, filter.endDate);
            Map<String, List<Decimal>> scoresByCategory = new Map<String, List<Decimal>>();
            Map<String, Integer> flaggedByCategory = new Map<String, Integer>();
            for (SObject c : categories) {
                String cat = (String) c.get('category__c');
                if (String.isBlank(cat)) {
                    continue;
                }
                Decimal val = parseDecimal(c.get('value__c'));
                if (val == null) {
                    continue;
                }
                if (!scoresByCategory.containsKey(cat)) {
                    scoresByCategory.put(cat, new List<Decimal>());
                    flaggedByCategory.put(cat, 0);
                }
                scoresByCategory.get(cat).add(val);
                if (val >= SAFETY_FLAG_THRESHOLD) {
                    flaggedByCategory.put(cat, flaggedByCategory.get(cat) + 1);
                }
            }
            Map<String, Decimal> avgByCategory = new Map<String, Decimal>();
            for (String cat : scoresByCategory.keySet()) {
                List<Decimal> vals = scoresByCategory.get(cat);
                Decimal sum = 0;
                for (Decimal v : vals) {
                    sum += v;
                }
                avgByCategory.put(cat, (sum / vals.size()).setScale(4));
            }
            out.avgCategoryScores = avgByCategory;
            out.flaggedByCategory = flaggedByCategory;
        } catch (Exception ex) {
            // Category breakdown is best-effort — leave empty maps on failure
        }

        // Recent flagged outputs — bounded Quality query + per-row hydration
        if (toxic > 0) {
            try {
                List<SObject> recentToxicQuality = dao.getRecentToxicQuality(
                    filter.startDate,
                    filter.endDate,
                    TOP_N_DEFAULT
                );
                if (!recentToxicQuality.isEmpty()) {
                    out.recentFlaggedOutputs = hydrateFlaggedOutputs(recentToxicQuality);
                }
            } catch (Exception ex) {
                // Hydration failure should not poison the whole DTO
            }
        }

        return out;
    }

    /**
     * Hydrate up to N flagged outputs by walking Quality → Generation → Response
     * → Request via bounded business-key IN-clauses. Each call is bounded by
     * the input list size (typically <= 10), so this runs fast regardless of
     * overall org volume.
     */
    @TestVisible
    private List<PromptOutputDTO> hydrateFlaggedOutputs(List<SObject> qualityRows) {
        Set<String> genIds = new Set<String>();
        for (SObject q : qualityRows) {
            String genId = (String) q.get('parent__c');
            if (String.isNotBlank(genId)) {
                genIds.add(genId);
            }
        }
        if (genIds.isEmpty()) {
            return new List<PromptOutputDTO>();
        }

        // Fetch generations by business key
        List<SObject> generations = dao.getGenerationsByIds(genIds);
        Map<String, SObject> generationByKey = new Map<String, SObject>();
        Set<String> responseIds = new Set<String>();
        for (SObject g : generations) {
            String gid = (String) g.get('generationId__c');
            if (String.isNotBlank(gid)) {
                generationByKey.put(gid, g);
            }
            String rid = (String) g.get('generationResponseId__c');
            if (String.isNotBlank(rid)) {
                responseIds.add(rid);
            }
        }

        // Fetch responses → request linkage
        Map<String, String> responseToRequest = new Map<String, String>();
        Set<String> requestIds = new Set<String>();
        if (!responseIds.isEmpty()) {
            for (SObject resp : dao.getResponsesByIds(responseIds)) {
                String respId = (String) resp.get('generationResponseId__c');
                String reqId = (String) resp.get('generationRequestId__c');
                if (String.isNotBlank(respId) && String.isNotBlank(reqId)) {
                    responseToRequest.put(respId, reqId);
                    requestIds.add(reqId);
                }
            }
        }

        // Fetch requests
        Map<String, SObject> requestByKey = new Map<String, SObject>();
        Set<String> userIds = new Set<String>();
        if (!requestIds.isEmpty()) {
            for (SObject req : dao.getRequestsByGatewayIds(requestIds)) {
                String rid = (String) req.get('gatewayRequestId__c');
                if (String.isNotBlank(rid)) {
                    requestByKey.put(rid, req);
                }
                String uid = (String) req.get('userId__c');
                if (String.isNotBlank(uid)) {
                    userIds.add(uid);
                }
            }
        }

        Map<String, String> userNames = userIds.isEmpty()
            ? new Map<String, String>()
            : resolver.resolveUserNames(userIds);

        List<PromptOutputDTO> outputs = new List<PromptOutputDTO>();
        for (SObject q : qualityRows) {
            String genId = (String) q.get('parent__c');
            SObject gen = generationByKey.get(genId);
            if (gen == null) {
                continue;
            }
            String respId = (String) gen.get('generationResponseId__c');
            String reqId = responseToRequest.get(respId);
            SObject req = requestByKey.get(reqId);
            if (req == null) {
                continue;
            }
            PromptOutputDTO o = new PromptOutputDTO();
            o.requestId = reqId;
            String uid = (String) req.get('userId__c');
            o.userName = userNames.get(uid) == null ? uid : userNames.get(uid);
            o.requestDate = (DateTime) req.get('timestamp__c');
            String rawPrompt = (String) req.get('prompt__c');
            String rawGenerated = (String) gen.get('responseText__c');
            o.inputPrompt = truncate(rawPrompt, OUTPUT_TRUNCATE_LEN);
            o.generatedText = truncate(rawGenerated, OUTPUT_TRUNCATE_LEN);
            o.inputPromptFull = rawPrompt;
            o.generatedTextFull = rawGenerated;
            o.model = (String) req.get('model__c');
            o.inputTokens = toInteger(req.get('promptTokens__c'));
            o.outputTokens = toInteger(req.get('completionTokens__c'));
            o.isToxic = true;
            outputs.add(o);
        }
        outputs.sort(new PromptOutputByDateDesc());
        return outputs;
    }

    // ───────────────────────── Explorer Pivot ────────────────────

    /**
     * Server-side aggregate refactor (2026-04-29).
     *
     * The previous implementation pulled every request row in range, filtered
     * in Apex, grouped in Apex, and walked the generation chain for feedback
     * / quality metrics. That doesn't scale. The new flow:
     *
     *   1. Dispatch to a groupBy-specific aggregate DAO method, pushing
     *      `model` and `feature` equality filters into the SOQL WHERE clause
     *      as extra bind variables (still parameterized — no string concat of
     *      user input).
     *   2. Compute `RequestCount`, `TotalTokens`, and `UniqueUsers` from the
     *      aggregate rows plus one optional (user, group) pivot query for
     *      UniqueUsers when groupBy != User.
     *   3. Day/Week groupings fall back to raw rows with the same narrow-
     *      window ceiling as `getTokenConsumption` (31 days / 12 weeks).
     *
     * Compromises (v1 — see BUILD-LOG):
     *   - `AcceptanceRate` returns 0 with `metricLabel = 'Acceptance Rate (v1)'`
     *     when the groupBy is a dimension that cannot be cheaply correlated
     *     with feedback (User is supported via a userId join on the Feedback
     *     DMO; other dimensions return 0 and rely on the LWC to surface the
     *     v1 tag). Phase 4 will revisit with a materialized join.
     *   - `ToxicFlagCount` returns 0 outside the User/Feature dimensions.
     *     Feature is directly usable because both GenAIGatewayRequest and
     *     GenAIContentQuality expose `feature__c`. Phase 4 handles the rest.
     *   - `feedbackValue` filter is supported only on User groupings; other
     *     groupings ignore it and an LWC-visible flag warns the operator.
     */
    public virtual List<ExplorerResultDTO> runExplorer(ExplorerRequest req) {
        if (req == null) {
            throw new IllegalArgumentException('ExplorerRequest is required');
        }
        DateRangeFilter filter = new DateRangeFilter(req.startDate, req.endDate);
        validateFilter(filter);
        if (String.isBlank(req.groupBy)) {
            throw new IllegalArgumentException('groupBy is required');
        }
        if (String.isBlank(req.metric)) {
            throw new IllegalArgumentException('metric is required');
        }
        Integer effectiveLimit = (req.resultLimit == null || req.resultLimit <= 0) ? 25 : req.resultLimit;

        String normalizedGroupBy = req.groupBy.toLowerCase();

        // Unify legacy `filters` map with the newer `criteria` bag: the rail
        // uses criteria, the old Explorer card used filters. Whichever arrives
        // wins for its dimension.
        FilterCriteria criteria = normalizeCriteria(req, filter);
        Map<String, String> filters = req.filters == null ? new Map<String, String>() : req.filters;
        String feedbackFilter = filters.get('feedbackValue');

        Map<String, ExplorerResultDTO> perGroup = new Map<String, ExplorerResultDTO>();

        // ── Day / Week fallback ─────────────────────────────────────────
        if (normalizedGroupBy == 'day' || normalizedGroupBy == 'week') {
            Integer maxDays = normalizedGroupBy == 'day' ? 31 : 84;
            Long spanDays = (filter.endDate.getTime() - filter.startDate.getTime()) / (1000L * 60L * 60L * 24L);
            if (spanDays > maxDays) {
                throw new IllegalArgumentException(
                    'Date range too wide for ' +
                        req.groupBy +
                        ' grouping. Max ' +
                        maxDays +
                        ' days — DMOs do not support date-bucket aggregate grouping.'
                );
            }
            perGroup = runExplorerDayWeekFallback(filter, normalizedGroupBy, criteria, req.metric);
        } else {
            // ── Aggregate-first path ────────────────────────────────────
            perGroup = runExplorerAggregatePath(criteria, normalizedGroupBy, feedbackFilter, req.metric);
        }

        if (perGroup.isEmpty()) {
            return new List<ExplorerResultDTO>();
        }

        // Resolve labels for User / PromptTemplate groupBy
        Map<String, String> labels = resolveGroupLabels(perGroup.keySet(), normalizedGroupBy);
        for (ExplorerResultDTO row : perGroup.values()) {
            row.groupLabel = labels.containsKey(row.groupKey) ? labels.get(row.groupKey) : row.groupKey;
        }

        List<ExplorerResultDTO> results = new List<ExplorerResultDTO>(perGroup.values());
        results.sort(new ExplorerByMetricDesc());
        if (results.size() > effectiveLimit) {
            List<ExplorerResultDTO> trimmed = new List<ExplorerResultDTO>();
            for (Integer i = 0; i < effectiveLimit; i++) {
                trimmed.add(results[i]);
            }
            return trimmed;
        }
        return results;
    }

    /**
     * Aggregate path for User / PromptTemplate / Model / Feature groupings.
     * Builds the SOQL dynamically (necessary for optional filters) but always
     * uses bind variables — never string-concatenates caller-supplied values.
     */
    private Map<String, ExplorerResultDTO> runExplorerAggregatePath(
        FilterCriteria criteria,
        String normalizedGroupBy,
        String feedbackFilter,
        String metric
    ) {
        String groupField;
        if (normalizedGroupBy == 'user') {
            groupField = 'userId__c';
        } else if (normalizedGroupBy == 'prompttemplate') {
            groupField = 'promptTemplateDevName__c';
        } else if (normalizedGroupBy == 'model') {
            groupField = 'model__c';
        } else if (normalizedGroupBy == 'feature') {
            groupField = 'feature__c';
        } else {
            throw new IllegalArgumentException('Unsupported groupBy: ' + normalizedGroupBy);
        }

        // WHERE + binds come from FilterQueryBuilder — every dimension filter
        // (userIds, promptTemplateDevNames, models, providers, features,
        // appTypes) rides in as an `IN :bind` with a Set<String>. No caller
        // value ever touches the SOQL string. Delegated to DAO so the path
        // is mockable from tests (DMO data isn't seedable in test context).
        List<AggregateResult> aggs = dao.getExplorerAggregates(criteria, groupField);
        if (aggs == null) {
            return new Map<String, ExplorerResultDTO>();
        }

        Map<String, ExplorerResultDTO> perGroup = new Map<String, ExplorerResultDTO>();
        for (AggregateResult a : aggs) {
            String key = (String) a.get('gkey');
            if (String.isBlank(key)) {
                if (normalizedGroupBy == 'user') {
                    key = SYSTEM_SENTINEL;
                } else {
                    continue;
                }
            }
            ExplorerResultDTO dto = new ExplorerResultDTO();
            dto.groupKey = key;
            dto.supportingCount = toInteger(a.get('cnt'));
            if (metric == 'RequestCount') {
                dto.metricValue = dto.supportingCount;
                dto.metricLabel = 'Request Count';
            } else if (metric == 'TotalTokens') {
                dto.metricValue = toLong(a.get('tt'));
                dto.metricLabel = 'Total Tokens';
            } else if (metric == 'UniqueUsers') {
                // Filled in below by pivot query
                dto.metricValue = normalizedGroupBy == 'user' ? 1 : 0;
                dto.metricLabel = 'Unique Users';
            } else if (metric == 'AcceptanceRate') {
                dto.metricValue = 0;
                dto.metricLabel = 'Acceptance Rate (v1)';
            } else if (metric == 'ToxicFlagCount') {
                dto.metricValue = 0;
                dto.metricLabel = 'Toxic Flag Count (v1)';
            } else if (metric == 'TotalCost') {
                // Phase 3.5 — when grouped by Model the cost is a single
                // rate-card lookup × count. For User/Prompt/Feature groupings
                // the aggregate row doesn't tell us the model split, so we
                // use the null-model path which falls back to the Standard
                // tier — matches the documented fallback policy. The
                // CostCalculatorService is deliberately cheap (static-cached
                // rate card) so calling it per row here is negligible.
                CostCalculatorService costSvc = new CostCalculatorService();
                String modelArg = normalizedGroupBy == 'model' ? key : null;
                CostCalculatorService.CostResult cr = costSvc.costForAggregate(
                    modelArg,
                    dto.supportingCount,
                    toLong(a.get('tt'))
                );
                dto.metricValue = cr.discountedUsd == null ? 0 : cr.discountedUsd;
                dto.metricLabel = 'Total Cost (USD)';
            } else {
                throw new IllegalArgumentException('Unsupported metric: ' + metric);
            }
            perGroup.put(key, dto);
        }

        // UniqueUsers pivot when not already grouped by user
        if (metric == 'UniqueUsers' && normalizedGroupBy != 'user') {
            try {
                Map<String, Set<String>> usersByGroup = pivotUniqueUsers(criteria, normalizedGroupBy);
                for (String grp : usersByGroup.keySet()) {
                    if (perGroup.containsKey(grp)) {
                        perGroup.get(grp).metricValue = usersByGroup.get(grp).size();
                    }
                }
            } catch (Exception ex) {
                // Leave metricValue = 0 on failure
            }
        }

        // feedbackValue filter — supported only on User groupings in v1
        if (String.isNotBlank(feedbackFilter) && normalizedGroupBy == 'user') {
            Set<String> matchingUsers = new Set<String>();
            try {
                List<SObject> feedback = dao.getFeedbackForDateRange(criteria.startDate, criteria.endDate);
                for (SObject f : feedback) {
                    String fv = (String) f.get('feedback__c');
                    if (fv == null || !feedbackFilter.equalsIgnoreCase(fv)) {
                        continue;
                    }
                    String uid = (String) f.get('userId__c');
                    if (uid == null) {
                        uid = SYSTEM_SENTINEL;
                    }
                    matchingUsers.add(uid);
                }
            } catch (Exception ex) {
                // Empty match set on failure
            }
            Map<String, ExplorerResultDTO> survivors = new Map<String, ExplorerResultDTO>();
            for (String k : perGroup.keySet()) {
                if (matchingUsers.contains(k)) {
                    survivors.put(k, perGroup.get(k));
                }
            }
            perGroup = survivors;
        }

        // AcceptanceRate per user — join on userId in Feedback DMO
        if (metric == 'AcceptanceRate' && normalizedGroupBy == 'user') {
            Map<String, Integer> posByUser = new Map<String, Integer>();
            Map<String, Integer> totalByUser = new Map<String, Integer>();
            try {
                for (SObject f : dao.getFeedbackForDateRange(criteria.startDate, criteria.endDate)) {
                    String uid = (String) f.get('userId__c');
                    if (uid == null) {
                        uid = SYSTEM_SENTINEL;
                    }
                    if (!perGroup.containsKey(uid)) {
                        continue;
                    }
                    totalByUser.put(uid, (totalByUser.get(uid) == null ? 0 : totalByUser.get(uid)) + 1);
                    if (isPositiveFeedback(f)) {
                        posByUser.put(uid, (posByUser.get(uid) == null ? 0 : posByUser.get(uid)) + 1);
                    }
                }
                for (String uid : perGroup.keySet()) {
                    Integer total = totalByUser.get(uid) == null ? 0 : totalByUser.get(uid);
                    if (total == 0) {
                        continue;
                    }
                    Integer pos = posByUser.get(uid) == null ? 0 : posByUser.get(uid);
                    perGroup.get(uid).metricValue = ((Decimal) pos / total).setScale(4);
                    perGroup.get(uid).metricLabel = 'Acceptance Rate';
                }
            } catch (Exception ex) {
                // Leave zero
            }
        }

        // ToxicFlagCount — supported on Feature grouping via feature__c on Quality DMO
        if (metric == 'ToxicFlagCount' && normalizedGroupBy == 'feature') {
            try {
                List<AggregateResult> qAggs = dao.getToxicFlagsByFeature(criteria.startDate, criteria.endDate);
                for (AggregateResult a : qAggs) {
                    String feat = (String) a.get('gkey');
                    if (feat != null && perGroup.containsKey(feat)) {
                        perGroup.get(feat).metricValue = toInteger(a.get('cnt'));
                        perGroup.get(feat).metricLabel = 'Toxic Flag Count';
                    }
                }
            } catch (Exception ex) {
                // Leave zero
            }
        }

        return perGroup;
    }

    /**
     * Per-group unique-user pivot using the (user, X) aggregate DAO methods.
     * Returns groupKey → set of userIds. Dimension filters from the criteria
     * are applied in Apex against the pivot-carried group key since the
     * aggregate rows only surface the `(user, X)` pair.
     */
    private Map<String, Set<String>> pivotUniqueUsers(FilterCriteria criteria, String normalizedGroupBy) {
        List<AggregateResult> pivotRows;
        if (normalizedGroupBy == 'prompttemplate') {
            pivotRows = dao.getRequestAggregatesByUserAndPrompt(criteria.startDate, criteria.endDate);
        } else if (normalizedGroupBy == 'model') {
            pivotRows = dao.getRequestAggregatesByUserAndModel(criteria.startDate, criteria.endDate);
        } else if (normalizedGroupBy == 'feature') {
            pivotRows = dao.getRequestAggregatesByUserAndFeature(criteria.startDate, criteria.endDate);
        } else {
            return new Map<String, Set<String>>();
        }

        Set<String> modelAllow = toAllowSet(criteria.models);
        Set<String> featureAllow = toAllowSet(criteria.features);
        Set<String> promptAllow = toAllowSet(criteria.promptTemplateDevNames);
        Set<String> userAllow = toAllowSet(criteria.userIds);

        Map<String, Set<String>> out = new Map<String, Set<String>>();
        for (AggregateResult a : pivotRows) {
            String grp = (String) a.get('pdn');
            if (String.isBlank(grp)) {
                continue;
            }
            String uid = (String) a.get('uid');
            if (uid == null) {
                uid = SYSTEM_SENTINEL;
            }
            if (userAllow != null && !userAllow.contains(uid)) {
                continue;
            }
            if (normalizedGroupBy == 'model' && modelAllow != null && !modelAllow.contains(grp)) {
                continue;
            }
            if (normalizedGroupBy == 'feature' && featureAllow != null && !featureAllow.contains(grp)) {
                continue;
            }
            if (normalizedGroupBy == 'prompttemplate' && promptAllow != null && !promptAllow.contains(grp)) {
                continue;
            }
            if (!out.containsKey(grp)) {
                out.put(grp, new Set<String>());
            }
            out.get(grp).add(uid);
        }
        return out;
    }

    private Set<String> toAllowSet(List<String> values) {
        if (values == null || values.isEmpty()) {
            return null;
        }
        Set<String> s = new Set<String>();
        for (String v : values) {
            if (String.isNotBlank(v)) {
                s.add(v);
            }
        }
        return s.isEmpty() ? null : s;
    }

    /**
     * Raw-row fallback for Day/Week groupings. Bounded to <= 31 days / 12 weeks
     * by the caller. Dimension filters are a v1 limitation on Day/Week
     * groupings — the aggregate DAO methods don't yet accept criteria, so the
     * rail's non-date filters are ignored on these bucketed views (documented).
     */
    private Map<String, ExplorerResultDTO> runExplorerDayWeekFallback(
        DateRangeFilter filter,
        String normalizedGroupBy,
        FilterCriteria criteria,
        String metric
    ) {
        // DMO SOQL doesn't support DATE() / CALENDAR_WEEK() aggregate grouping.
        // Fan out one aggregate query per bucket (up to ~31 days or ~12 weeks).
        // The caller has already validated the date span; we just iterate.
        Map<String, ExplorerResultDTO> perGroup = new Map<String, ExplorerResultDTO>();

        // Model/Feature filters at the bucket level aren't supported by the
        // existing aggregate DAO methods — for Day/Week with filters we'd need
        // dedicated filtered aggregate methods. In v1, ignore the filters on
        // Day/Week groupings and surface the unfiltered buckets (documented
        // limitation). AcceptanceRate and ToxicFlagCount are also v1-TBD.
        Boolean tokensOnly = (metric == 'TotalTokens');
        Boolean countOnly = (metric == 'RequestCount');
        Boolean usersOnly = (metric == 'UniqueUsers');

        Integer bucketSizeDays = (normalizedGroupBy == 'day') ? 1 : 7;
        DateTime bucketStart = filter.startDate;
        Integer bucketIndex = 0;
        while (bucketStart < filter.endDate && bucketIndex < 100) {
            DateTime bucketEnd = bucketStart.addDays(bucketSizeDays);
            if (bucketEnd > filter.endDate) {
                bucketEnd = filter.endDate;
            }
            String key = formatBucketKey(bucketStart, normalizedGroupBy);
            ExplorerResultDTO dto = new ExplorerResultDTO();
            dto.groupKey = key;
            dto.groupLabel = key;
            if (countOnly || tokensOnly) {
                AggregateResult bucketTotals = dao.getRequestTotals(bucketStart, bucketEnd);
                Integer cnt = bucketTotals == null ? 0 : toInteger(bucketTotals.get('cnt'));
                dto.supportingCount = cnt;
                if (countOnly) {
                    dto.metricValue = cnt;
                    dto.metricLabel = 'Request Count';
                } else {
                    dto.metricValue = bucketTotals == null ? 0 : toLong(bucketTotals.get('tt'));
                    dto.metricLabel = 'Total Tokens';
                }
            } else if (usersOnly) {
                List<AggregateResult> userBuckets = dao.getRequestAggregatesByUser(bucketStart, bucketEnd);
                dto.metricValue = userBuckets.size();
                dto.metricLabel = 'Unique Users';
                Integer cnt = 0;
                for (AggregateResult ar : userBuckets) {
                    cnt += toInteger(ar.get('cnt'));
                }
                dto.supportingCount = cnt;
            } else {
                // AcceptanceRate / ToxicFlagCount for Day/Week — v1 limitation
                dto.metricValue = 0;
                dto.metricLabel = metric + ' (v1)';
            }
            if (dto.supportingCount == null) {
                dto.supportingCount = 0;
            }
            // Skip empty buckets so the chart doesn't render flat zero rows.
            if (dto.metricValue != null && dto.metricValue > 0) {
                perGroup.put(key, dto);
            }
            bucketStart = bucketEnd;
            bucketIndex++;
        }
        return perGroup;
    }

    /**
     * Human-readable bucket key for Day/Week aggregate groupings.
     * "day"  → "2026-04-29"         (ISO date)
     * "week" → "Wk 2026-04-27"      (ISO date of bucket start, "Wk" prefix)
     */
    @TestVisible
    private String formatBucketKey(DateTime bucketStart, String normalizedGroupBy) {
        if (bucketStart == null) {
            return '—';
        }
        String iso = bucketStart.format('yyyy-MM-dd');
        return normalizedGroupBy == 'week' ? 'Wk ' + iso : iso;
    }

    // ───────────────────────── Adoption analytics (Phase 3) ─────────────────

    /**
     * Trailing 8-week trend of (requests, activeUsers, tokens) for the Overview
     * tab WoW chip strip + the Activity tab adoption sparkline. Independent of
     * the active filter — always anchored to "now" so the chip matches the
     * KPI tile delta. Eight DAO calls × two helpers each, all sub-second.
     */
    public virtual OrgAdoptionDeltasDTO getOrgAdoptionDeltas(DateRangeFilter filter) {
        validateFilter(filter);
        OrgAdoptionDeltasDTO out = new OrgAdoptionDeltasDTO();
        Integer weekCount = 8;
        DateTime now = DateTime.now();
        // weekStart[i] is the start of the i-th week back. Week 0 is the
        // most recent (still-active) ISO week.
        Date currentWeekStart = toIsoWeekStart(now.dateGmt());
        List<OrgAdoptionDeltasDTO.WeekDelta> series = new List<OrgAdoptionDeltasDTO.WeekDelta>();
        for (Integer i = weekCount - 1; i >= 0; i--) {
            Date wkStart = currentWeekStart.addDays(-7 * i);
            Date wkEnd = wkStart.addDays(7);
            DateTime startDt = DateTime.newInstance(wkStart, Time.newInstance(0, 0, 0, 0));
            DateTime endDt = DateTime.newInstance(wkEnd, Time.newInstance(0, 0, 0, 0)).addSeconds(-1);
            OrgAdoptionDeltasDTO.WeekDelta wd = new OrgAdoptionDeltasDTO.WeekDelta();
            wd.weekStart = wkStart;
            wd.weekIsoLabel = isoWeekLabel(wkStart);
            try {
                AggregateResult tot = dao.getRequestTotals(startDt, endDt);
                if (tot != null) {
                    wd.requests = toInteger(tot.get('cnt'));
                    wd.tokens = toLong(tot.get('pt')) + toLong(tot.get('ct'));
                }
            } catch (Exception e) {
            }
            try {
                wd.activeUsers = dao.getDistinctUserCountInWindow(startDt, endDt);
            } catch (Exception e) {
            }
            series.add(wd);
        }

        // Compute WoW pct deltas in a second pass (oldest week has no prior
        // baseline, so its delta stays 0).
        for (Integer i = 1; i < series.size(); i++) {
            OrgAdoptionDeltasDTO.WeekDelta cur = series[i];
            OrgAdoptionDeltasDTO.WeekDelta prv = series[i - 1];
            cur.requestsWowPct = wowPct(cur.requests, prv.requests);
            cur.usersWowPct = wowPct(cur.activeUsers, prv.activeUsers);
            cur.tokensWowPct = wowPct(cur.tokens, prv.tokens);
        }

        out.weeks = series;
        if (series.size() >= 2) {
            OrgAdoptionDeltasDTO.WeekDelta latest = series[series.size() - 1];
            out.latestRequestsWowPct = latest.requestsWowPct == null ? 0 : latest.requestsWowPct;
            out.latestUsersWowPct = latest.usersWowPct == null ? 0 : latest.usersWowPct;
            out.latestTokensWowPct = latest.tokensWowPct == null ? 0 : latest.tokensWowPct;
        }
        return out;
    }

    /**
     * Cohort retention: bins users by ISO-week of first observed request, then
     * for each cohort × age-week computes the share of cohort members who were
     * active in the observation week. Capped at MAX_COHORT_WEEKS to bound heap.
     * `truncated = true` when the underlying timestamp DAO call hit its 50k cap.
     */
    public virtual AdoptionCohortsDTO getAdoptionCohorts(DateRangeFilter filter) {
        validateFilter(filter);
        AdoptionCohortsDTO out = new AdoptionCohortsDTO();
        try {
            List<SObject> rows = dao.getRequestTimestampsByUser(filter.startDate, filter.endDate);
            if (rows == null || rows.isEmpty()) {
                return out;
            }
            out.truncated = (rows.size() >= 50000);
            Map<String, Date> firstSeenByUser = new Map<String, Date>();
            // user -> set of ISO week starts the user was active in. Set<Date>
            // is denser than List in heap because of dedup.
            Map<String, Set<Date>> activeWeeksByUser = new Map<String, Set<Date>>();
            for (SObject r : rows) {
                String uid = (String) r.get('userId__c');
                if (String.isBlank(uid)) {
                    continue;
                }
                Object rawTs = r.get('timestamp__c');
                Date d = toDateGmt(rawTs);
                if (d == null) {
                    continue;
                }
                Date wkStart = toIsoWeekStart(d);
                Date prior = firstSeenByUser.get(uid);
                if (prior == null || wkStart < prior) {
                    firstSeenByUser.put(uid, wkStart);
                }
                Set<Date> active = activeWeeksByUser.get(uid);
                if (active == null) {
                    active = new Set<Date>();
                    activeWeeksByUser.put(uid, active);
                }
                active.add(wkStart);
            }
            out.totalUsersObserved = firstSeenByUser.size();

            // Build cohort buckets: cohortWeek -> userIds in that cohort.
            Map<Date, Set<String>> cohortMembers = new Map<Date, Set<String>>();
            for (String uid : firstSeenByUser.keySet()) {
                Date cw = firstSeenByUser.get(uid);
                Set<String> bucket = cohortMembers.get(cw);
                if (bucket == null) {
                    bucket = new Set<String>();
                    cohortMembers.put(cw, bucket);
                }
                bucket.add(uid);
            }

            // Sort cohort weeks ASC so the heatmap renders oldest-first.
            List<Date> cohortWeeks = new List<Date>(cohortMembers.keySet());
            cohortWeeks.sort();
            // Clip if we have more cohorts than the cap allows.
            Integer maxWeeks = AdoptionCohortsDTO.MAX_COHORT_WEEKS;
            if (cohortWeeks.size() > maxWeeks) {
                cohortWeeks = sliceTail(cohortWeeks, maxWeeks);
            }
            Date latestCohort = cohortWeeks[cohortWeeks.size() - 1];

            for (Date cw : cohortWeeks) {
                Set<String> members = cohortMembers.get(cw);
                AdoptionCohortsDTO.CohortRow row = new AdoptionCohortsDTO.CohortRow();
                row.weekStart = cw;
                row.weekIsoLabel = isoWeekLabel(cw);
                row.cohortSize = members.size();
                Integer weeksSinceFirst = weeksBetween(cw, latestCohort);
                Integer ageCols = Math.min(weeksSinceFirst + 1, maxWeeks);
                row.ageInWeeks = ageCols;
                List<Decimal> retention = new List<Decimal>();
                for (Integer ageIdx = 0; ageIdx < ageCols; ageIdx++) {
                    Date observationWeek = cw.addDays(7 * ageIdx);
                    Integer activeInWeek = 0;
                    for (String uid : members) {
                        Set<Date> userActive = activeWeeksByUser.get(uid);
                        if (userActive != null && userActive.contains(observationWeek)) {
                            activeInWeek++;
                        }
                    }
                    Decimal pct = members.isEmpty() ? 0 : ((Decimal) activeInWeek / members.size()).setScale(4);
                    retention.add(pct);
                }
                row.retentionByWeek = retention;
                out.cohorts.add(row);
            }
        } catch (Exception e) {
            // DAO failure or schema-absent — return empty DTO so the LWC shows
            // its empty-state rather than crashing.
        }
        return out;
    }

    /**
     * Pareto-style power-user segmentation. Sorts the existing per-user
     * aggregate by request count DESC, slices top-1% / top-10%, computes
     * volume share. No extra DAO call beyond the one cached aggregate.
     */
    public virtual PowerUserSegmentsDTO getPowerUserSegments(DateRangeFilter filter) {
        validateFilter(filter);
        PowerUserSegmentsDTO out = new PowerUserSegmentsDTO();
        try {
            List<AggregateResult> userAggs = dao.getRequestAggregatesByUser(filter.startDate, filter.endDate);
            if (userAggs == null || userAggs.isEmpty()) {
                return out;
            }
            List<UserAggRow> rows = new List<UserAggRow>();
            Long totalRequests = 0L;
            for (AggregateResult a : userAggs) {
                String uid = (String) a.get('gkey');
                if (String.isBlank(uid)) {
                    continue;
                }
                UserAggRow r = new UserAggRow();
                r.userId = uid;
                r.requestCount = toInteger(a.get('cnt'));
                r.totalTokens = toLong(a.get('tt'));
                rows.add(r);
                totalRequests += r.requestCount;
            }
            if (rows.isEmpty()) {
                return out;
            }
            rows.sort(new UserAggByCountDesc());
            out.totalActiveUsers = rows.size();
            out.totalRequests = totalRequests;

            Integer top10 = Math.max(1, (Integer) Math.ceil(rows.size() * 0.10));
            Integer top1 = Math.max(1, (Integer) Math.ceil(rows.size() * 0.01));
            // top-1% only meaningful when there are at least ~10 users; below
            // that the ceil(1%) lower-bound makes it identical to "the top user".
            if (rows.size() < 10) {
                top1 = 0;
            }
            top10 = Math.min(top10, rows.size());
            top1 = Math.min(top1, rows.size());

            Long top10Reqs = 0L;
            for (Integer i = 0; i < top10; i++) {
                top10Reqs += rows[i].requestCount;
            }
            Long top1Reqs = 0L;
            for (Integer i = 0; i < top1; i++) {
                top1Reqs += rows[i].requestCount;
            }

            out.top10PercentUserCount = top10;
            out.top10PercentRequestCount = top10Reqs;
            out.top10PercentVolumeShare = totalRequests == 0 ? 0 : ((Decimal) top10Reqs / totalRequests).setScale(4);
            out.top1PercentUserCount = top1;
            out.top1PercentRequestCount = top1Reqs;
            out.top1PercentVolumeShare = totalRequests == 0 ? 0 : ((Decimal) top1Reqs / totalRequests).setScale(4);

            // Resolve names for the top slice (cap at 50 to keep the cache
            // partition healthy and avoid LWC payload bloat).
            Integer nameCap = Math.min(50, top10);
            Set<String> idsToResolve = new Set<String>();
            for (Integer i = 0; i < nameCap; i++) {
                idsToResolve.add(rows[i].userId);
            }
            Map<String, String> names = new Map<String, String>();
            try {
                names = resolver.resolveUserNames(idsToResolve);
            } catch (Exception e) {
            }
            for (Integer i = 0; i < nameCap; i++) {
                UserAggRow r = rows[i];
                PowerUserSegmentsDTO.TopUser tu = new PowerUserSegmentsDTO.TopUser();
                tu.userId = r.userId;
                tu.userName = names.get(r.userId);
                tu.requestCount = r.requestCount;
                tu.totalTokens = r.totalTokens;
                tu.tier = (i < top1) ? 'Top 1%' : 'Top 10%';
                out.topUsers.add(tu);
            }
        } catch (Exception e) {
            // Swallow — empty DTO already returned with zeros.
        }
        return out;
    }

    /**
     * Per-feature breadth/depth + first-observed timestamps. Breadth uses the
     * entitled denominator from EntitlementService; depth is the median
     * invocations per active user. Repeat-user count is users with ≥ 2
     * invocations on that feature.
     */
    public virtual List<FeatureAdoptionDTO> getFeatureAdoption(DateRangeFilter filter) {
        validateFilter(filter);
        List<FeatureAdoptionDTO> out = new List<FeatureAdoptionDTO>();
        try {
            // Per-feature totals (counts, tokens, min/max ts).
            List<AggregateResult> featureAggs = dao.getRequestAggregatesByFeature(filter.startDate, filter.endDate);
            if (featureAggs == null || featureAggs.isEmpty()) {
                return out;
            }
            // Per-(user, feature) for breadth + depth math.
            List<AggregateResult> userFeatureAggs = dao.getRequestAggregatesByUserAndFeature(
                filter.startDate,
                filter.endDate
            );

            // Build feature -> List<invocationsPerUser>, and feature -> distinct users.
            Map<String, List<Integer>> invocationsByFeature = new Map<String, List<Integer>>();
            Map<String, Set<String>> uniqueUsersByFeature = new Map<String, Set<String>>();
            if (userFeatureAggs != null) {
                for (AggregateResult a : userFeatureAggs) {
                    // alias used on this DAO method is `pdn` for the secondary
                    // dimension and `uid` for user; see getRequestAggregatesByUserAndFeature
                    String feat = (String) a.get('pdn');
                    String uid = (String) a.get('uid');
                    Integer cnt = toInteger(a.get('cnt'));
                    if (String.isBlank(feat) || String.isBlank(uid)) {
                        continue;
                    }
                    List<Integer> inv = invocationsByFeature.get(feat);
                    if (inv == null) {
                        inv = new List<Integer>();
                        invocationsByFeature.put(feat, inv);
                    }
                    inv.add(cnt);
                    Set<String> users = uniqueUsersByFeature.get(feat);
                    if (users == null) {
                        users = new Set<String>();
                        uniqueUsersByFeature.put(feat, users);
                    }
                    users.add(uid);
                }
            }

            // Resolve entitled denominator once.
            Integer denominator = 0;
            Boolean fallback = true;
            try {
                EntitlementSnapshotDTO snap = entitlement.getSnapshot(new Set<String>());
                if (snap != null) {
                    denominator = snap.entitledCount == null ? 0 : snap.entitledCount;
                    fallback = snap.entitledFallback == null ? true : snap.entitledFallback;
                }
            } catch (Exception e) {
            }

            for (AggregateResult a : featureAggs) {
                String feat = (String) a.get('gkey');
                if (String.isBlank(feat)) {
                    continue;
                }
                FeatureAdoptionDTO row = new FeatureAdoptionDTO();
                row.featureName = feat;
                row.invocationCount = toInteger(a.get('cnt'));
                row.totalTokens = toLong(a.get('tt'));
                Object minRaw = a.get('minTs');
                Object maxRaw = a.get('maxTs');
                if (minRaw != null) {
                    row.firstObservedInRange = toDateTime(minRaw);
                }
                if (maxRaw != null) {
                    row.lastObservedInRange = toDateTime(maxRaw);
                }
                List<Integer> invocations = invocationsByFeature.get(feat);
                Set<String> distinctUsers = uniqueUsersByFeature.get(feat);
                Integer unique = distinctUsers == null ? 0 : distinctUsers.size();
                row.uniqueUserCount = unique;
                row.repeatUserCount = countRepeatUsers(invocations);
                row.depthMedian = medianInteger(invocations);
                row.breadthRate = (denominator <= 0) ? 0 : ((Decimal) unique / denominator).setScale(4);
                row.entitledFallback = fallback;
                row.firstObservedInOrg = row.firstObservedInRange;
                out.add(row);
            }
        } catch (Exception e) {
            // Swallow — partial result already accumulated.
        }
        return out;
    }

    /**
     * Thin pass-through to EntitlementService for the dedicated funnel LWC.
     * Computes the active-userId set from the request aggregate so the
     * snapshot has a real numerator.
     */
    public virtual EntitlementSnapshotDTO getEntitlementSnapshot(DateRangeFilter filter) {
        validateFilter(filter);
        Set<String> activeUserIdStrings = new Set<String>();
        try {
            List<AggregateResult> userAggs = dao.getRequestAggregatesByUser(filter.startDate, filter.endDate);
            if (userAggs != null) {
                for (AggregateResult a : userAggs) {
                    String uid = (String) a.get('gkey');
                    if (String.isNotBlank(uid)) {
                        activeUserIdStrings.add(uid);
                    }
                }
            }
        } catch (Exception e) {
            // Empty active set — entitled snapshot still resolves with 0 active.
        }
        try {
            EntitlementSnapshotDTO snap = entitlement.getSnapshot(activeUserIdStrings);
            return snap == null ? new EntitlementSnapshotDTO() : snap;
        } catch (Exception e) {
            return new EntitlementSnapshotDTO();
        }
    }

    // ───────────────────────── Adoption helpers ─────────────────────

    @TestVisible
    private static Decimal wowPct(Long latest, Long prior) {
        if (prior == null || prior == 0L) {
            return latest == null || latest == 0L ? 0 : 100;
        }
        Decimal delta = ((Decimal) (latest - prior) / prior) * 100;
        return delta.setScale(2);
    }

    @TestVisible
    private static Decimal wowPct(Integer latest, Integer prior) {
        return wowPct(latest == null ? 0L : (Long) latest, prior == null ? 0L : (Long) prior);
    }

    /**
     * ISO-8601 week start (Monday). Apex's `Date.toStartOfWeek()` honors the
     * locale; we need an absolute Monday so cohorts align across users in
     * different locales.
     */
    @TestVisible
    private static Date toIsoWeekStart(Date d) {
        if (d == null) {
            return null;
        }
        // Date.SUNDAY-based offsets won't help here because Apex doesn't expose
        // a direct day-of-week getter on Date. Use DateTime.format('u') which
        // returns 1 (Mon) ... 7 (Sun).
        DateTime asDt = DateTime.newInstance(d, Time.newInstance(12, 0, 0, 0));
        Integer iso = Integer.valueOf(asDt.formatGmt('u'));
        return d.addDays(-(iso - 1));
    }

    @TestVisible
    private static String isoWeekLabel(Date weekStart) {
        if (weekStart == null) {
            return '';
        }
        DateTime asDt = DateTime.newInstance(weekStart, Time.newInstance(12, 0, 0, 0));
        // 'YYYY-Www' is the ISO 8601 week date format.
        return asDt.formatGmt('YYYY') + '-W' + asDt.formatGmt('ww');
    }

    @TestVisible
    private static Integer weeksBetween(Date earlier, Date later) {
        if (earlier == null || later == null) {
            return 0;
        }
        Integer days = earlier.daysBetween(later);
        return days / 7;
    }

    @TestVisible
    private static Date toDateGmt(Object raw) {
        if (raw == null) {
            return null;
        }
        if (raw instanceof DateTime) {
            return ((DateTime) raw).dateGmt();
        }
        try {
            return DateTime.valueOf(String.valueOf(raw)).dateGmt();
        } catch (Exception e) {
            return null;
        }
    }

    @TestVisible
    private static DateTime toDateTime(Object raw) {
        if (raw == null) {
            return null;
        }
        if (raw instanceof DateTime) {
            return (DateTime) raw;
        }
        try {
            return DateTime.valueOf(String.valueOf(raw));
        } catch (Exception e) {
            return null;
        }
    }

    @TestVisible
    private static Integer countRepeatUsers(List<Integer> invocations) {
        if (invocations == null) {
            return 0;
        }
        Integer repeat = 0;
        for (Integer n : invocations) {
            if (n != null && n >= 2) {
                repeat++;
            }
        }
        return repeat;
    }

    @TestVisible
    private static Decimal medianInteger(List<Integer> values) {
        if (values == null || values.isEmpty()) {
            return 0;
        }
        List<Integer> copy = new List<Integer>(values);
        copy.sort();
        Integer n = copy.size();
        if (Math.mod(n, 2) == 1) {
            return copy[n / 2];
        }
        Integer a = copy[n / 2 - 1];
        Integer b = copy[n / 2];
        return ((Decimal) (a + b) / 2).setScale(2);
    }

    @TestVisible
    private static List<Date> sliceTail(List<Date> src, Integer count) {
        Integer start = Math.max(0, src.size() - count);
        List<Date> out = new List<Date>();
        for (Integer i = start; i < src.size(); i++) {
            out.add(src[i]);
        }
        return out;
    }

    @TestVisible
    private class UserAggRow {
        public String userId;
        public Integer requestCount;
        public Long totalTokens;

        public UserAggRow() {
            this.requestCount = 0;
            this.totalTokens = 0L;
        }
    }

    private class UserAggByCountDesc implements Comparator<UserAggRow> {
        public Integer compare(UserAggRow a, UserAggRow b) {
            Integer ac = a.requestCount == null ? 0 : a.requestCount;
            Integer bc = b.requestCount == null ? 0 : b.requestCount;
            if (ac == bc) {
                return 0;
            }
            return ac < bc ? 1 : -1;
        }
    }

    // ───────────────────────── Prerequisites ─────────────────────

    public virtual Map<String, Boolean> checkPrerequisites() {
        Map<String, Boolean> out = new Map<String, Boolean>{
            'dataCloudEnabled' => false,
            'hasDmoAccess' => false,
            'hasData' => false,
            'cacheAvailable' => false
        };
        DateTime start = DateTime.now().addDays(-7);
        DateTime endDt = DateTime.now();
        Integer count = -1;
        try {
            count = dao.countRequestsByDateRange(start, endDt);
            out.put('dataCloudEnabled', true);
            out.put('hasDmoAccess', true);
            out.put('hasData', count != null && count > 0);
        } catch (Exception e) {
            // DMO not present or no access — leave flags false
        }
        try {
            Cache.OrgPartition partition = Cache.Org.getPartition(CACHE_PARTITION_NAME);
            out.put('cacheAvailable', partition != null);
        } catch (Exception e) {
            out.put('cacheAvailable', false);
        }
        return out;
    }

    // ───────────────────────── Helpers: validation ───────────────

    private void validateFilter(DateRangeFilter filter) {
        if (filter == null) {
            throw new IllegalArgumentException('DateRangeFilter is required');
        }
        if (filter.startDate == null || filter.endDate == null) {
            throw new IllegalArgumentException('startDate and endDate are required');
        }
        if (filter.startDate > filter.endDate) {
            throw new IllegalArgumentException('startDate must be on or before endDate');
        }
    }

    // ───────────────────────── Helpers: parsing ──────────────────

    @TestVisible
    private static Long toLong(Object raw) {
        if (raw == null) {
            return 0L;
        }
        if (raw instanceof Decimal) {
            return ((Decimal) raw).longValue();
        }
        if (raw instanceof Double) {
            return ((Double) raw).longValue();
        }
        if (raw instanceof Integer) {
            return (Long) (Integer) raw;
        }
        if (raw instanceof Long) {
            return (Long) raw;
        }
        try {
            return Decimal.valueOf(String.valueOf(raw)).longValue();
        } catch (Exception e) {
            return 0L;
        }
    }

    @TestVisible
    private static Integer toInteger(Object raw) {
        if (raw == null) {
            return 0;
        }
        if (raw instanceof Decimal) {
            return ((Decimal) raw).intValue();
        }
        if (raw instanceof Double) {
            return ((Double) raw).intValue();
        }
        if (raw instanceof Integer) {
            return (Integer) raw;
        }
        if (raw instanceof Long) {
            return ((Long) raw).intValue();
        }
        try {
            return Decimal.valueOf(String.valueOf(raw)).intValue();
        } catch (Exception e) {
            return 0;
        }
    }

    @TestVisible
    private static Boolean parseBool(Object raw) {
        if (raw == null) {
            return false;
        }
        if (raw instanceof Boolean) {
            return (Boolean) raw;
        }
        String s = String.valueOf(raw);
        return 'true'.equalsIgnoreCase(s);
    }

    @TestVisible
    private static Decimal parseDecimal(Object raw) {
        if (raw == null) {
            return null;
        }
        if (raw instanceof Decimal) {
            return (Decimal) raw;
        }
        if (raw instanceof Double) {
            return Decimal.valueOf((Double) raw);
        }
        try {
            return Decimal.valueOf(String.valueOf(raw));
        } catch (Exception e) {
            return null;
        }
    }

    @TestVisible
    private static String truncate(String s, Integer max) {
        if (s == null) {
            return null;
        }
        return s.length() <= max ? s : s.substring(0, max) + '…';
    }

    // ───────────────────────── Helpers: feedback ─────────────────

    @TestVisible
    private static Boolean isPositiveFeedback(SObject f) {
        String action = normalize((String) f.get('action__c'));
        String fb = normalize((String) f.get('feedback__c'));
        return action == FEEDBACK_POSITIVE_ACCEPTED ||
            fb == FEEDBACK_POSITIVE_THUMBS_UP ||
            fb == FEEDBACK_POSITIVE_ACCEPTED;
    }

    @TestVisible
    private static Boolean isNegativeFeedback(SObject f) {
        String action = normalize((String) f.get('action__c'));
        String fb = normalize((String) f.get('feedback__c'));
        return action == FEEDBACK_NEGATIVE_REJECTED ||
            fb == FEEDBACK_NEGATIVE_THUMBS_DOWN ||
            fb == FEEDBACK_NEGATIVE_REJECTED;
    }

    private static String normalize(String s) {
        return s == null ? null : s.trim().toLowerCase();
    }

    /**
     * Phase 2.2 — read the per-org top-N cap from FluentMetric_Cost_Settings__c.
     * Defaults to 25 when the setting is missing/null. Hard ceiling of 50 to
     * keep the chain walk inside the 100-SOQL transaction limit even when
     * other dashboards run in the same call.
     */
    @TestVisible
    private static Integer readTopNPromptAcceptanceSample() {
        Integer fallback = 25;
        Integer hardCeiling = 50;
        try {
            FluentMetric_Cost_Settings__c s = FluentMetric_Cost_Settings__c.getOrgDefaults();
            if (s == null || s.Top_N_Prompt_Acceptance_Sample__c == null) {
                return fallback;
            }
            Integer configured = s.Top_N_Prompt_Acceptance_Sample__c.intValue();
            if (configured < 0) {
                return fallback;
            }
            return Math.min(configured, hardCeiling);
        } catch (Exception ex) {
            return fallback;
        }
    }

    /**
     * Phase 2.2 — bounded chain walk producing a SAMPLED acceptance rate for
     * a single prompt. Pulls up to 500 recent requests in window, joins
     * Request → Response → Generation, then counts feedback. Returns null
     * when there's no clean attribution (no requests, no feedback, or any
     * step throws — caller leaves whatever the correlation pass produced).
     */
    @TestVisible
    private Decimal sampleAcceptanceForPrompt(String promptDevName, DateRangeFilter filter) {
        if (String.isBlank(promptDevName)) {
            return null;
        }
        try {
            List<SObject> requests = dao.getRecentRequestsByPromptTemplate(
                promptDevName,
                filter.startDate,
                filter.endDate,
                500
            );
            if (requests == null || requests.isEmpty()) {
                return null;
            }
            Set<String> requestIds = collectBusinessKeys(requests, 'gatewayRequestId__c');
            if (requestIds.isEmpty()) {
                return null;
            }
            List<SObject> responses = dao.getResponsesForRequests(requestIds);
            Set<String> responseIds = new Set<String>();
            for (SObject r : responses) {
                String rid = (String) r.get('generationResponseId__c');
                if (String.isNotBlank(rid)) {
                    responseIds.add(rid);
                }
            }
            if (responseIds.isEmpty()) {
                return null;
            }
            List<SObject> generations = dao.getGenerationsForResponses(responseIds);
            Set<String> generationIds = new Set<String>();
            for (SObject g : generations) {
                String gid = (String) g.get('generationId__c');
                if (String.isNotBlank(gid)) {
                    generationIds.add(gid);
                }
            }
            if (generationIds.isEmpty()) {
                return null;
            }
            List<SObject> feedback = dao.getFeedbackForGenerations(generationIds);
            Integer accepted = 0;
            Integer rejected = 0;
            for (SObject f : feedback) {
                if (isPositiveFeedback(f)) {
                    accepted++;
                } else if (isNegativeFeedback(f)) {
                    rejected++;
                }
            }
            Integer denom = accepted + rejected;
            if (denom == 0) {
                return null;
            }
            return ((Decimal) accepted / denom).setScale(4);
        } catch (Exception ex) {
            return null;
        }
    }

    /**
     * Return the weaker of two confidence bands so a roll-up reflects the
     * lowest-quality input (HIGH > ESTIMATED > FALLBACK > NOT_COSTED).
     * Treats null/blank as HIGH to avoid polluting otherwise-clean rollups.
     */
    @TestVisible
    private static String weakerConfidence(String a, String b) {
        Map<String, Integer> rank = new Map<String, Integer>{
            CostCalculatorService.CONFIDENCE_HIGH => 3,
            CostCalculatorService.CONFIDENCE_ESTIMATED => 2,
            CostCalculatorService.CONFIDENCE_FALLBACK => 1,
            CostCalculatorService.CONFIDENCE_NOT_COSTED => 0
        };
        Integer ra = a == null || !rank.containsKey(a) ? rank.get(CostCalculatorService.CONFIDENCE_HIGH) : rank.get(a);
        Integer rb = b == null || !rank.containsKey(b) ? rank.get(CostCalculatorService.CONFIDENCE_HIGH) : rank.get(b);
        return ra <= rb ? a : b;
    }

    // ───────────────────────── Helpers: join maps ────────────────

    private Set<String> collectBusinessKeys(List<SObject> records, String field) {
        Set<String> keys = new Set<String>();
        for (SObject r : records) {
            String v = (String) r.get(field);
            if (String.isNotBlank(v)) {
                keys.add(v);
            }
        }
        return keys;
    }

    private Map<String, String> buildGenerationToUserMap(Set<String> requestIds, Map<String, String> requestIdToUser) {
        return buildGenerationToKeyMap(requestIds, requestIdToUser);
    }

    private Map<String, String> buildGenerationToKeyMap(Set<String> requestIds, Map<String, String> requestIdToKey) {
        Map<String, String> generationToKey = new Map<String, String>();
        if (requestIds == null || requestIds.isEmpty()) {
            return generationToKey;
        }
        List<SObject> responses = dao.getResponsesForRequests(requestIds);
        Map<String, String> responseToRequest = new Map<String, String>();
        for (SObject resp : responses) {
            responseToRequest.put(
                (String) resp.get('generationResponseId__c'),
                (String) resp.get('generationRequestId__c')
            );
        }
        if (responseToRequest.isEmpty()) {
            return generationToKey;
        }
        List<SObject> generations = dao.getGenerationsForResponses(responseToRequest.keySet());
        for (SObject g : generations) {
            String genId = (String) g.get('generationId__c');
            String respId = (String) g.get('generationResponseId__c');
            String reqId = responseToRequest.get(respId);
            if (genId != null && reqId != null && requestIdToKey.containsKey(reqId)) {
                generationToKey.put(genId, requestIdToKey.get(reqId));
            }
        }
        return generationToKey;
    }

    private Map<String, String> selfMap(Set<String> values) {
        Map<String, String> out = new Map<String, String>();
        for (String v : values) {
            out.put(v, v);
        }
        return out;
    }

    // ───────────────────────── Helpers: grouping ─────────────────

    private String resolveTokenGroupKey(SObject r, String groupBy) {
        if (groupBy == 'user') {
            String v = (String) r.get('userId__c');
            return v == null ? SYSTEM_SENTINEL : v;
        }
        if (groupBy == 'prompt') {
            return (String) r.get('promptTemplateDevName__c');
        }
        if (groupBy == 'model') {
            return (String) r.get('model__c');
        }
        if (groupBy == 'day' || groupBy == 'week') {
            DateTime ts = (DateTime) r.get('timestamp__c');
            if (ts == null) {
                return null;
            }
            return groupBy == 'day' ? formatDayBucket(ts) : formatWeekBucket(ts);
        }
        throw new IllegalArgumentException('Unsupported groupBy: ' + groupBy);
    }

    private String resolveExplorerGroupKey(SObject r, String groupBy) {
        String normalized = groupBy == null ? null : groupBy.toLowerCase();
        if (normalized == 'user') {
            String v = (String) r.get('userId__c');
            return v == null ? SYSTEM_SENTINEL : v;
        }
        if (normalized == 'prompttemplate') {
            return (String) r.get('promptTemplateDevName__c');
        }
        if (normalized == 'feature') {
            return (String) r.get('feature__c');
        }
        if (normalized == 'model') {
            return (String) r.get('model__c');
        }
        if (normalized == 'day' || normalized == 'week') {
            DateTime ts = (DateTime) r.get('timestamp__c');
            if (ts == null) {
                return null;
            }
            return normalized == 'day' ? formatDayBucket(ts) : formatWeekBucket(ts);
        }
        throw new IllegalArgumentException('Unsupported groupBy: ' + groupBy);
    }

    private Map<String, String> resolveGroupLabels(Set<String> keys, String groupBy) {
        Map<String, String> out = new Map<String, String>();
        if (keys == null || keys.isEmpty()) {
            return out;
        }
        String normalized = groupBy == null ? null : groupBy.toLowerCase();
        if (normalized == 'user') {
            Map<String, String> names = resolver.resolveUserNames(keys);
            for (String k : keys) {
                out.put(k, names.containsKey(k) ? names.get(k) : k);
            }
        } else if (normalized == 'prompt' || normalized == 'prompttemplate') {
            Map<String, String> labels = resolver.resolvePromptTemplateLabels(keys);
            for (String k : keys) {
                out.put(k, labels.containsKey(k) ? labels.get(k) : k);
            }
        } else {
            // model, feature, day, week — key already IS the label
            for (String k : keys) {
                out.put(k, k);
            }
        }
        return out;
    }

    @TestVisible
    private static String formatDayBucket(DateTime ts) {
        return ts.formatGmt('yyyy-MM-dd');
    }

    @TestVisible
    private static String formatWeekBucket(DateTime ts) {
        // ISO-style "yyyy-Www" — Apex DateTime lacks ISO week, so approximate
        // by zero-padding the week-of-year. Still sortable and consistent.
        Date d = ts.dateGmt();
        Integer year = d.year();
        Integer weekOfYear = (Integer) (d.dayOfYear() / 7) + 1;
        String weekStr = weekOfYear < 10 ? '0' + weekOfYear : String.valueOf(weekOfYear);
        return year + '-W' + weekStr;
    }

    @TestVisible
    private static String formatRangeLabel(DateRangeFilter filter) {
        Long days = (filter.endDate.getTime() - filter.startDate.getTime()) / (1000L * 60L * 60L * 24L);
        return 'Last ' + String.valueOf(days) + ' days';
    }

    // ───────────────────────── Helpers: top-N ────────────────────

    private static List<String> topNKeys(Map<String, Integer> counts, Integer n) {
        if (counts.isEmpty()) {
            return new List<String>();
        }
        List<CountedKey> wrapped = new List<CountedKey>();
        for (String k : counts.keySet()) {
            wrapped.add(new CountedKey(k, counts.get(k)));
        }
        wrapped.sort();
        List<String> out = new List<String>();
        Integer cap = Math.min(n, wrapped.size());
        for (Integer i = 0; i < cap; i++) {
            out.add(wrapped[i].key);
        }
        return out;
    }

    // ───────────────────────── Comparators ───────────────────────

    private class CountedKey implements Comparable {
        public String key;
        public Integer count;
        public CountedKey(String key, Integer count) {
            this.key = key;
            this.count = count;
        }
        public Integer compareTo(Object other) {
            CountedKey that = (CountedKey) other;
            if (this.count == that.count) {
                return 0;
            }
            return this.count < that.count ? 1 : -1;
        }
    }

    private class UserUsageByCountDesc implements Comparator<UserUsageDTO> {
        public Integer compare(UserUsageDTO a, UserUsageDTO b) {
            if (a.requestCount == b.requestCount) {
                return 0;
            }
            return a.requestCount < b.requestCount ? 1 : -1;
        }
    }

    private class PromptUsageByCountDesc implements Comparator<PromptUsageDTO> {
        public Integer compare(PromptUsageDTO a, PromptUsageDTO b) {
            if (a.invocationCount == b.invocationCount) {
                return 0;
            }
            return a.invocationCount < b.invocationCount ? 1 : -1;
        }
    }

    private class PromptOutputByDateDesc implements Comparator<PromptOutputDTO> {
        public Integer compare(PromptOutputDTO a, PromptOutputDTO b) {
            if (a.requestDate == null && b.requestDate == null) {
                return 0;
            }
            if (a.requestDate == null) {
                return 1;
            }
            if (b.requestDate == null) {
                return -1;
            }
            if (a.requestDate == b.requestDate) {
                return 0;
            }
            return a.requestDate < b.requestDate ? 1 : -1;
        }
    }

    private class TokenByTotalDesc implements Comparator<TokenConsumptionDTO> {
        public Integer compare(TokenConsumptionDTO a, TokenConsumptionDTO b) {
            if (a.totalTokens == b.totalTokens) {
                return 0;
            }
            return a.totalTokens < b.totalTokens ? 1 : -1;
        }
    }

    private class ExplorerByMetricDesc implements Comparator<ExplorerResultDTO> {
        public Integer compare(ExplorerResultDTO a, ExplorerResultDTO b) {
            if (a.metricValue == b.metricValue) {
                return 0;
            }
            return a.metricValue < b.metricValue ? 1 : -1;
        }
    }

    // ═════════════════════════ Filter rail support ═══════════════════════
    //
    // These methods back the new dynamic filter rail (aiInsightsFilterRail).
    // They are deliberately read-only and narrow — building the filter UX is
    // not the place for business logic, so the service just turns DMO data
    // into label/value lists the LWC can drop straight into comboboxes.

    /**
     * Merge legacy `ExplorerRequest.filters` (the single-value map that still
     * backs the feedbackValue pill) with the rail's new `criteria` bag. Either
     * or both may arrive from the LWC depending on which surface fired the
     * request. The rail wins for any dimension it sets; the legacy map only
     * contributes `model` / `feature` values when `criteria` left them empty,
     * so existing Explorer cards keep working unchanged.
     */
    @TestVisible
    private Boolean hasDimensionFilters(FilterCriteria c) {
        return (c.userIds != null && !c.userIds.isEmpty()) ||
            (c.promptTemplateDevNames != null && !c.promptTemplateDevNames.isEmpty()) ||
            (c.models != null && !c.models.isEmpty()) ||
            (c.providers != null && !c.providers.isEmpty()) ||
            (c.features != null && !c.features.isEmpty()) ||
            (c.appTypes != null && !c.appTypes.isEmpty());
    }

    // Maps a normalised entity type to the DMO field used as the anchor
    // equality clause (e.g. userId__c for the User drill-in). Returns null
    // for entity types that don't map to a single filterable field.
    private String anchorFieldForType(String normalizedType) {
        if (normalizedType == 'user')
            return 'userId__c';
        if (normalizedType == 'prompttemplate')
            return 'promptTemplateDevName__c';
        if (normalizedType == 'model')
            return 'model__c';
        if (normalizedType == 'feature')
            return 'feature__c';
        return null;
    }

    // Overload that accepts a pre-built FilterCriteria (no ExplorerRequest).
    // Used by the entity-detail path.
    @TestVisible
    private FilterCriteria normalizeCriteria(FilterCriteria inbound) {
        if (inbound == null)
            return null;
        return inbound;
    }

    @TestVisible
    private FilterCriteria normalizeCriteria(ExplorerRequest req, DateRangeFilter filter) {
        FilterCriteria out = req.criteria == null ? new FilterCriteria() : req.criteria;
        out.startDate = filter.startDate;
        out.endDate = filter.endDate;

        Map<String, String> legacy = req.filters == null ? new Map<String, String>() : req.filters;
        String legacyModel = legacy.get('model');
        if (String.isNotBlank(legacyModel) && (out.models == null || out.models.isEmpty())) {
            out.models = new List<String>{ legacyModel };
        }
        String legacyFeature = legacy.get('feature');
        if (String.isNotBlank(legacyFeature) && (out.features == null || out.features.isEmpty())) {
            out.features = new List<String>{ legacyFeature };
        }
        return out;
    }

    /**
     * Populate every multi-select combobox in the filter rail with the set of
     * values actually present in the current date window. Running one
     * lightweight aggregate per dimension keeps the round-trip under ~6
     * GROUP BY queries, all cacheable via `@AuraEnabled(cacheable=true)`.
     *
     * `topUsers` is capped at `topUserLimit` (default 100) because user
     * cardinality is unbounded — anything beyond that comes through the
     * `searchUsersInRange` typeahead.
     *
     * Prompt templates are sorted by request count desc and capped at 200
     * (enough to cover any realistic org without dragging the DTO into
     * cacheable-size territory).
     */
    public virtual FilterFacetsDTO getFilterFacets(DateRangeFilter filter, Integer topUserLimit) {
        validateFilter(filter);
        Integer userCap = (topUserLimit == null || topUserLimit <= 0) ? 100 : topUserLimit;
        FilterFacetsDTO out = new FilterFacetsDTO();
        out.models = collectFacet('model__c', filter, 500);
        out.providers = collectFacet('provider__c', filter, 100);
        out.features = collectFacet('feature__c', filter, 200);
        out.appTypes = collectFacet('appType__c', filter, 200);
        out.promptTemplates = collectPromptFacet(filter, 200);
        out.topUsers = collectTopUsersFacet(filter, userCap);
        return out;
    }

    private List<FilterFacetsDTO.FacetOption> collectFacet(String fieldName, DateRangeFilter filter, Integer maxRows) {
        List<FilterFacetsDTO.FacetOption> out = new List<FilterFacetsDTO.FacetOption>();
        try {
            List<AggregateResult> rows = dao.getDistinctFieldValues(fieldName, filter.startDate, filter.endDate);
            List<FilterFacetsDTO.FacetOption> tmp = new List<FilterFacetsDTO.FacetOption>();
            for (AggregateResult a : rows) {
                String val = (String) a.get('gkey');
                if (String.isBlank(val)) {
                    continue;
                }
                tmp.add(new FilterFacetsDTO.FacetOption(val, val, toInteger(a.get('cnt'))));
            }
            // DMO SOQL can't ORDER BY COUNT — sort in Apex (popular first).
            tmp.sort(new FacetCountDesc());
            Integer n = Math.min(tmp.size(), maxRows == null ? tmp.size() : maxRows);
            for (Integer i = 0; i < n; i++) {
                out.add(tmp[i]);
            }
        } catch (Exception e) {
            // Facet failure shouldn't crash the rail — leave the list empty
            // and let the LWC render a disabled combobox for that dimension.
        }
        return out;
    }

    private List<FilterFacetsDTO.FacetOption> collectPromptFacet(DateRangeFilter filter, Integer maxRows) {
        List<FilterFacetsDTO.FacetOption> out = new List<FilterFacetsDTO.FacetOption>();
        try {
            List<AggregateResult> rows = dao.getDistinctFieldValues(
                'promptTemplateDevName__c',
                filter.startDate,
                filter.endDate
            );
            List<FilterFacetsDTO.FacetOption> tmp = new List<FilterFacetsDTO.FacetOption>();
            Set<String> rawDevNames = new Set<String>();
            for (AggregateResult a : rows) {
                String val = (String) a.get('gkey');
                if (String.isBlank(val)) {
                    continue;
                }
                tmp.add(new FilterFacetsDTO.FacetOption(val, val, toInteger(a.get('cnt'))));
                rawDevNames.add(val);
            }
            tmp.sort(new FacetCountDesc());
            // Resolve labels so the rail shows human-friendly prompt names
            // (master labels when available, otherwise humanized dev names).
            Map<String, String> labels = resolver.resolvePromptTemplateLabels(rawDevNames);
            for (FilterFacetsDTO.FacetOption opt : tmp) {
                String label = labels.get(opt.value);
                if (String.isNotBlank(label)) {
                    opt.label = label;
                }
            }
            Integer n = Math.min(tmp.size(), maxRows == null ? tmp.size() : maxRows);
            for (Integer i = 0; i < n; i++) {
                out.add(tmp[i]);
            }
        } catch (Exception e) {
            // No-op — empty facet list
        }
        return out;
    }

    private List<FilterFacetsDTO.FacetOption> collectTopUsersFacet(DateRangeFilter filter, Integer maxRows) {
        List<FilterFacetsDTO.FacetOption> out = new List<FilterFacetsDTO.FacetOption>();
        try {
            List<AggregateResult> rows = dao.getDistinctUserAggregates(filter.startDate, filter.endDate);
            List<FilterFacetsDTO.FacetOption> tmp = new List<FilterFacetsDTO.FacetOption>();
            Set<String> ids = new Set<String>();
            for (AggregateResult a : rows) {
                String uid = (String) a.get('gkey');
                if (String.isBlank(uid)) {
                    continue;
                }
                tmp.add(new FilterFacetsDTO.FacetOption(uid, uid, toInteger(a.get('cnt'))));
                ids.add(uid);
            }
            tmp.sort(new FacetCountDesc());
            Integer n = Math.min(tmp.size(), maxRows == null ? tmp.size() : maxRows);
            // Resolve only the top N so we don't query User for every id in
            // the window — on large orgs that slice can be thousands.
            Set<String> topIds = new Set<String>();
            for (Integer i = 0; i < n; i++) {
                topIds.add(tmp[i].value);
            }
            Map<String, String> names = resolver.resolveUserNames(topIds);
            for (Integer i = 0; i < n; i++) {
                FilterFacetsDTO.FacetOption opt = tmp[i];
                String nm = names.get(opt.value);
                if (String.isNotBlank(nm)) {
                    opt.label = nm;
                }
                out.add(opt);
            }
        } catch (Exception e) {
            // No-op
        }
        return out;
    }

    /**
     * Typeahead support for the user filter. Returns users observed in the
     * range whose resolved display name matches `term` (case-insensitive,
     * substring). Server-side matching on resolved names — no User SOQL
     * LIKE, so deactivated / cross-org users still show up as their
     * fallback label ("Unknown User (<id>)") and remain filterable.
     *
     * `term` under 2 chars returns an empty list to avoid an expensive
     * full-range resolve on every keystroke; the LWC waits until the user
     * has typed at least two characters.
     */
    public virtual List<FilterFacetsDTO.FacetOption> searchUsersInRange(
        String term,
        DateRangeFilter filter,
        Integer maxRows
    ) {
        validateFilter(filter);
        Integer cap = (maxRows == null || maxRows <= 0) ? 25 : maxRows;
        if (String.isBlank(term) || term.trim().length() < 2) {
            return new List<FilterFacetsDTO.FacetOption>();
        }
        String needle = term.trim().toLowerCase();
        List<FilterFacetsDTO.FacetOption> out = new List<FilterFacetsDTO.FacetOption>();
        try {
            List<AggregateResult> rows = dao.getDistinctUserAggregates(filter.startDate, filter.endDate);
            Set<String> ids = new Set<String>();
            Map<String, Integer> counts = new Map<String, Integer>();
            for (AggregateResult a : rows) {
                String uid = (String) a.get('gkey');
                if (String.isBlank(uid)) {
                    continue;
                }
                ids.add(uid);
                counts.put(uid, toInteger(a.get('cnt')));
            }
            if (ids.isEmpty()) {
                return out;
            }
            Map<String, String> names = resolver.resolveUserNames(ids);
            List<FilterFacetsDTO.FacetOption> matches = new List<FilterFacetsDTO.FacetOption>();
            for (String uid : ids) {
                String nm = names.get(uid);
                if (String.isBlank(nm)) {
                    continue;
                }
                if (nm.toLowerCase().contains(needle)) {
                    matches.add(new FilterFacetsDTO.FacetOption(uid, nm, counts.get(uid)));
                }
            }
            matches.sort(new FacetCountDesc());
            Integer n = Math.min(matches.size(), cap);
            for (Integer i = 0; i < n; i++) {
                out.add(matches[i]);
            }
        } catch (Exception e) {
            // Swallow — empty list tells the LWC "no matches"
        }
        return out;
    }

    private class FacetCountDesc implements Comparator<FilterFacetsDTO.FacetOption> {
        public Integer compare(FilterFacetsDTO.FacetOption a, FilterFacetsDTO.FacetOption b) {
            Integer ac = a.count == null ? 0 : a.count;
            Integer bc = b.count == null ? 0 : b.count;
            if (ac == bc) {
                return 0;
            }
            return ac < bc ? 1 : -1;
        }
    }
}
