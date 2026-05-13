import { LightningElement, wire } from 'lwc';
import { publish, subscribe, unsubscribe, MessageContext } from 'lightning/messageService';
import AI_INSIGHTS_DATE_RANGE from '@salesforce/messageChannel/AiInsightsDateRange__c';
import getTokenConsumption from '@salesforce/apex/AiInsightsController.getTokenConsumption';
import getOverviewTrends from '@salesforce/apex/AiInsightsController.getOverviewTrends';
import { abbreviateNumber, formatPercent } from './numberFormat';
import { TOOLTIPS } from 'c/aiInsightsTooltips';
import FM_Empty_Tokens_Title from '@salesforce/label/c.FM_Empty_Tokens_Title';
import FM_Empty_Tokens_Message from '@salesforce/label/c.FM_Empty_Tokens_Message';
import FM_Action_Expand_90_Days from '@salesforce/label/c.FM_Action_Expand_90_Days';

const TT = TOOLTIPS.tokenConsumption;
const TOP_N = 10;

const GROUP_BY_OPTIONS = [
    { label: 'Prompt', value: 'Prompt' },
    { label: 'User', value: 'User' },
    { label: 'Model', value: 'Model' },
    { label: 'Day', value: 'Day' },
    { label: 'Week', value: 'Week' }
];

/**
 * Token consumption dashboard: CSS-only stacked horizontal bar chart on top,
 * `lightning-datatable` below.
 *
 * The bar chart is styled divs with flex widths keyed off `maxTotalTokens` —
 * no chart library. Each bar is split into an input-tokens segment and an
 * output-tokens segment; the per-segment width is a percentage of the row's
 * OWN total (not the global max), so inside each bar the lighter/darker split
 * reads as a proportion and the overall bar length still communicates scale
 * across rows.
 *
 * Top-N grouping builds an "Others" bucket that aggregates the tail — keeps
 * the chart legible when a user picks e.g. Group by User on a busy org.
 */
export default class AiInsightsTokenConsumption extends LightningElement {
    @wire(MessageContext)
    messageContext;

    subscription;
    // Seed a default 30-day window so the component can render even before the
    // LMS date channel has fired. If the date filter publishes a different
    // range, handleDateRange will overwrite these and re-run the query.
    startDate = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString();
    endDate = new Date().toISOString();

    groupBy = 'Prompt';
    groupByOptions = GROUP_BY_OPTIONS;

    labels = {
        emptyTitle: FM_Empty_Tokens_Title,
        emptyMessage: FM_Empty_Tokens_Message,
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

    rawRows = [];
    chartRows = [];
    tableRows = [];

    sortedBy = 'totalTokens';
    sortedDirection = 'desc';

    isLoading = false;
    hasLoadedOnce = false;
    errorMessage;
    chartCollapsed = false;

    // Group column is a button so the user can click to drill into entity
    // details. We map the current groupBy -> entityType inside the row action
    // handler. Day/Week groupings are not drillable (no single entity).
    // Canonical column order across entity tables: Label · Requests ·
    // Total tokens · Input · Output · Avg. Tokens are headline columns —
    // sortable and right-aligned so magnitudes line up vertically.
    columns = [
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
            label: 'Requests',
            fieldName: 'requestCount',
            type: 'number',
            sortable: true,
            helpText: TT.requestCount,
            cellAttributes: { alignment: 'right' },
            typeAttributes: { maximumFractionDigits: 0 }
        },
        {
            label: 'Total Tokens',
            fieldName: 'totalTokensDisplay',
            type: 'text',
            sortable: true,
            sortBy: 'totalTokens',
            helpText: TT.totalTokens,
            cellAttributes: { alignment: 'right' }
        },
        {
            label: 'Input Tokens',
            fieldName: 'inputTokensDisplay',
            type: 'text',
            sortable: true,
            sortBy: 'inputTokens',
            helpText: TT.inputTokens,
            cellAttributes: { alignment: 'right' }
        },
        {
            label: 'Output Tokens',
            fieldName: 'outputTokensDisplay',
            type: 'text',
            sortable: true,
            sortBy: 'outputTokens',
            helpText: TT.outputTokens,
            cellAttributes: { alignment: 'right' }
        },
        {
            label: 'Avg per Request',
            fieldName: 'avgPerRequestDisplay',
            type: 'text',
            sortable: true,
            sortBy: 'avgTokensPerRequest',
            helpText: TT.avgTokensPerRequest,
            cellAttributes: { alignment: 'right' }
        }
    ];

