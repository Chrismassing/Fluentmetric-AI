import { LightningElement, wire } from 'lwc';
import { publish, subscribe, unsubscribe, MessageContext } from 'lightning/messageService';
import AI_INSIGHTS_DATE_RANGE from '@salesforce/messageChannel/AiInsightsDateRange__c';
import getOverview from '@salesforce/apex/AiInsightsController.getOverview';
import getOverviewTrends from '@salesforce/apex/AiInsightsController.getOverviewTrends';
import getUsageByUser from '@salesforce/apex/AiInsightsController.getUsageByUser';
import getPowerUserSegments from '@salesforce/apex/AiInsightsController.getPowerUserSegments';
import { abbreviateNumber, formatPercent } from './numberFormat';
import { TOOLTIPS } from 'c/aiInsightsTooltips';
import FM_Section_Highlights from '@salesforce/label/c.FM_Section_Highlights';
import FM_Section_Key_Metrics from '@salesforce/label/c.FM_Section_Key_Metrics';
import FM_Empty_Overview_Title from '@salesforce/label/c.FM_Empty_Overview_Title';
import FM_Empty_Overview_Message from '@salesforce/label/c.FM_Empty_Overview_Message';
import FM_Action_Expand_90_Days from '@salesforce/label/c.FM_Action_Expand_90_Days';
import FM_Adoption_Pareto_Chip from '@salesforce/label/c.FM_Adoption_Pareto_Chip';
import FM_Adoption_Pareto_Suffix from '@salesforce/label/c.FM_Adoption_Pareto_Suffix';
import FM_Adoption_Entitled_Label from '@salesforce/label/c.FM_Adoption_Entitled_Label';
import FM_Adoption_Fallback_Label from '@salesforce/label/c.FM_Adoption_Fallback_Label';
import FM_Adoption_Fallback_Tip from '@salesforce/label/c.FM_Adoption_Fallback_Tip';

/**
 * Token-first KPI strip. Imperatively calls AiInsightsController.getOverview
 * whenever the shared date range on the LMS channel changes.
 *
 * Card order: Total Requests, Unique Users, Acceptance Rate, Total Tokens,
 * Feedback Given, Safety Flags, Avg Tokens / Request. Cost figures are no
 * longer rendered here — they live on the dedicated Cost Analysis tab,
 * gated by Enable_Cost_Metrics__c.
 */
export default class AiInsightsOverview extends LightningElement {
    @wire(MessageContext)
    messageContext;

    subscription;
    // Seed a default 30-day window so the component can render even before the
    // LMS date channel has fired. If the date filter publishes a different
    // range, handleDateRange will overwrite these and re-run the query.
    // Prevents "startDate and endDate are required" errors when a tab-switch
    // or tab-mount races the parent's initial publish.
    startDate = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString();
    endDate = new Date().toISOString();
    presetLabel;

    overview;
    isLoading = false;
    hasLoadedOnce = false;
    errorMessage;

    // Top-contributors mini-leaderboard. Loaded from getUsageByUser and
    // displayed below the KPI strip with a Requests/Tokens sort toggle.
    topUsers = [];
    topUsersSort = 'tokens'; // 'tokens' | 'requests'
    topUsersLimit = 5;

    // Trend payload from getOverviewTrends. Loaded in parallel with the main
    // overview but stored separately so sparkline/delta failures never hide
    // the KPI numbers. Null until the first trend load succeeds.
    trends;

    // Pareto power-user segmentation. Loaded best-effort alongside the
    // overview; null until the first load completes. The Pareto chip in
    // the Adoption strip surfaces top10PercentVolumeShare.
    paretoSegments;

    // Exposed to the template so every KPI label renders its own help text.
    tooltips = TOOLTIPS.overview;

    labels = {
        sectionHighlights: FM_Section_Highlights,
        sectionKeyMetrics: FM_Section_Key_Metrics,
        emptyTitle: FM_Empty_Overview_Title,
        emptyMessage: FM_Empty_Overview_Message,
        expandRange: FM_Action_Expand_90_Days,
        paretoPrefix: FM_Adoption_Pareto_Chip,
        paretoSuffix: FM_Adoption_Pareto_Suffix,
        entitledLabel: FM_Adoption_Entitled_Label,
        fallbackLabel: FM_Adoption_Fallback_Label,
        fallbackTip: FM_Adoption_Fallback_Tip
    };

