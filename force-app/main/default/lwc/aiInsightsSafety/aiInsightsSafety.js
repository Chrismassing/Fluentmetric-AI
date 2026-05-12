import { LightningElement, wire } from 'lwc';
import { publish, subscribe, unsubscribe, MessageContext } from 'lightning/messageService';
import AI_INSIGHTS_DATE_RANGE from '@salesforce/messageChannel/AiInsightsDateRange__c';
import getSafetyOverview from '@salesforce/apex/AiInsightsController.getSafetyOverview';
import getOverviewTrends from '@salesforce/apex/AiInsightsController.getOverviewTrends';
import { abbreviateNumber, formatPercent } from './numberFormat';
import { TOOLTIPS } from 'c/aiInsightsTooltips';
import FM_Empty_Safety_Title from '@salesforce/label/c.FM_Empty_Safety_Title';
import FM_Empty_Safety_Message from '@salesforce/label/c.FM_Empty_Safety_Message';
import FM_Action_Expand_90_Days from '@salesforce/label/c.FM_Action_Expand_90_Days';

const TT = TOOLTIPS.safety;
const OUTPUT_TT = TOOLTIPS.promptOutputViewer;
const MODAL_TT = TOOLTIPS.textModal;
const COLLAPSED_CHARS = 200;

/**
 * Content Safety dashboard.
 *
 * Three stacked sections in a single SLDS card:
 *   1. Summary KPI — flagged rate with color band (red/yellow/green).
 *   2. Category breakdown — 8-row progress-bar grid. v1 limitation: the
 *      avgCategoryScores map is empty because the DMO stores category scores
 *      as a JSON-encoded string. When empty, render a helpful explainer
 *      instead of crashing or showing zeros.
 *   3. Recent flagged outputs — list view, same styling as the Output Viewer
 *      accordion cards.
 */
export default class AiInsightsSafety extends LightningElement {
    @wire(MessageContext)
    messageContext;

    subscription;
    // Seed a default 30-day window so the component can render even before the
    // LMS date channel has fired. If the date filter publishes a different
    // range, handleDateRange will overwrite these and re-run the query.
    startDate = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString();
    endDate = new Date().toISOString();

    summary;
    categoryRows = [];
    flaggedOutputs = [];
    activeSections = [];

    isLoading = false;
    hasLoadedOnce = false;
    errorMessage;

    tooltips = TT;
    outputTooltips = OUTPUT_TT;
    modalTooltips = MODAL_TT;

    labels = {
        emptyTitle: FM_Empty_Safety_Title,
        emptyMessage: FM_Empty_Safety_Message,
        expandRange: FM_Action_Expand_90_Days
    };

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

    // --- LMS + lifecycle ---------------------------------------------------

    connectedCallback() {
        this.subscription = subscribe(
            this.messageContext,
            AI_INSIGHTS_DATE_RANGE,
            (message) => this.handleDateRange(message)
        );
        // Fire an initial load using the seeded defaults so tab-switchers
        // always see something. handleDateRange re-runs when LMS publishes.
        this.loadSafety();
    }

    disconnectedCallback() {
        if (this.subscription) {
            unsubscribe(this.subscription);
            this.subscription = undefined;
        }
    }

    handleDateRange(message) {
        if (!message || !message.startDate || !message.endDate) return;
        this.startDate = message.startDate;
        this.endDate = message.endDate;
        this.loadSafety();
    }

    async loadSafety() {
        this.isLoading = true;
        this.errorMessage = undefined;
        try {
            // Kick off safety overview + trends together. Trends is a side
            // channel for the per-day flag strip (a lightweight heatmap) —
            // if it fails we still render the main review surfaces.
            const [data, trendsResult] = await Promise.all([
                getSafetyOverview({
                    startDate: this.startDate,
                    endDate: this.endDate
                }),
                getOverviewTrends({ startDate: this.startDate, endDate: this.endDate }).catch(() => null)
            ]);
            this.summary = data || {};
            this.categoryRows = this.buildCategoryRows(
                (data && data.avgCategoryScores) || {},
                (data && data.flaggedByCategory) || {}
            );
            this.flaggedOutputs = ((data && data.recentFlaggedOutputs) || [])
                .slice(0, 10)
                .map((row, idx) => this.toOutputCard(row, idx));
            this.buildDailyFlagColumns(trendsResult);
            this.hasLoadedOnce = true;
        } catch (err) {
            this.errorMessage = this.extractError(err);
            this.summary = undefined;
            this.categoryRows = [];
            this.flaggedOutputs = [];
            this.dailyFlagColumns = [];
        } finally {
            this.isLoading = false;
        }
    }