    // --- LMS + lifecycle ---------------------------------------------------

    connectedCallback() {
        this.subscription = subscribe(
            this.messageContext,
            AI_INSIGHTS_DATE_RANGE,
            (message) => this.handleDateRange(message)
        );
        // Fire an initial load using the seeded defaults so tab-switchers
        // always see something. handleDateRange re-runs when LMS publishes.
        this.loadTokens();
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
        this.loadTokens();
    }

    handleGroupByChange(event) {
        this.groupBy = event.detail.value;
        this.loadTokens();
    }

    // --- Data load ---------------------------------------------------------

    async loadTokens() {
        if (!this.startDate || !this.endDate) return;
        this.isLoading = true;
        this.errorMessage = undefined;
        try {
            // Parallelize the main group-by query with the side-channel
            // trends fetch. The daily-token series is best-effort — if it
            // rejects we leave the trend strip blank rather than failing
            // the whole tab.
            const [data, trendsResult] = await Promise.all([
                getTokenConsumption({
                    startDate: this.startDate,
                    endDate: this.endDate,
                    groupBy: this.groupBy
                }),
                getOverviewTrends({ startDate: this.startDate, endDate: this.endDate }).catch(() => null)
            ]);
            this.rawRows = Array.isArray(data) ? data : [];
            this.buildViewModel();
            this.buildTrendColumns(trendsResult);
            this.hasLoadedOnce = true;
        } catch (err) {
            this.errorMessage = this.extractError(err);
            this.rawRows = [];
            this.chartRows = [];
            this.tableRows = [];
            this.trendColumns = [];
        } finally {
            this.isLoading = false;
        }
    }

    // Per-day mini-columns strip above the detail chart. Reuses the trends
    // DTO's `dailyTokens` array — one column per day, height proportional to
    // that day's share of the peak. Kept purely decorative (no click-through);
    // the detail table below handles drill-through.
    trendColumns = [];
    get hasTrendColumns() {
        return this.trendColumns && this.trendColumns.length > 0;
    }

    buildTrendColumns(trends) {
        if (!trends || !Array.isArray(trends.dailyTokens) || trends.dailyTokens.length === 0) {
            this.trendColumns = [];
            return;
        }
        const values = trends.dailyTokens.map((v) => Number(v) || 0);
        const peak = Math.max(...values) || 1;
        this.trendColumns = values.map((v, i) => {
            const pct = Math.max(2, Math.round((v / peak) * 100));
            return {
                key: `d-${i}`,
                heightStyle: `height: ${pct}%`,
                title: `${v.toLocaleString()} tokens`
            };
        });
    }

    // --- View-model: chart + table ----------------------------------------