    connectedCallback() {
        this.subscription = subscribe(
            this.messageContext,
            AI_INSIGHTS_DATE_RANGE,
            (message) => this.handleDateRange(message)
        );
        // Fire an initial load using the seeded defaults. If LMS then
        // publishes a different range, handleDateRange will re-run the query.
        this.loadOverview();
    }

    disconnectedCallback() {
        if (this.subscription) {
            unsubscribe(this.subscription);
            this.subscription = undefined;
        }
    }

    handleDateRange(message) {
        if (!message || !message.startDate || !message.endDate) {
            return;
        }
        this.startDate = message.startDate;
        this.endDate = message.endDate;
        this.presetLabel = message.presetLabel;
        this.loadOverview();
    }

    // Empty-state quick action: re-publish a 90-day range so every subscriber
    // (this card + every other tab) widens in lockstep — same pattern the date
    // filter uses when a preset is picked.
    handleExpandRange() {
        const endDate = new Date();
        const startDate = new Date();
        startDate.setDate(startDate.getDate() - 90);
        publish(this.messageContext, AI_INSIGHTS_DATE_RANGE, {
            startDate: startDate.toISOString(),
            endDate: endDate.toISOString(),
            presetLabel: 'Last 90 days'
        });
    }

    async loadOverview() {
        this.isLoading = true;
        this.errorMessage = undefined;
        try {
            // Fire all three queries in parallel. The main overview drives the
            // visible KPI numbers; trends is a best-effort side channel for
            // sparklines and delta badges; users powers the Top contributors
            // leaderboard. Side-channel failures (trends, users) never hide
            // the headline KPIs.
            const [result, trendsResult, usersResult, paretoResult] = await Promise.all([
                getOverview({ startDate: this.startDate, endDate: this.endDate }),
                getOverviewTrends({ startDate: this.startDate, endDate: this.endDate }).catch(() => null),
                getUsageByUser({ startDate: this.startDate, endDate: this.endDate }).catch(() => []),
                getPowerUserSegments({ startDate: this.startDate, endDate: this.endDate }).catch(() => null)
            ]);
            this.overview = result;
            this.trends = trendsResult;
            this.topUsers = Array.isArray(usersResult) ? usersResult : [];
            this.paretoSegments = paretoResult;
            this.hasLoadedOnce = true;
        } catch (err) {
            this.errorMessage = this.extractError(err);
            this.overview = undefined;
            this.trends = undefined;
            this.topUsers = [];
            this.paretoSegments = undefined;
        } finally {
            this.isLoading = false;
        }
    }

    // ───────── Top contributors leaderboard ─────────

    handleTopUsersSortToggle(event) {
        const value = event?.target?.dataset?.sort;
        if (value === 'tokens' || value === 'requests') {
            this.topUsersSort = value;
        }
    }

    get topUsersByRequestsActive() {
        return this.topUsersSort === 'requests';
    }
    get topUsersByTokensActive() {
        return this.topUsersSort === 'tokens';
    }
    get topUsersTokensClass() {
        return this.topUsersByTokensActive
            ? 'slds-button slds-button_brand'
            : 'slds-button slds-button_neutral';
    }
    get topUsersRequestsClass() {
        return this.topUsersByRequestsActive
            ? 'slds-button slds-button_brand'
            : 'slds-button slds-button_neutral';
    }

