/**
 * Central tooltip copy for every FluentMetric AI dashboard.
 *
 * Keys are grouped by dashboard name so each component can import and
 * reference its own slice (e.g. TOOLTIPS.overview.totalRequests). The
 * language is deliberately consistent across dashboards: each entry
 * names the metric, explains how it is calculated (SUM / COUNT / RATIO
 * of a specific DMO field), and notes caveats where they matter.
 *
 * Everything that renders as a column header, card label, or axis label
 * should be wrapped in a `<lightning-helptext content={tooltips.x}>` so
 * users can self-serve the meaning of any metric without leaving the
 * dashboard.
 */

export const TOOLTIPS = {
    // ─── Overview (Phase 2 retrofit) ─────────────────────────────────────
    overview: {
        totalRequests:
            'Total number of Einstein Generative AI requests in the selected range. ' +
            'Calculated as COUNT(Id) on GenAIGatewayRequest__dlm filtered by timestamp__c. ' +
            'Includes system calls (user shown as NOT_SET) alongside end-user requests.',
        uniqueUsers:
            'Distinct users who triggered at least one AI request. ' +
            'COUNT(DISTINCT userId__c) on GenAIGatewayRequest__dlm. ' +
            'The "NOT_SET" sentinel (system calls) is bucketed separately and not counted as a user.',
        uniquePromptTemplates:
            'Distinct prompt templates invoked in the range. ' +
            'COUNT(DISTINCT promptTemplateDevName__c) on GenAIGatewayRequest__dlm. ' +
            'Empty template names are filtered out.',
        totalInputTokens:
            'Total input tokens sent to the model. ' +
            'SUM of inputTokenCount__c on GenAIGatewayRequest__dlm.',
        totalOutputTokens:
            'Total output tokens returned by the model. ' +
            'SUM of outputTokenCount__c on GenAIGatewayRequest__dlm.',
        acceptanceRate:
            'Share of feedback events that were positive (thumbs_up / accepted). ' +
            'Calculated as positive feedback / total feedback on GenAIGatewayFeedback__dlm. ' +
            'Shows 0% when no feedback exists in the range — common for system calls and background agents.',
        feedbackCount:
            'Total feedback events recorded in the range. ' +
            'COUNT(Id) on GenAIGatewayFeedback__dlm. ' +
            'Feedback is often sparse — most internal calls never receive thumbs-up / thumbs-down.',
        toxicFlagCount:
            'Number of generations flagged by the safety classifier. ' +
            'COUNT on GenAIContentQuality__dlm where isToxicityDetected__c = "true". ' +
            'A value of 0 means nothing was flagged — not that safety scoring was skipped.',
        estimatedUsd:
            'Estimated USD for this date range: tokens × rate-card USD/call, with the org\'s discount applied. ' +
            'Derived by CostCalculatorService from FluentMetric_Rate_Card__mdt joined on model name. ' +
            'Uses the Standard-tier fallback for models not in the rate card.',
        estimatedFlexCredits:
            'Total Agentforce Flex Credits consumed. Each prompt tier has a fixed FC cost per call ' +
            '(Basic=2, Standard=4, Advanced=16). SUM of Flex_Credits_Per_Call__c over requests in the range.',
        highlights:
            'Headline leaders for this date range: the most active user, most-invoked prompt template, ' +
            'heaviest-token-consuming model, and top calling feature. Each is computed from GROUP BY aggregates ' +
            'on GenAIGatewayRequest__dlm and reflects the same scope as the KPI cards below.',
        wowBadge:
            'Week-over-week change for this metric: latest complete week vs. the prior week. ' +
            'Computed in Apex from GROUP BY week aggregates on GenAIGatewayRequest__dlm. ' +
            'Hidden when the prior window is empty so we never show "+Infinity%".',
        paretoChip:
            'Pareto check on engagement: the share of total requests driven by the top 10% of active users. ' +
            'Sourced from PowerUserSegmentsDTO. A high number means usage concentrates in a few power users — ' +
            'expand the User Adoption tab to see who, and target them for advanced training first.',
        entitledDenominator:
            'Adoption rate uses an entitled-user denominator: distinct active users in the range divided by ' +
            'users assigned to the FluentMetric_AI_Entitled_User permission set. When that permset has no ' +
            'assignees in this org the denominator falls back to total active org users and a tip is shown ' +
            'so admins know to assign the permset to the people expected to use Einstein Generative AI.'
    },

    // ─── User Adoption (Phase 2 retrofit) ────────────────────────────────
    userAdoption: {
        clickToDrill:
            'Click to see this user\'s recent requests and usage stats.',
        userName:
            'The end user who triggered the requests. Resolved from GenAIGatewayRequest__dlm.userId__c via User SOQL lookup. ' +
            'System calls appear as "System Call" from the NOT_SET sentinel.',
        profileName:
            'User profile at the time of resolution. Sourced from User.Profile.Name. ' +
            'May be blank for integration users or external actors.',
        department:
            'User department from the User record. Frequently blank when the org has not populated department fields.',
        requestCount:
            'Total AI requests made by this user. ' +
            'COUNT(Id) on GenAIGatewayRequest__dlm grouped by userId__c. Default sort column.',
        firstUsed:
            'Earliest request timestamp for this user within the range. ' +
            'MIN(timestamp__c) on GenAIGatewayRequest__dlm.',
        lastUsed:
            'Most recent request timestamp for this user within the range. ' +
            'MAX(timestamp__c) on GenAIGatewayRequest__dlm.',
        feedbackRatio:
            'Share of this user\'s feedback events that were positive. ' +
            'Positive feedback / total feedback on GenAIGatewayFeedback__dlm. ' +
            'Shows "—" when this user has submitted no feedback — common and not a problem.',
        topPrompts:
            'Up to three most-used prompt templates for this user, ranked by invocation count. ' +
            'Derived by joining user aggregates with user-and-prompt aggregates in Apex.',
        totalTokens:
            'Sum of input + output tokens across all this user\'s requests. ' +
            'SUM(inputTokenCount__c + outputTokenCount__c) on GenAIGatewayRequest__dlm.'
    },

    // ─── Prompt Analytics ────────────────────────────────────────────────
    promptAnalytics: {
        promptLabel:
            'Human-readable prompt template name. Resolved from GenAiPromptTemplate.MasterLabel ' +
            'via the developer name on GenAIGatewayRequest__dlm.promptTemplateDevName__c.',
        featureName:
            'The feature that owns the prompt (e.g. Sales Emails, Agentforce Copilot). ' +
            'Sourced from GenAIGatewayRequest__dlm.featureName__c.',
        invocationCount:
            'Total times this prompt was invoked in the range. ' +
            'COUNT(Id) on GenAIGatewayRequest__dlm grouped by promptTemplateDevName__c. Default sort column.',
        uniqueUserCount:
            'Distinct users who invoked this prompt. ' +
            'COUNT(DISTINCT userId__c) within the prompt group.',
        acceptanceRate:
            'Share of feedback on this prompt that was positive. ' +
            'Positive feedback / total feedback on GenAIGatewayFeedback__dlm filtered to this prompt. ' +
            'Shows 0% when this prompt has no feedback yet — common for low-traffic or system prompts.',
        avgTokens:
            'Average tokens per invocation (input + output). ' +
            'Derived as SUM(tokens) / COUNT(requests) for this prompt. ' +
            'Useful for spotting unexpectedly large prompts before they hit quota.',
        totalTokens:
            'Total tokens consumed by this prompt in the range. ' +
            'SUM(inputTokenCount__c + outputTokenCount__c) grouped by promptTemplateDevName__c.',
        toxicFlagCount:
            'Generations from this prompt that the safety classifier flagged. ' +
            'COUNT on GenAIContentQuality__dlm where isToxicityDetected__c = "true", joined by business key.',
        firstUsed:
            'First time this prompt was invoked in the selected range. MIN(timestamp__c).',
        lastUsed:
            'Most recent invocation of this prompt in the range. MAX(timestamp__c).'
    },

    // ─── Prompt Output Viewer ────────────────────────────────────────────
    promptOutputViewer: {
        userName:
            'User who triggered this specific request. Resolved from GenAIGatewayRequest__dlm.userId__c.',
        requestDate:
            'Timestamp of the request. timestamp__c on GenAIGatewayRequest__dlm.',
        inputPrompt:
            'The fully-hydrated prompt sent to the model, including retrieved context. ' +
            'Sourced from GenAIGatewayRequest__dlm.requestMessage__c (or equivalent payload field). ' +
            'Truncated to 200 characters in the collapsed card view.',
        generatedText:
            'The model\'s response for this request. Sourced from GenAIGatewayGeneration__dlm.generatedText__c. ' +
            'Truncated to 200 characters in the collapsed card view.',
        feedbackValue:
            'User feedback on this specific output, if any. ' +
            'Values: thumbs_up, thumbs_down, accepted, edited, rejected. ' +
            'Blank means no feedback was submitted — which is the common case.',
        isToxic:
            'True when the safety classifier flagged this output. ' +
            'Sourced from GenAIContentQuality__dlm.isToxicityDetected__c.',
        inputTokens:
            'Input tokens for this specific request. inputTokenCount__c on GenAIGatewayRequest__dlm.',
        outputTokens:
            'Output tokens for this specific request. outputTokenCount__c on GenAIGatewayRequest__dlm.',
        model:
            'LLM used for this generation (e.g. gpt-4, claude-3-sonnet). ' +
            'Sourced from GenAIGatewayRequest__dlm.modelName__c.'
    },

    // ─── Token Consumption ───────────────────────────────────────────────
    tokenConsumption: {
        clickToDrill:
            'Click to see the full request detail for this group.',
        groupLabel:
            'The group this row represents (prompt, user, model, day, or week) — depending on the Group By selector.',
        inputTokens:
            'Input tokens consumed by this group. ' +
            'SUM(inputTokenCount__c) on GenAIGatewayRequest__dlm.',
        outputTokens:
            'Output tokens generated for this group. ' +
            'SUM(outputTokenCount__c) on GenAIGatewayRequest__dlm.',
        totalTokens:
            'Input + output tokens for this group. Used to rank bars and to build the "Others" bucket.',
        requestCount:
            'Number of requests contributing to this row. COUNT(Id) within the group.',
        avgTokensPerRequest:
            'Mean tokens per request for this group. ' +
            'totalTokens / requestCount. Useful for spotting outsized prompts.'
    },

    // ─── Safety ──────────────────────────────────────────────────────────
    safety: {
        totalGenerations:
            'Generations inspected by the safety classifier in the range. ' +
            'COUNT(Id) on GenAIContentQuality__dlm.',
        toxicCount:
            'Generations flagged as toxic. COUNT where isToxicityDetected__c = "true" on GenAIContentQuality__dlm.',
        toxicRate:
            'Share of inspected generations that were flagged. toxicCount / totalGenerations. ' +
            'Shows 0% when nothing was flagged — common and desired.',
        categoryScore:
            'Average safety score (0-1) for this category across all generations in the range. ' +
            'Closer to 0 is safer; the color band turns yellow above 0.3 and red above 0.7. ' +
            'Sourced from category-specific score fields on GenAIContentQuality__dlm.',
        flaggedCount:
            'Generations flagged by this specific category. ' +
            'COUNT on GenAIContentQuality__dlm where the category threshold was exceeded.'
    },

    // ─── App shell (tab tooltips) ────────────────────────────────────────
    app: {
        tabOverview:
            'Glanceable KPIs — total requests, unique users, acceptance rate, token volume, feedback, and safety flags for the selected date range.',
        tabAdoption:
            'Adoption — funnel from active org users → entitled → active in window, top contributors leaderboard, per-user table, feature breadth, and cohort retention.',
        tabExplorer:
            'Dynamic pivot — pick a Group By + Metric + optional filters, and the controller runs a custom aggregation. Preset chips load common pivots in one click.',
        tabSafety:
            'Content-safety scoring — flagged rate, daily cadence, category breakdown, and recent flagged outputs.',
        tabCost:
            'Cost analysis — Wallet actuals when available, or tier-based Flex Credit estimates. Confidence badges show whether each figure is ACTUAL, HIGH, ESTIMATED, FALLBACK, or NOT_COSTED.',
        // Legacy keys retained so older bindings keep rendering during the IA
        // refactor rollout — safe to remove after the deploy lands.
        tabActivity:
            'Activity — superseded by Adoption + Explorer + Cost in the refactored navigation.',
        tabUsers:
            'Per-user adoption — moved to the Adoption tab.',
        tabTokens:
            'Token consumption — moved to the Explorer tab; use the "Tokens by user" or "Tokens by day" preset chip.'
    },

    // ─── Adoption tab container ──────────────────────────────────────────
    adoption: {
        tabHeading:
            'Adoption shows you the journey from "could use AI" to "uses AI heavily" — funnel, leaderboard, per-user activity, feature breadth, and cohort retention all in one place.',
        funnelStage:
            'Each funnel stage is the count of users that survived the previous gate: Active org users (anyone licensed) → Entitled (assigned to the FluentMetric_AI_Entitled_User permission set) → Active in window (made at least one request in the selected range).',
        contributorRank:
            'Top contributors are the highest-volume users in the date range. Toggle between Tokens (sum of input + output) and Requests (count of GenAIGatewayRequest__dlm rows) — the bar lengths normalize against the leader so the ranking is visually obvious.',
        activeOrgUsers:
            'Distinct active users in this org (User.IsActive = true). The ceiling for who could ever use Einstein Generative AI — independent of permission-set entitlement or actual activity.',
        entitled:
            'Users assigned to the FluentMetric_AI_Entitled_User permission set — the people you expect to be using AI. Adjust assignments to sharpen the adoption denominator. When the permset has no assignees, the funnel falls back to total active org users.',
        activeInWindow:
            'Users who triggered at least one Einstein Generative AI request inside the selected date range. The realized layer of the funnel — DISTINCT userId__c on GenAIGatewayRequest__dlm filtered by timestamp__c.',
        entitledDenominator:
            'Adoption rate uses an entitled-user denominator: active users in the range divided by users assigned to the FluentMetric_AI_Entitled_User permission set. When that permset has no assignees, the denominator falls back to total active org users so the metric still renders.',
        perUserAdoption:
            'Per-user activity table for the selected range. Click a row to drill into recent requests, prompt mix, and feedback ratio for that user. Sort by any column.',
        cohortRetention:
            'Weekly retention heatmap. Each cell shows the share of week-N users who came back in week-N+k. Reads top-left to bottom-right; darker cells are stronger retention.',
        featureAdoption:
            'Breadth view: which Einstein Generative AI features (Sales Email, Agentforce, Prompt Builder, etc.) are getting traction in the selected range. Sourced from GenAIGatewayRequest__dlm.featureName__c grouped by feature.'
    },

    // ─── Cost tab container ──────────────────────────────────────────────
    cost: {
        tabHeading:
            'Cost is computed Wallet-first: when Enable_Wallet_Costs__c is on AND TenantEnrichedUsageEvent__dll is queryable, figures come from Salesforce Digital Wallet (the same data Salesforce uses to bill you). Otherwise, FluentMetric_Rate_Card__mdt × token counts produces a tier-based estimate.',
        rateCardSettings:
            'Adjust USD-per-Flex-Credit, the contracted discount, and the fallback model used when a rate card has no exact match. Saves to FluentMetric_Cost_Settings__c — admins only.'
    },

    // ─── Explorer presets (chips above the pivot controls) ──────────────
    explorerPresets: {
        topPrompts:
            'One-click pivot: Group by Prompt Template, metric = Total Tokens. Equivalent to picking those values manually — useful for spotting which prompts dominate token spend.',
        tokensByUser:
            'One-click pivot: Group by User, metric = Total Tokens. Surfaces the heaviest token consumers regardless of feedback or feature.',
        tokensByDay:
            'One-click pivot: Group by Day, metric = Total Tokens. Shows token-volume trend over time inside the selected range.',
        acceptanceByPrompt:
            'One-click pivot: Group by Prompt Template, metric = Acceptance Rate. Use to find prompts where users are dissatisfied (low acceptance) regardless of volume.'
    },

    // ─── Entity Details modal (drill-in from any table row) ─────────────
    entityDetails: {
        modalHeader:
            'Drill-in view for a single entity — user, prompt template, model, or feature. ' +
            'Stats and recent requests are scoped to the currently-selected dashboard date range.',
        entityKey:
            'The raw key used internally (userId, prompt developer name, model name, or feature name). ' +
            'Shown below the label so it is unambiguous which entity is being inspected.',
        requestCount:
            'Total requests attributed to this entity in the selected range. ' +
            'COUNT(Id) on GenAIGatewayRequest__dlm scoped by entity.',
        totalTokens:
            'Sum of input + output tokens across every request attributed to this entity. ' +
            'SUM(inputTokenCount__c + outputTokenCount__c) on GenAIGatewayRequest__dlm.',
        avgTokensPerRequest:
            'Mean tokens per request for this entity. totalTokens / requestCount. ' +
            'Useful for spotting unusually large prompts or outputs.',
        firstUsed:
            'Earliest request timestamp attributed to this entity within the range. ' +
            'Shown as a relative time; hover for the exact timestamp.',
        lastUsed:
            'Most recent request timestamp attributed to this entity within the range. ' +
            'Shown as a relative time; hover for the exact timestamp.',
        acceptanceRate:
            'Share of feedback events for this entity that were positive (thumbs_up / accepted). ' +
            'Green above 70%, yellow 50-70%, red below 50%. Shows "—" when no feedback exists.',
        toxicFlagCount:
            'Generations from this entity that the safety classifier flagged. ' +
            'Red when > 0, green when 0 (not that safety scoring was skipped).',
        uniqueUserCount:
            'Distinct users who contributed requests for this entity. Hidden when the entity itself is a user.',
        uniquePromptCount:
            'Distinct prompt templates invoked for this entity. Hidden when the entity itself is a prompt template.'
    },

    // ─── Full-text modal (expand) ────────────────────────────────────────
    textModal: {
        expandInput:
            'Open the full untruncated input prompt in a modal where you can scroll and copy.',
        expandOutput:
            'Open the full untruncated generated output in a modal where you can scroll and copy.',
        copy:
            'Copy the full text to your clipboard. A confirmation appears next to the button when the copy succeeds.',
        close:
            'Close the modal. Clicking the backdrop or pressing Escape also closes it.'
    },

    // ─── Cost confidence badges ──────────────────────────────────────────
    costConfidence: {
        ACTUAL:
            'Actual cost from Salesforce Digital Wallet. These Flex Credits are read directly from the ' +
            'TenantEnrichedUsageEvent Data Lake Object — the same data Salesforce uses to bill you. ' +
            'No estimation; the figure matches what your org\'s Consumption Analytics dashboard shows. ' +
            'Wallet data is only available in Wallet-enabled production orgs with the Consumption Tagging app installed.',
        HIGH:
            'High confidence. The model was matched exactly to an entry in FluentMetric_Rate_Card__mdt, ' +
            'the correct tier-based Flex Credit rate was applied, and (for Agentforce traffic) STDM ' +
            'session data was present so Actions were priced at their true flat 20-FC rate.',
        ESTIMATED:
            'Estimated cost. The model name was not an exact match in the rate card, so the resolver ' +
            'walked through prefix / version-suffix matches to find the closest tier. The magnitude ' +
            'should be correct but individual calls may be mispriced by one tier.',
        FALLBACK:
            'Fallback rate applied. No model match was found in the rate card at all, so the entry ' +
            'flagged Is_Default_Fallback__c was used. Treat this as an order-of-magnitude estimate ' +
            'and add the missing model to the rate card to upgrade to High confidence.',
        NOT_COSTED:
            'Not costed. This traffic is Agentforce-originated (carries a botVersionId) but the STDM ' +
            'data streams are not ingested in this org, so we cannot tell Agent Actions from LLM planner ' +
            'calls. Rather than show a known-wrong number, the cost is blank. Enable the STDM ingestion ' +
            'to see accurate Agentforce costs.'
    },

    // ─── Explorer (dynamic) ──────────────────────────────────────────────
    explorer: {
        clickToDrill:
            'Click to see recent requests for this group.',
        groupLabel:
            'The dimension value for this row — changes with the Group By selector (User, Prompt, Feature, Model, Day, or Week).',
        metricValue:
            'The value of the currently-selected metric for this group. ' +
            'Computed server-side by AiInsightsService.runExplorerQuery using the same aggregation rules as the fixed dashboards.',
        supportingCount:
            'Row count backing the metric value — useful to gauge confidence. ' +
            'For example, a 100% acceptance rate on 2 feedback events is less reliable than 80% on 200 events.'
    }
};

/**
 * Convenience helper: returns a tooltip string for a given dashboard/field,
 * falling back to a generic message when the key is missing so UI renders
 * gracefully rather than crashing if a tooltip is forgotten.
 */
export function lookupTooltip(dashboard, field) {
    const dash = TOOLTIPS[dashboard];
    if (!dash) {
        return 'Metric definition not available.';
    }
    return dash[field] || 'Metric definition not available.';
}