    // Per-day flagged-output columns. Uses the trends DTO's `dailyToxicFlags`
    // series and color-maps each column by relative count so day-level spikes
    // are visible at a glance. Decorative — click-through would require a new
    // day-scoped filter on the accordion below, which is a bigger task.
    dailyFlagColumns = [];
    get hasDailyFlagColumns() {
        return this.dailyFlagColumns && this.dailyFlagColumns.length > 0;
    }

    buildDailyFlagColumns(trends) {
        if (!trends || !Array.isArray(trends.dailyToxicFlags) || trends.dailyToxicFlags.length === 0) {
            this.dailyFlagColumns = [];
            return;
        }
        const values = trends.dailyToxicFlags.map((v) => Number(v) || 0);
        const peak = Math.max(...values) || 1;
        this.dailyFlagColumns = values.map((v, i) => {
            // Intensity bucket — drives the CSS class so heavier days read
            // visually heavier without relying on color alone (tooltip shows
            // exact count, accessible to screen readers).
            const ratio = v / peak;
            let intensity = 'zero';
            if (v > 0 && ratio <= 0.33) intensity = 'low';
            else if (v > 0 && ratio <= 0.66) intensity = 'mid';
            else if (v > 0) intensity = 'high';
            return {
                key: `sfd-${i}`,
                className: `fm-flag-strip__col fm-flag-strip__col_${intensity}`,
                title: `${v} flagged output${v === 1 ? '' : 's'}`
            };
        });
    }

    // --- Summary KPI -------------------------------------------------------

    get toxicRatePct() {
        if (!this.summary) return 0;
        const rate = Number(this.summary.toxicRate || 0);
        return Math.abs(rate) <= 1 ? rate * 100 : rate;
    }

    get toxicRateDisplay() {
        if (!this.summary) return '—';
        return formatPercent(this.summary.toxicRate);
    }

    get toxicRateTheme() {
        const pct = this.toxicRatePct;
        if (pct > 1) return 'error';
        if (pct > 0.1) return 'warning';
        return 'success';
    }

    get toxicRateCardClass() {
        return `fm-card fm-card_${this.toxicRateTheme}`;
    }

    get toxicRateToneLabel() {
        const theme = this.toxicRateTheme;
        if (theme === 'error') return 'At risk';
        if (theme === 'warning') return 'Watch';
        return 'Healthy';
    }

    get toxicRateIcon() {
        const theme = this.toxicRateTheme;
        if (theme === 'error') return 'utility:error';
        if (theme === 'warning') return 'utility:warning';
        return 'utility:success';
    }

    get flaggedCountDisplay() {
        if (!this.summary) return '0 / 0';
        const toxic = Number(this.summary.toxicCount || 0);
        const total = Number(this.summary.totalGenerations || 0);
        return `${toxic.toLocaleString()} / ${total.toLocaleString()}`;
    }

    get totalGenerationsDisplay() {
        return abbreviateNumber((this.summary && this.summary.totalGenerations) || 0);
    }

    // --- Category rows -----------------------------------------------------

    buildCategoryRows(scoresMap, flaggedMap) {
        const names = new Set([
            ...Object.keys(scoresMap || {}),
            ...Object.keys(flaggedMap || {})
        ]);
        if (names.size === 0) return [];
        return Array.from(names)
            .sort((a, b) => a.localeCompare(b))
            .map((name) => {
                const score = Number((scoresMap && scoresMap[name]) || 0);
                const flagged = Number((flaggedMap && flaggedMap[name]) || 0);
                const pct = Math.round(Math.min(1, Math.max(0, score)) * 100);
                return {
                    name,
                    score,
                    scorePct: pct,
                    scoreDisplay: score.toFixed(2),
                    flaggedCount: flagged,
                    variant: this.categoryVariant(score),
                    rowClass: `fm-category-row fm-category-row_${this.categoryVariant(score)}`
                };
            });
    }

    categoryVariant(score) {
        const s = Number(score || 0);
        if (s >= 0.7) return 'error';
        if (s >= 0.3) return 'warning';
        return 'success';
    }

    get hasCategoryData() {
        return this.categoryRows.length > 0;
    }

    get hasNoCategoryData() {
        return !this.loading && !this.error && this.categoryRows.length === 0 && this.data !== null;
    }