    get topUsersRows() {
        if (!Array.isArray(this.topUsers) || this.topUsers.length === 0) return [];
        const sortKey = this.topUsersSort === 'requests' ? 'requestCount' : 'totalTokens';
        // DAO-supplied rows are already filtered to the date window. Sort on
        // the active key, descending, and slice the top N for the leaderboard.
        const sorted = [...this.topUsers].sort(
            (a, b) => (Number(b?.[sortKey]) || 0) - (Number(a?.[sortKey]) || 0)
        );
        const max = Number(sorted[0]?.[sortKey]) || 0;
        return sorted.slice(0, this.topUsersLimit).map((row) => {
            const value = Number(row?.[sortKey]) || 0;
            const tokens = Number(row?.totalTokens) || 0;
            const requests = Number(row?.requestCount) || 0;
            const widthPct = max > 0 ? Math.max(2, Math.round((value / max) * 100)) : 0;
            return {
                userId: row?.userId || row?.userKey || row?.userName,
                userName: row?.userName || row?.userId || 'Unknown',
                requestCount: requests,
                totalTokens: tokens,
                primaryDisplay:
                    this.topUsersSort === 'requests' ? requests.toLocaleString() : abbreviateNumber(tokens),
                secondaryDisplay:
                    this.topUsersSort === 'requests' ? `${abbreviateNumber(tokens)} tokens` : `${requests.toLocaleString()} req`,
                barStyle: `width: ${widthPct}%`
            };
        });
    }

    get hasTopUsersRows() {
        return this.topUsersRows.length > 0;
    }

    // ───────── Sparklines + delta badges (from `trends`) ─────────

    // Min-max normalize a numeric series into an SVG polyline `points`
    // attribute. 0..80 x, 20..0 y (inverted so higher = up). Returns empty
    // string when the series is missing or flat so the template can hide
    // the sparkline cleanly.
    _polyline(series) {
        if (!Array.isArray(series) || series.length < 2) return '';
        const numeric = series.map((v) => Number(v) || 0);
        const max = Math.max(...numeric);
        const min = Math.min(...numeric);
        const span = max - min || 1;
        const stepX = 80 / (numeric.length - 1);
        return numeric
            .map((v, i) => {
                const x = (i * stepX).toFixed(2);
                const y = (20 - ((v - min) / span) * 20).toFixed(2);
                return `${x},${y}`;
            })
            .join(' ');
    }

    // Compute a ±% delta against prior-window value. Returns a plain object
    // the template can render (label, icon, class, a11y text). When there is
    // no prior data (first-time install, 0 prior) we return null so the
    // template skips the badge instead of rendering "+Infinity%".
    _delta(currentVal, previousVal) {
        if (this.trends === null || this.trends === undefined) return null;
        const prev = Number(previousVal) || 0;
        const cur = Number(currentVal) || 0;
        if (prev === 0) return null;
        const pct = ((cur - prev) / prev) * 100;
        const rounded = Math.round(pct);
        const up = rounded >= 0;
        const windowDays = this.trends && this.trends.daysInWindow ? this.trends.daysInWindow : 0;
        const windowText = windowDays > 0 ? `vs prior ${windowDays} day${windowDays === 1 ? '' : 's'}` : 'vs prior period';
        const sign = up ? '+' : '−';
        const display = `${sign}${Math.abs(rounded)}%`;
        return {
            display,
            windowText,
            ariaLabel: `${display} ${windowText}`,
            icon: up ? 'utility:arrowup' : 'utility:arrowdown',
            // Deltas use the same success/warning pattern as KPI cards, but
            // "direction of good" differs by metric — callers pass their own
            // polarity via `invert`.
            class: up ? 'fm-delta fm-delta_up' : 'fm-delta fm-delta_down'
        };
    }

    // Sparklines — exposed to the template as pre-rendered point strings.
    get sparkRequests() { return this._polyline(this.trends && this.trends.dailyRequests); }
    get sparkTokens() { return this._polyline(this.trends && this.trends.dailyTokens); }
    get sparkToxic() { return this._polyline(this.trends && this.trends.dailyToxicFlags); }
    get hasSparkRequests() { return !!this.sparkRequests; }
    get hasSparkTokens() { return !!this.sparkTokens; }
    get hasSparkToxic() { return !!this.sparkToxic; }

    // Deltas — one getter per KPI that has a prior-window counterpart.
    get deltaRequests() {
        return this.trends && this._delta(this.totalRequestsValue, this.trends.previousTotalRequests);
    }
    get deltaUniqueUsers() {
        return this.trends && this._delta(this.uniqueUsersValue, this.trends.previousUniqueUsers);
    }
    get deltaTokens() {
        if (!this.trends || !this.overview) return null;
        const curTot = (this.overview.totalInputTokens || 0) + (this.overview.totalOutputTokens || 0);
        return this._delta(curTot, this.trends.previousTotalTokens);
    }
    get deltaFeedback() {
        return this.trends && this._delta(this.feedbackCountValue, this.trends.previousFeedbackCount);
    }
    get deltaToxic() {
        return this.trends && this._delta(this.safetyFlagCountValue, this.trends.previousToxicFlagCount);
    }

