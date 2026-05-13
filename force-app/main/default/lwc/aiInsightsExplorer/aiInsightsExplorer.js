import { LightningElement, wire } from 'lwc';
import { publish, subscribe, unsubscribe, MessageContext } from 'lightning/messageService';
import AI_INSIGHTS_FILTERS from '@salesforce/messageChannel/AiInsightsFilters__c';
import AI_INSIGHTS_DATE_RANGE from '@salesforce/messageChannel/AiInsightsDateRange__c';
import runExplorerQuery from '@salesforce/apex/AiInsightsController.runExplorerQuery';
import getCostSettings from '@salesforce/apex/AiInsightsController.getCostSettings';
import { abbreviateNumber, formatPercent } from './numberFormat';
import { TOOLTIPS } from 'c/aiInsightsTooltips';
import FM_Explorer_Starter_Heading from '@salesforce/label/c.FM_Explorer_Starter_Heading';
import FM_Explorer_Starter_Top_Prompts from '@salesforce/label/c.FM_Explorer_Starter_Top_Prompts';
import FM_Explorer_Starter_Flagged_Last_Week from '@salesforce/label/c.FM_Explorer_Starter_Flagged_Last_Week';
import FM_Explorer_Starter_Heavy_Users from '@salesforce/label/c.FM_Explorer_Starter_Heavy_Users';

const TT = TOOLTIPS.explorer;

const GROUP_BY_OPTIONS = [
    { label: 'User', value: 'User' },
    { label: 'Prompt Template', value: 'PromptTemplate' },
    { label: 'Feature', value: 'Feature' },
    { label: 'Model', value: 'Model' },
    { label: 'Day', value: 'Day' },
    { label: 'Week', value: 'Week' }
];

// Default metrics — TotalCost is intentionally NOT here. Cost lives on the
// dedicated Cost Analysis tab, gated by Enable_Cost_Metrics__c, so the
// default Explorer experience shows tokens and counts rather than estimates.
const METRIC_OPTIONS = [
    { label: 'Request Count', value: 'RequestCount' },
    { label: 'Unique Users', value: 'UniqueUsers' },
    { label: 'Total Tokens', value: 'TotalTokens' },
    { label: 'Acceptance Rate', value: 'AcceptanceRate' },
    { label: 'Toxic Flag Count', value: 'ToxicFlagCount' }
];

// Feedback is still an Explorer-local pill because it requires a join
// against GenAIFeedback__dlm, which the filter rail doesn't surface today.
// All other dimension filters (user, prompt, model, provider, feature,
// appType) come in through the rail via AiInsightsFilters LMS.
const FILTER_TYPE_OPTIONS = [{ label: 'Feedback value', value: 'feedbackValue' }];

const FILTER_VALUE_OPTIONS = {
    feedbackValue: [
        { label: 'Thumbs up', value: 'thumbs_up' },
        { label: 'Thumbs down', value: 'thumbs_down' },
        { label: 'Accepted', value: 'accepted' },
        { label: 'Rejected', value: 'rejected' },
        { label: 'Edited', value: 'edited' }
    ]
};

const DEFAULT_RESULT_LIMIT = 25;

/**
 * Dynamic pivot explorer — "centerpiece" component.
 *
 * Users pick a Group By and Metric, optionally add filter pills, and the
 * component calls `runExplorerQuery` imperatively (non-cacheable). Results
 * render as both a CSS-only horizontal SLDS bar chart and a sortable table,
 * plus a one-click CSV export.
 *
 * Pending-filter state: adding a filter is a two-step interaction (type, then
 * value). The pending value picker appears as a secondary combobox; confirming
 * it adds the pill and re-runs the query.
 */
export default class AiInsightsExplorer extends LightningElement {
    @wire(MessageContext)
    messageContext;

    subscription;
    filtersSubscription;
    // Seed a default 30-day window so group-by / metric / filter interactions
    // work even before the LMS date channel has fired. The filter rail and
    // aiInsightsApp both publish on load; if either publish races the
    // Explorer's subscribe we still have a usable fallback rather than
    // sending null dates to Apex.
    startDate = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString();
    endDate = new Date().toISOString();

    // Full criteria payload from the filter rail. Empty default — populated
    // on the first AiInsightsFilters publish. Kept as an object (not JSON)
    // so individual dimensions are readable for rendering logic.
    criteria = {};

    groupBy = 'User';
    metric = 'RequestCount';
    groupByOptions = GROUP_BY_OPTIONS;
    metricOptions = METRIC_OPTIONS;
    filterTypeOptions = FILTER_TYPE_OPTIONS;