    buildViewModel() {
        // Sort server rows DESC by total tokens so the "Top N + Others" rollup
        // is stable regardless of server ordering.
        const sorted = [...this.rawRows].sort((a, b) => (b.totalTokens || 0) - (a.totalTokens || 0));

        const top = sorted.slice(0, TOP_N);
        const tail = sorted.slice(TOP_N);

        const chartRows = top.map((r) => this.toChartRow(r));

        if (tail.length > 0) {
            const othersInput = tail.reduce((acc, r) => acc + Number(r.inputTokens || 0), 0);
            const othersOutput = tail.reduce((acc, r) => acc + Number(r.outputTokens || 0), 0);
            const othersTotal = othersInput + othersOutput;
            const othersRequests = tail.reduce((acc, r) => acc + Number(r.requestCount || 0), 0);
            chartRows.push(this.toChartRow({
                groupKey: '__others__',
                groupLabel: `Others (${tail.length})`,
                inputTokens: othersInput,
                outputTokens: othersOutput,
                totalTokens: othersTotal,
                requestCount: othersRequests,
                avgTokensPerRequest: othersRequests > 0 ? othersTotal / othersRequests : 0
            }));
        }

        const grandTotal = chartRows.reduce((acc, r) => acc + Number(r.totalTokens || 0), 0);
        const maxTotal = chartRows.reduce((acc, r) => Math.max(acc, Number(r.totalTokens || 0)), 0);

        // Second pass: width percentages rely on max (for overall bar length)
        // and per-row share (for the input/output split inside each bar).
        this.chartRows = chartRows.map((r) => this.withBarGeometry(r, maxTotal, grandTotal));

        // Table uses ALL rows (not just top 10) plus full display formatting.
        this.tableRows = sorted.map((r) => this.toTableRow(r));
        this.applySort();
    }

    toChartRow(r) {
        const input = Number(r.inputTokens || 0);
        const output = Number(r.outputTokens || 0);
        const total = input + output;
        return {
            groupKey: r.groupKey,
            groupLabel: r.groupLabel || r.groupKey || '—',
            inputTokens: input,
            outputTokens: output,
            totalTokens: total,
            requestCount: Number(r.requestCount || 0),
            avgTokensPerRequest: Number(r.avgTokensPerRequest || 0)
        };
    }

    withBarGeometry(row, maxTotal, grandTotal) {
        const barWidth = maxTotal > 0 ? (row.totalTokens / maxTotal) * 100 : 0;
        const rowTotal = row.totalTokens || 0;
        const inputPctInRow = rowTotal > 0 ? (row.inputTokens / rowTotal) * 100 : 0;
        const outputPctInRow = rowTotal > 0 ? 100 - inputPctInRow : 0;
        const sharePct = grandTotal > 0 ? (row.totalTokens / grandTotal) * 100 : 0;

        return {
            ...row,
            totalDisplay: abbreviateNumber(row.totalTokens),
            inputDisplay: abbreviateNumber(row.inputTokens),
            outputDisplay: abbreviateNumber(row.outputTokens),
            sharePctDisplay: formatPercent(sharePct / 100),
            // inline styles keep the bar renderer CSS-only.
            barStyle: `width: ${barWidth.toFixed(2)}%;`,
            inputSegmentStyle: `width: ${inputPctInRow.toFixed(2)}%;`,
            outputSegmentStyle: `width: ${outputPctInRow.toFixed(2)}%;`,
            ariaLabel: `${row.groupLabel}: ${abbreviateNumber(row.totalTokens)} total tokens, ${formatPercent(sharePct / 100)} of top ${TOP_N} plus others.`
        };
    }

    toTableRow(r) {
        const input = Number(r.inputTokens || 0);
        const output = Number(r.outputTokens || 0);
        const total = input + output;
        const avg = Number(r.avgTokensPerRequest || 0);
        // Every grouping is drillable now — Day/Week drill into a time-bucket
        // filter that the details modal resolves as a dated request list.
        const drillDisabled = false;
        return {
            groupKey: r.groupKey,
            groupLabel: r.groupLabel || r.groupKey || '—',
            inputTokens: input,
            outputTokens: output,
            totalTokens: total,
            requestCount: Number(r.requestCount || 0),
            avgTokensPerRequest: avg,
            inputTokensDisplay: abbreviateNumber(input),
            outputTokensDisplay: abbreviateNumber(output),
            totalTokensDisplay: abbreviateNumber(total),
            avgPerRequestDisplay: abbreviateNumber(avg),
            drillDisabled,
            // LWC templates forbid !negation inline, so expose the inverse
            // directly for the hand-rolled table's two-template switch.
            drillEnabled: !drillDisabled
        };
    }