    extractError(err) {
        if (!err) {
            return 'Unknown error';
        }
        if (typeof err === 'string') {
            return err;
        }
        if (err.body && err.body.message) {
            return err.body.message;
        }
        if (Array.isArray(err.body) && err.body.length) {
            return err.body.map((e) => e.message).join(', ');
        }
        return err.message || 'Unknown error';
    }

    get hasData() {
        return !!this.overview && (this.overview.totalRequests || 0) > 0;
    }

    get showEmptyState() {
        return this.hasLoadedOnce && !this.isLoading && !this.errorMessage && !this.hasData;
    }

    get showError() {
        return !!this.errorMessage;
    }

    get showCards() {
        return !this.showEmptyState && !this.showError;
    }

    // --- Card data getters --------------------------------------------------

    get totalRequestsValue() {
        return this.overview?.totalRequests ?? 0;
    }

    get uniqueUsersValue() {
        return this.overview?.uniqueUsers ?? 0;
    }

    get acceptanceRateDisplay() {
        if (!this.overview) return '—';
        return formatPercent(this.overview.acceptanceRate);
    }

    get acceptanceRateTheme() {
        const rate = this.ratePercent(this.overview?.acceptanceRate);
        if (rate === null) return 'neutral';
        if (rate > 70) return 'success';
        if (rate >= 50) return 'warning';
        return 'error';
    }

    get acceptanceRateToneLabel() {
        const theme = this.acceptanceRateTheme;
        if (theme === 'success') return 'Healthy';
        if (theme === 'warning') return 'Needs attention';
        if (theme === 'error') return 'At risk';
        return '';
    }

    get acceptanceRateIcon() {
        const theme = this.acceptanceRateTheme;
        if (theme === 'success') return 'utility:success';
        if (theme === 'warning') return 'utility:warning';
        if (theme === 'error') return 'utility:error';
        return 'utility:info';
    }

    get acceptanceRateClass() {
        return `fm-card fm-card_${this.acceptanceRateTheme}`;
    }

    get totalTokensDisplay() {
        if (!this.overview) return '—';
        const total = (this.overview.totalInputTokens || 0) + (this.overview.totalOutputTokens || 0);
        return abbreviateNumber(total);
    }

    // Avg tokens per request — pure token math, no cost inference. Replaces
    // the $ card on the default KPI strip per the hybrid cost model.
    get avgTokensPerRequestDisplay() {
        if (!this.overview) return '—';
        const total = (this.overview.totalInputTokens || 0) + (this.overview.totalOutputTokens || 0);
        const requests = this.overview.totalRequests || 0;
        if (requests === 0) return '—';
        return abbreviateNumber(Math.round(total / requests));
    }

    // --- Highlights --------------------------------------------------------

    get hasTopUser() {
        return !!(this.overview && this.overview.topUserName);
    }
    get hasTopPrompt() {
        return !!(this.overview && this.overview.topPromptLabel);
    }
    get hasTopModel() {
        return !!(this.overview && this.overview.topModelName);
    }
    get hasTopFeature() {
        return !!(this.overview && this.overview.topFeatureName);
    }
    get hasHighlights() {
        return this.hasTopUser || this.hasTopPrompt || this.hasTopModel || this.hasTopFeature;
    }

    get topUserName() {
        return (this.overview && this.overview.topUserName) || '—';
    }
    get topUserRequestCount() {
        return (this.overview && this.overview.topUserRequestCount) || 0;
    }
    get topPromptLabel() {
        return (this.overview && this.overview.topPromptLabel) || '—';
    }
    get topPromptInvocations() {
        return (this.overview && this.overview.topPromptInvocations) || 0;
    }
    get topModelName() {
        return (this.overview && this.overview.topModelName) || '—';
    }
    get topModelTokensDisplay() {
        if (!this.overview || !this.overview.topModelTotalTokens) return '—';
        return abbreviateNumber(this.overview.topModelTotalTokens);
    }
    get topFeatureName() {
        return (this.overview && this.overview.topFeatureName) || '—';
    }
    get topFeatureRequestCount() {
        return (this.overview && this.overview.topFeatureRequestCount) || 0;
    }