    // Feedback-value pill (still local — requires feedback join).
    filters = [];

    // Pending filter state (two-step add: type -> value).
    pendingFilterKey;
    pendingFilterValue = '';

    results = [];
    chartRows = [];

    sortedBy = 'metricValue';
    sortedDirection = 'desc';

    isLoading = false;
    hasLoadedOnce = false;
    errorMessage;
    chartCollapsed = false;

    // Starter-chip state: shown only until the user interacts. Once they run
    // any query explicitly (change group/metric, click a chip, etc.), we hide
    // the starter row so it doesn't compete for attention on subsequent visits.
    hasInteracted = false;

    columns = [];

    labels = {
        starterHeading: FM_Explorer_Starter_Heading,
        starterTopPrompts: FM_Explorer_Starter_Top_Prompts,
        starterFlagged: FM_Explorer_Starter_Flagged_Last_Week,
        starterHeavyUsers: FM_Explorer_Starter_Heavy_Users
    };

    get showStarters() {
        return !this.hasInteracted && !this.isLoading;
    }

    // Apply a starter preset. Each preset sets group+metric; the "flagged"
    // preset also re-publishes a 7-day window so every dashboard stays in
    // sync with the user's stated intent. Uses the same LMS channel the date
    // filter uses so nothing special is required from subscribers.
    handleStarterClick(event) {
        const preset = event.currentTarget.dataset.preset;
        this.hasInteracted = true;
        switch (preset) {
            case 'top_prompts':
                this.groupBy = 'PromptTemplate';
                this.metric = 'TotalTokens';
                break;
            case 'flagged':
                this.groupBy = 'User';
                this.metric = 'ToxicFlagCount';
                this.publishRange(7, 'Last 7 days');
                break;
            case 'heavy_users':
                this.groupBy = 'User';
                this.metric = 'RequestCount';
                break;
            default:
                return;
        }
        this.rebuildColumns();
        this.runQuery();
    }

    publishRange(days, presetLabel) {
        const endDate = new Date();
        const startDate = new Date();
        startDate.setDate(startDate.getDate() - days);
        this.startDate = startDate.toISOString();
        this.endDate = endDate.toISOString();
        publish(this.messageContext, AI_INSIGHTS_DATE_RANGE, {
            startDate: this.startDate,
            endDate: this.endDate,
            presetLabel
        });
    }

    connectedCallback() {
        this.rebuildColumns();
        // Fire an initial load with the seeded defaults. If LMS publishes a
        // different range or criteria after subscribe, the handlers re-run.
        this.runQuery();
        // Primary channel — full filter criteria from the rail.
        this.filtersSubscription = subscribe(
            this.messageContext,
            AI_INSIGHTS_FILTERS,
            (message) => this.handleFilters(message)
        );
        // Legacy date-only channel kept active so the older date filter
        // component and any not-yet-migrated subscribers still drive the
        // Explorer. Safe to drop once the rail is the sole date surface.
        this.subscription = subscribe(
            this.messageContext,
            AI_INSIGHTS_DATE_RANGE,
            (message) => this.handleDateRange(message)
        );
        // Cost is off by default everywhere now (see hybrid cost model).
        // If TotalCost ever sneaks into stored state (e.g. from a prior
        // session), flip it back to RequestCount.
        this.applyCostGate();
    }

    applyCostGate() {
        // No-op read for consistency with the rest of the app — keeps the
        // getCostSettings endpoint warm in Lightning cache. Cost metrics are
        // never rendered on the Explorer itself regardless of the setting.
        getCostSettings().catch(() => {
            /* no-op */
        });
        if (this.metric === 'TotalCost') {
            this.metric = 'RequestCount';
            this.rebuildColumns();
            this.runQuery();
        }
    }

    disconnectedCallback() {
        if (this.subscription) {
            unsubscribe(this.subscription);
            this.subscription = undefined;
        }
        if (this.filtersSubscription) {
            unsubscribe(this.filtersSubscription);
            this.filtersSubscription = undefined;
        }
    }

    // --- Controls handlers -------------------------------------------------

    handleDateRange(message) {
        if (!message || !message.startDate || !message.endDate) return;
        this.startDate = message.startDate;
        this.endDate = message.endDate;
        this.runQuery();
    }