    get hasNoFlaggedOutputs() {
        return !this.loading && !this.error && this.flaggedOutputs.length === 0 && this.data !== null;
    }

    // --- Recent flagged outputs -------------------------------------------

    toOutputCard(row, idx) {
        const tokens = (row.inputTokens || 0) + (row.outputTokens || 0);
        const userName = row.userName || 'Unknown user';
        const dateLabel = this.shortTimestamp(row.requestDate);
        const sectionLabel = dateLabel ? `${userName} — ${dateLabel}` : userName;
        return {
            ...row,
            sectionName: `safety-output-${idx}-${row.requestId || idx}`,
            sectionLabel,
            inputPromptCollapsed: this.truncate(row.inputPrompt, COLLAPSED_CHARS),
            generatedTextCollapsed: this.truncate(row.generatedText, COLLAPSED_CHARS),
            totalTokensDisplay: abbreviateNumber(tokens),
            modelDisplay: row.model || '—',
            // When the userId is blank (rare but possible) we can't drill in
            // — render the user name as plain text. LWC templates forbid
            // !inverse conditions, so we expose a dedicated flag.
            userIdMissing: !row.userId
        };
    }

    shortTimestamp(value) {
        if (!value) return '';
        const d = new Date(value);
        if (Number.isNaN(d.getTime())) return '';
        return d.toLocaleString(undefined, {
            month: 'short',
            day: 'numeric',
            hour: '2-digit',
            minute: '2-digit'
        });
    }

    /**
     * Opens the shared entity-details modal for the clicked user. The button
     * carries the userId + userName on data- attributes so we don't have to
     * re-resolve the row from flaggedOutputs.
     */
    handleDrillToUser(event) {
        const userId = event.currentTarget.dataset.userId;
        const userName = event.currentTarget.dataset.userName;
        if (!userId) return;
        const panel = this.template.querySelector('c-ai-insights-drill-panel');
        if (panel && typeof panel.open === 'function') {
            panel.open('User', userId, userName, this.startDate, this.endDate);
        }
    }

    truncate(text, maxChars) {
        if (!text) return '';
        if (text.length <= maxChars) return text;
        return `${text.slice(0, maxChars)}…`;
    }

    handleAccordionToggle(event) {
        this.activeSections = event.detail.openSections || [];
    }

    // --- Expand-in-modal handlers -----------------------------------------

    /**
     * Open the full input prompt for a flagged output in the reusable text
     * modal. The expand button carries `data-request-id` so we can look up
     * the row from the current `flaggedOutputs` array without passing the
     * whole row through the DOM.
     */
    handleExpandInput(event) {
        const requestId = event.currentTarget.dataset.requestId;
        const row = this.flaggedOutputs.find((r) => r.requestId === requestId);
        if (!row) return;
        // Prefer the full (untruncated) payload when Apex supplied it;
        // fall back to the 280-char preview for older DTO shapes.
        this.openTextModal('Input Prompt', row.inputPromptFull || row.inputPrompt, row);
    }

    handleExpandOutput(event) {
        const requestId = event.currentTarget.dataset.requestId;
        const row = this.flaggedOutputs.find((r) => r.requestId === requestId);
        if (!row) return;
        this.openTextModal('Generated Output', row.generatedTextFull || row.generatedText, row);
    }

    openTextModal(title, content, row) {
        const tokens = (row.inputTokens || 0) + (row.outputTokens || 0);
        const metadata = {
            user: row.userName,
            model: row.modelDisplay || row.model,
            date: row.requestDate,
            tokens
        };
        const modal = this.template.querySelector('c-ai-insights-text-modal');
        if (modal) {
            modal.open(title, content || '', metadata);
        }
    }

    // --- State getters -----------------------------------------------------

    get showError() {
        return !!this.errorMessage;
    }

    get showEmptyState() {
        return (
            this.hasLoadedOnce &&
            !this.isLoading &&
            !this.errorMessage &&
            !this.summary
        );
    }

    get showContent() {
        return this.hasLoadedOnce && !this.showError && !this.showEmptyState;
    }

    get hasFlaggedOutputs() {
        return this.flaggedOutputs.length > 0;
    }

    extractError(err) {
        if (!err) return 'Unknown error';
        if (typeof err === 'string') return err;
        if (err.body && err.body.message) return err.body.message;
        if (Array.isArray(err.body) && err.body.length) {
            return err.body.map((e) => e.message).join(', ');
        }
        return err.message || 'Unknown error';
    }
}