    // Combined tooltip — covers both input and output, since the card shows
    // their sum rather than one of the two individually.
    get totalTokensTooltip() {
        return `${this.tooltips.totalInputTokens}\n\n${this.tooltips.totalOutputTokens}`;
    }

    get totalTokensTitle() {
        if (!this.overview) return '';
        const input = this.overview.totalInputTokens || 0;
        const output = this.overview.totalOutputTokens || 0;
        return `Input: ${input.toLocaleString()} · Output: ${output.toLocaleString()}`;
    }

    get feedbackCountValue() {
        return this.overview?.feedbackCount ?? 0;
    }

    get safetyFlagCountValue() {
        return this.overview?.toxicFlagCount ?? 0;
    }

    get safetyFlagTheme() {
        if (!this.overview) return 'neutral';
        return (this.overview.toxicFlagCount || 0) > 0 ? 'error' : 'success';
    }

    get safetyFlagToneLabel() {
        return this.safetyFlagTheme === 'error' ? 'Flagged content' : 'All clear';
    }

    get safetyFlagIcon() {
        return this.safetyFlagTheme === 'error' ? 'utility:warning' : 'utility:success';
    }

    get safetyFlagClass() {
        return `fm-card fm-card_${this.safetyFlagTheme}`;
    }

    // --- Adoption strip (Phase 4.1) ----------------------------------------

    get adoptionRatePct() {
        const v = this.overview && this.overview.adoptionRate;
        if (v === null || v === undefined) return null;
        const n = Number(v);
        if (Number.isNaN(n)) return null;
        // Service emits a 0..1 ratio; render as a 0..100 percent.
        return Math.abs(n) <= 1 ? n * 100 : n;
    }

    get adoptionRateDisplay() {
        const pct = this.adoptionRatePct;
        if (pct === null) return '—';
        return `${pct.toFixed(1)}%`;
    }

    get hasAdoptionData() {
        return !!(this.overview && (this.overview.entitledUserCount > 0 || this.overview.totalActiveOrgUsers > 0));
    }

    get adoptionDenominatorLabel() {
        if (!this.overview) return '';
        return this.overview.entitledFallback ? this.labels.fallbackLabel : this.labels.entitledLabel;
    }

    get adoptionDenominatorCount() {
        if (!this.overview) return 0;
        return this.overview.entitledFallback
            ? (this.overview.totalActiveOrgUsers || 0)
            : (this.overview.entitledUserCount || 0);
    }

    get adoptionFallbackTip() {
        return this.overview && this.overview.entitledFallback ? this.labels.fallbackTip : '';
    }

    get showAdoptionFallbackTip() {
        return !!(this.overview && this.overview.entitledFallback);
    }

    // --- Pareto chip (Phase 4.1) -------------------------------------------

    get paretoSharePct() {
        const v = this.paretoSegments && this.paretoSegments.top10PercentVolumeShare;
        if (v === null || v === undefined) return null;
        const n = Number(v);
        if (Number.isNaN(n)) return null;
        return Math.abs(n) <= 1 ? n * 100 : n;
    }

    get paretoChipDisplay() {
        const pct = this.paretoSharePct;
        if (pct === null) return '';
        return `${this.labels.paretoPrefix} ${pct.toFixed(1)}% ${this.labels.paretoSuffix}`;
    }

    get hasParetoChip() {
        const pct = this.paretoSharePct;
        const users = this.paretoSegments && this.paretoSegments.top10PercentUserCount;
        return pct !== null && (users || 0) > 0;
    }

    get dateRangeLabel() {
        if (this.overview?.dateRangeLabel) {
            return this.overview.dateRangeLabel;
        }
        return this.presetLabel || '';
    }

    ratePercent(value) {
        if (value === null || value === undefined || Number.isNaN(Number(value))) {
            return null;
        }
        const n = Number(value);
        return Math.abs(n) <= 1 ? n * 100 : n;
    }
}