    handleFilters(message) {
        if (!message) return;
        let parsed = null;
        if (message.criteriaJson) {
            try {
                parsed = JSON.parse(message.criteriaJson);
            } catch (err) {
                parsed = null;
            }
        }
        const next = parsed || {};
        if (next.startDate) this.startDate = next.startDate;
        else if (message.startDate) this.startDate = message.startDate;
        if (next.endDate) this.endDate = next.endDate;
        else if (message.endDate) this.endDate = message.endDate;
        this.criteria = {
            userIds: next.userIds || [],
            promptTemplateDevNames: next.promptTemplateDevNames || [],
            models: next.models || [],
            providers: next.providers || [],
            features: next.features || [],
            appTypes: next.appTypes || []
        };
        // Optional groupBy hint from a "Pin to Explorer" hand-off. Accept
        // only values we actually offer in the dropdown so a stale hint
        // can't put the Explorer into an unrenderable state.
        if (message.groupBy) {
            const allowed = GROUP_BY_OPTIONS.some((o) => o.value === message.groupBy);
            if (allowed) {
                this.groupBy = message.groupBy;
                this.hasInteracted = true;
                this.rebuildColumns();
            }
        }
        this.runQuery();
    }

    handleGroupByChange(event) {
        this.hasInteracted = true;
        this.groupBy = event.detail.value;
        this.runQuery();
    }

    handleMetricChange(event) {
        this.hasInteracted = true;
        this.metric = event.detail.value;
        this.rebuildColumns();
        this.runQuery();
    }

    handleAddFilterMenuSelect(event) {
        // Clicking a menu item surfaces the second-step value picker.
        this.pendingFilterKey = event.detail.value;
        this.pendingFilterValue = '';
    }

    handlePendingValueChange(event) {
        this.pendingFilterValue = event.detail.value;
    }

    handleConfirmPendingFilter() {
        if (!this.pendingFilterKey || !this.pendingFilterValue) {
            return;
        }
        const typeLabel = this.labelForFilterType(this.pendingFilterKey);
        const valueLabel = this.labelForFilterValue(this.pendingFilterKey, this.pendingFilterValue);
        this.filters = [
            ...this.filters.filter((f) => f.key !== this.pendingFilterKey),
            {
                key: this.pendingFilterKey,
                value: this.pendingFilterValue,
                label: `${typeLabel}: ${valueLabel}`
            }
        ];
        this.pendingFilterKey = undefined;
        this.pendingFilterValue = '';
        this.runQuery();
    }

    handleCancelPendingFilter() {
        this.pendingFilterKey = undefined;
        this.pendingFilterValue = '';
    }

    handleRemoveFilter(event) {
        const key = event.target.dataset.key;
        this.filters = this.filters.filter((f) => f.key !== key);
        this.runQuery();
    }

    // --- Data load ---------------------------------------------------------

    async runQuery() {
        if (!this.startDate || !this.endDate) return;
        this.isLoading = true;
        this.errorMessage = undefined;

        const filtersMap = {};
        this.filters.forEach((f) => {
            filtersMap[f.key] = f.value;
        });
        const filtersJson = JSON.stringify(filtersMap);
        const criteriaJson = JSON.stringify(this.criteria || {});

        try {
            // NOT @wire — runExplorerQuery is non-cacheable because its pivot
            // shape changes with every input. All params are primitive and
            // top-level: LWC's marshaller to Apex custom DTOs with nested
            // DateTime / Map fields is fragile, so we keep the wire flat.
            const data = await runExplorerQuery({
                startDate: this.startDate,
                endDate: this.endDate,
                groupBy: this.groupBy,
                metric: this.metric,
                filtersJson,
                criteriaJson,
                resultLimit: DEFAULT_RESULT_LIMIT
            });
            this.results = Array.isArray(data) ? data : [];
            this.buildChart();
            this.applySort();
            this.hasLoadedOnce = true;
        } catch (err) {
            this.errorMessage = this.extractError(err);
            this.results = [];
            this.chartRows = [];
        } finally {
            this.isLoading = false;
        }
    }

    // --- Columns & chart ---------------------------------------------------