    // --- Drill-in ----------------------------------------------------------

    get groupColumnTooltip() {
        return (TT && TT.clickToDrill) || (TT && TT.groupLabel) || '';
    }

    /**
     * Fires when a user clicks a Group link in the hand-rolled detail table.
     * Maps the current `groupBy` to an entityType and opens the shared
     * entity-details modal. We use plain <a> + onclick instead of
     * lightning-datatable button cells because the datatable cell variant
     * proved unreliable across theme / cache states.
     */
    handleGroupClick(event) {
        event.preventDefault();
        const groupKey = event.currentTarget.dataset.groupKey;
        const groupLabel = event.currentTarget.dataset.groupLabel;
        // Token group-by values are PascalCase ("Prompt", "User", ...) —
        // match on the actual values, not lowercase. Earlier version used
        // lowercase keys so every click silently fell through.
        const map = {
            Prompt: 'PromptTemplate',
            User: 'User',
            Model: 'Model',
            Day: 'TimeBucket',
            Week: 'TimeBucket'
        };
        const entityType = map[this.groupBy];
        if (!entityType) return;

        // Day/Week buckets need a date range instead of an entity key. The
        // Apex side resolves TimeBucket by falling back to the passed
        // start/end timestamps. groupKey is the ISO date ("2026-04-23" or
        // "Wk 2026-04-20"); parse it back to an inclusive day/week range.
        let startIso = this.startDate;
        let endIso = this.endDate;
        if (entityType === 'TimeBucket') {
            const range = this.rangeForBucket(groupKey);
            if (range) {
                startIso = range.start;
                endIso = range.end;
            }
        }

        const panel = this.template.querySelector('c-ai-insights-drill-panel');
        if (panel && typeof panel.open === 'function') {
            panel.open(entityType, groupKey, groupLabel, startIso, endIso);
        }
    }

    /**
     * Given a bucket label like "2026-04-23" (day) or "Wk 2026-04-20" (week),
     * return the inclusive ISO start/end timestamps for the drill-in.
     */
    rangeForBucket(groupKey) {
        if (!groupKey) return null;
        const isWeek = groupKey.startsWith('Wk ');
        const iso = isWeek ? groupKey.slice(3) : groupKey;
        const start = new Date(`${iso}T00:00:00.000Z`);
        if (Number.isNaN(start.getTime())) return null;
        const end = new Date(start);
        end.setUTCDate(end.getUTCDate() + (isWeek ? 7 : 1));
        end.setUTCMilliseconds(-1); // inclusive end of bucket
        return { start: start.toISOString(), end: end.toISOString() };
    }

    // --- Sort (table only) -------------------------------------------------

    handleSort(event) {
        const columnDef = this.columns.find((c) => c.fieldName === event.detail.fieldName);
        this.sortedBy = (columnDef && columnDef.sortBy) || event.detail.fieldName;
        this.sortedDirection = event.detail.sortDirection;
        this.applySort();
    }

    applySort() {
        const key = this.sortedBy;
        const direction = this.sortedDirection === 'desc' ? -1 : 1;
        this.tableRows = [...this.tableRows].sort((a, b) => {
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

    // --- State getters -----------------------------------------------------

    get hasData() {
        return this.chartRows.length > 0;
    }

    get showEmptyState() {
        return this.hasLoadedOnce && !this.isLoading && !this.errorMessage && !this.hasData;
    }

    get showError() {
        return !!this.errorMessage;
    }

    get showChart() {
        return !this.showEmptyState && !this.showError && this.chartRows.length > 0;
    }

    get chartVisible() {
        return this.showChart && !this.chartCollapsed;
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

    get showTable() {
        return !this.showEmptyState && !this.showError && this.tableRows.length > 0;
    }

    get groupingSummary() {
        if (!this.hasLoadedOnce) return '';
        return `${this.rawRows.length} groups · Top ${Math.min(this.rawRows.length, TOP_N)} charted`;
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