    rebuildColumns() {
        // Group column becomes a button so users can drill into entity
        // details. Day/Week pivots are time buckets and set `drillDisabled`
        // per-row so the button renders but clicks are no-ops.
        this.columns = [
            {
                label: 'Group',
                fieldName: 'groupLabel',
                type: 'button',
                sortable: true,
                wrapText: true,
                helpText: TT.clickToDrill || TT.groupLabel,
                typeAttributes: {
                    label: { fieldName: 'groupLabel' },
                    name: 'drillToGroup',
                    variant: 'base',
                    disabled: { fieldName: 'drillDisabled' }
                }
            },
            {
                label: this.metricColumnLabel,
                fieldName: 'metricValueDisplay',
                type: 'text',
                sortable: true,
                sortBy: 'metricValue',
                helpText: this.getMetricTooltip(this.metric),
                cellAttributes: { alignment: 'right' }
            },
            {
                label: 'Supporting Count',
                fieldName: 'supportingCount',
                type: 'number',
                sortable: true,
                helpText: TT.supportingCount,
                cellAttributes: { alignment: 'right' },
                typeAttributes: { maximumFractionDigits: 0 }
            }
        ];
    }

    /**
     * Dynamic tooltip for the metric column — reuses the explorer.metricValue
     * base tooltip and appends a metric-specific hint so the header help
     * tracks whichever metric is selected.
     */
    getMetricTooltip(metric) {
        const base = TT.metricValue;
        const hints = {
            RequestCount: 'Count of AI requests per group.',
            UniqueUsers: 'Distinct users per group — useful for adoption pivots.',
            TotalTokens: 'Sum of input + output tokens per group.',
            TotalCost:
                'Estimated USD cost per group, with org discount applied. ' +
                'Uses exact rate-card match when grouped by Model; falls back to Standard tier for other groupings.',
            AcceptanceRate: 'Share of feedback events that were positive — interpret with care when Supporting Count is low.',
            ToxicFlagCount: 'Count of safety-flagged generations per group.'
        };
        return `${base}\n\n${hints[metric] || ''}`.trim();
    }

    get metricColumnLabel() {
        const opt = METRIC_OPTIONS.find((o) => o.value === this.metric);
        return opt ? opt.label : 'Metric';
    }

    buildChart() {
        const sorted = [...this.results].sort(
            (a, b) => Number(b.metricValue || 0) - Number(a.metricValue || 0)
        );
        const max = sorted.reduce((acc, r) => Math.max(acc, Number(r.metricValue || 0)), 0);
        // Day/Week groupings are time buckets, not drillable entities.
        const drillDisabled = this.groupBy === 'Day' || this.groupBy === 'Week';
        this.chartRows = sorted.map((r) => {
            const value = Number(r.metricValue || 0);
            const width = max > 0 ? (value / max) * 100 : 0;
            return {
                groupKey: r.groupKey,
                groupLabel: r.groupLabel || r.groupKey || '—',
                metricValue: value,
                metricValueDisplay: this.formatMetric(value),
                supportingCount: Number(r.supportingCount || 0),
                barStyle: `width: ${width.toFixed(2)}%;`,
                ariaLabel: `${r.groupLabel || r.groupKey}: ${this.formatMetric(value)}.`,
                drillDisabled,
                // LWC templates forbid !negation inline — expose inverse flag.
                drillEnabled: !drillDisabled
            };
        });
    }

    // --- Drill-in ----------------------------------------------------------

    get groupColumnTooltip() {
        return (TT && TT.clickToDrill) || (TT && TT.groupLabel) || '';
    }

    /**
     * Click handler on the hand-rolled table's Group <a> cell. Maps the
     * current `groupBy` to an entityType and opens the shared details modal.
     * Uses plain <a> + onclick instead of lightning-datatable button cells
     * because the datatable button variant proved unreliable.
     */
    handleGroupClick(event) {
        event.preventDefault();
        const groupKey = event.currentTarget.dataset.groupKey;
        const groupLabel = event.currentTarget.dataset.groupLabel;
        const map = {
            User: 'User',
            PromptTemplate: 'PromptTemplate',
            Model: 'Model',
            Feature: 'Feature'
        };
        const entityType = map[this.groupBy];
        if (!entityType) return;
        const panel = this.template.querySelector('c-ai-insights-drill-panel');
        if (panel && typeof panel.open === 'function') {
            // Forward the rail's active criteria so the drill stays scoped to
            // the same slice the Explorer table is showing.
            const criteriaJson = JSON.stringify(this.criteria || {});
            panel.open(
                entityType,
                groupKey,
                groupLabel,
                this.startDate,
                this.endDate,
                criteriaJson
            );
        }
    }

    formatMetric(value) {
        if (this.metric === 'AcceptanceRate') {
            return formatPercent(value);
        }
        if (this.metric === 'TotalCost') {
            const n = Number(value || 0);
            return `$${n.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
        }
        return abbreviateNumber(value);
    }

    // --- Table sort --------------------------------------------------------

    handleSort(event) {
        const columnDef = this.columns.find((c) => c.fieldName === event.detail.fieldName);
        this.sortedBy = (columnDef && columnDef.sortBy) || event.detail.fieldName;
        this.sortedDirection = event.detail.sortDirection;
        this.applySort();
    }

    applySort() {
        const key = this.sortedBy;
        const direction = this.sortedDirection === 'desc' ? -1 : 1;
        this.chartRows = [...this.chartRows].sort((a, b) => {
            const av = a[key];
            const bv = b[key];
            if (av === bv) return 0;
            if (av === null || av === undefined) return 1;
            if (bv === null || bv === undefined) return -1;
            if (typeof av === 'string') {
                return av.localeCompare(bv) * direction;
            }
            return (av < bv ? -1 : 1) * direction;
        });
    }

    // --- CSV export --------------------------------------------------------

    /**
     * Build CSV client-side from the current result set. We use a Blob +
     * object URL rather than a data URL so large result sets don't blow up
     * browser URL limits. Fields are escaped per RFC 4180: commas, quotes,
     * and newlines trigger double-quoting, and embedded quotes are doubled.
     */
    handleExportCsv() {
        if (!this.chartRows || this.chartRows.length === 0) return;

        const headers = ['Group', this.metricColumnLabel, 'Supporting Count'];
        const rows = this.chartRows.map((r) => [
            r.groupLabel,
            String(r.metricValue),
            String(r.supportingCount)
        ]);
        const csv = [headers, ...rows]
            .map((fields) => fields.map((f) => this.csvEscape(f)).join(','))
            .join('\r\n');

        const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' });
        const url = URL.createObjectURL(blob);
        const filename = this.buildExportFilename();

        const link = document.createElement('a');
        link.href = url;
        link.download = filename;
        link.style.display = 'none';
        document.body.appendChild(link);
        link.click();
        document.body.removeChild(link);

        // Release the object URL on the next tick so the download has started.
        setTimeout(() => URL.revokeObjectURL(url), 0);
    }

    csvEscape(value) {
        const str = value === null || value === undefined ? '' : String(value);
        if (/[",\r\n]/.test(str)) {
            return `"${str.replace(/"/g, '""')}"`;
        }
        return str;
    }

    buildExportFilename() {
        const dateStr = new Date().toISOString().slice(0, 10);
        return `fluentmetric-explorer-${this.groupBy}-${this.metric}-${dateStr}.csv`;
    }

    // --- Pending filter helpers -------------------------------------------

    get hasPendingFilter() {
        return !!this.pendingFilterKey;
    }

    get pendingFilterValueOptions() {
        return FILTER_VALUE_OPTIONS[this.pendingFilterKey] || [];
    }

    get pendingFilterTypeLabel() {
        return this.labelForFilterType(this.pendingFilterKey);
    }

    labelForFilterType(key) {
        const opt = FILTER_TYPE_OPTIONS.find((o) => o.value === key);
        return opt ? opt.label : key;
    }

    labelForFilterValue(key, value) {
        const opts = FILTER_VALUE_OPTIONS[key] || [];
        const found = opts.find((o) => o.value === value);
        return found ? found.label : value;
    }

    // --- State getters -----------------------------------------------------

    get hasFilters() {
        return this.filters.length > 0;
    }

    get hasData() {
        return this.chartRows.length > 0;
    }

    get showError() {
        return !!this.errorMessage;
    }

    get showEmptyState() {
        return this.hasLoadedOnce && !this.isLoading && !this.errorMessage && !this.hasData;
    }

    get showResults() {
        return !this.showEmptyState && !this.showError && this.hasData;
    }

    get chartVisible() {
        return !this.chartCollapsed;
    }

    get chartToggleIcon() {
        return this.chartCollapsed ? 'utility:chevrondown' : 'utility:chevronup';
    }

    get chartToggleLabel() {
        return this.chartCollapsed ? 'Show chart' : 'Hide chart';
    }

    handleToggleChart() {
        this.chartCollapsed = !this.chartCollapsed;
    }

    get canExport() {
        return this.hasData;
    }

    /** Inverse getter — lightning-button-icon takes `disabled`, not `enabled`. */
    get showExportDisabled() {
        return !this.hasData;
    }

    get resultSummary() {
        if (!this.hasLoadedOnce || this.results.length === 0) return '';
        return `${this.results.length} rows`;
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
