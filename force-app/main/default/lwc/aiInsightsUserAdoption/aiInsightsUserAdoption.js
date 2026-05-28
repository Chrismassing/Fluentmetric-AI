import { LightningElement, wire } from 'lwc';
import { subscribe, unsubscribe, MessageContext } from 'lightning/messageService';
import AI_INSIGHTS_DATE_RANGE from '@salesforce/messageChannel/AiInsightsDateRange__c';
import getUsageByUser from '@salesforce/apex/AiInsightsController.getUsageByUser';
import getCostSettings from '@salesforce/apex/AiInsightsController.getCostSettings';
import { abbreviateNumber, formatPercent } from './numberFormat';
import { TOOLTIPS } from 'c/aiInsightsTooltips';
import FM_Adoption_Cohort_Column from '@salesforce/label/c.FM_Adoption_Cohort_Column';
import FM_Adoption_Tier_Column from '@salesforce/label/c.FM_Adoption_Tier_Column';
import FM_Adoption_Tier_Top1 from '@salesforce/label/c.FM_Adoption_Tier_Top1';
import FM_Adoption_Tier_Top10 from '@salesforce/label/c.FM_Adoption_Tier_Top10';

const TT = TOOLTIPS.userAdoption;

const INITIAL_PAGE_SIZE = 25;
const PAGE_STEP = 25;

/**
 * Per-user adoption datatable. Subscribes to the shared date range, fetches
 * List<UserUsageDTO> from the controller, and renders a sortable, searchable
 * lightning-datatable with a client-side "Load More" pagination pattern.
 *
 * Columns are defined once as flat fields — topPrompts (List<String>) is
 * pre-joined to a comma-separated string with a max of 3 entries for display.
 */
export default class AiInsightsUserAdoption extends LightningElement {
    @wire(MessageContext)
    messageContext;

    subscription;
    // Seed a default 30-day window so the component can render even before the
    // LMS date channel has fired. If the date filter publishes a different
    // range, handleDateRange will overwrite these and re-run the query.
    startDate = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString();
    endDate = new Date().toISOString();
    presetLabel;

    rawRows = [];         // raw DTO rows from Apex
    allRows = [];         // flattened view-model rows
    filteredRows = [];    // after search filter
    visibleRows = [];     // after pagination slice

    sortedBy = 'requestCount';
    sortedDirection = 'desc';
    searchTerm = '';
    visibleCount = INITIAL_PAGE_SIZE;

    isLoading = false;
    hasLoadedOnce = false;
    errorMessage;

    // helpText on each column renders a little info icon in the header with
    // the tooltip content on hover — native lightning-datatable feature,
    // keeps every metric self-documenting without custom header renderers.
    // The User cell is rendered as a button so clicks open the drill-in
    // modal; the `name` field on the typeAttributes is what comes back on the
    // onrowaction event, so we key on "drillToUser" to route the handler.
    // Column order convention across all entity tables (Users / Tokens /
    // Explorer / drill panel): Label · Requests · Tokens · Acceptance ·
    // Last seen · First seen · supporting columns · Cost (gated). Putting
    // the headline numbers next to the label keeps cross-table comparison
    // honest and "sort by tokens" one click away.
    columns = [
        {
            label: 'User',
            fieldName: 'userName',
            type: 'button',
            sortable: true,
            wrapText: false,
            helpText: TT.userName,
            sortBy: 'userName',
            typeAttributes: {
                label: { fieldName: 'userName' },
                name: 'drillToUser',
                variant: 'base',
                title: TT.clickToDrill
            }
        },
        {
            label: FM_Adoption_Tier_Column,
            fieldName: 'tierLabel',
            type: 'text',
            sortable: true,
            sortBy: 'tierRank',
            helpText:
                'Pareto power-user segment: Top 1% / Top 10% / Standard. ' +
                'Derived client-side by sorting users by request count DESC and bucketing the top tail.',
            cellAttributes: {
                iconName: { fieldName: 'tierIcon' },
                iconPosition: 'left',
                class: { fieldName: 'tierClass' }
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
            label: 'Acceptance Rate',
            fieldName: 'feedbackRatioDisplay',
            type: 'text',
            sortable: true,
            sortBy: 'feedbackRatio',
            helpText: TT.feedbackRatio,
            cellAttributes: {
                iconName: { fieldName: 'feedbackRatioIcon' },
                iconPosition: 'left',
                class: { fieldName: 'feedbackRatioClass' }
            }
        },
        {
            label: 'Last Used',
            fieldName: 'lastUsed',
            type: 'date',
            sortable: true,
            helpText: TT.lastUsed,
            typeAttributes: {
                year: 'numeric',
                month: 'short',
                day: '2-digit',
                hour: '2-digit',
                minute: '2-digit'
            }
        },
        {
            label: 'First Used',
            fieldName: 'firstUsed',
            type: 'date',
            sortable: true,
            helpText: TT.firstUsed,
            typeAttributes: {
                year: 'numeric',
                month: 'short',
                day: '2-digit',
                hour: '2-digit',
                minute: '2-digit'
            }
        },
        {
            label: FM_Adoption_Cohort_Column,
            fieldName: 'cohortLabel',
            type: 'text',
            sortable: true,
            sortBy: 'cohortKey',
            helpText:
                'ISO-8601 week the user was first observed (YYYY-Www). Derived client-side from the firstUsed timestamp; ' +
                'sortable so cohort waves cluster together.'
        },
        { label: 'Top Prompts', fieldName: 'topPromptsDisplay', type: 'text', sortable: false, wrapText: true, helpText: TT.topPrompts },
        { label: 'Profile', fieldName: 'profileName', type: 'text', sortable: true, helpText: TT.profileName },
        { label: 'Department', fieldName: 'department', type: 'text', sortable: true, helpText: TT.department },
        {
            label: 'Est. Cost',
            fieldName: 'estimatedUsdDisplay',
            type: 'text',
            sortable: true,
            sortBy: 'estimatedUsd',
            helpText:
                'Estimated USD this user spent on Einstein GenAI in the range. ' +
                'Computed as SUM(tier-based FC × Flex_Credit_USD_Rate__c) with overage and discount applied. ' +
                'See the confidence badge beside each row for match quality.',
            cellAttributes: { alignment: 'right' }
        },
        {
            label: 'Cost conf.',
            fieldName: 'costConfidenceLabel',
            type: 'text',
            sortable: true,
            sortBy: 'costConfidence',
            helpText:
                'Confidence in the cost figure. HIGH = exact rate-card match; ESTIMATED = prefix walk; ' +
                'FALLBACK = default rate record; NOT_COSTED = Agentforce row without STDM.',
            cellAttributes: { alignment: 'center' }
        }
    ];

    connectedCallback() {
        this.subscription = subscribe(
            this.messageContext,
            AI_INSIGHTS_DATE_RANGE,
            (message) => this.handleDateRange(message)
        );
        // Fire an initial load using the seeded defaults so tab-switchers
        // always see something. handleDateRange re-runs when LMS publishes.
        this.loadUsers();
        // Gate the Est. Cost column on the org's opt-in flag. We filter the
        // columns array in place so lightning-datatable simply sees a
        // different set of columns when cost is off.
        this.applyCostGate();
    }

    async applyCostGate() {
        try {
            const s = await getCostSettings();
            const enabled = s && s.enabled === true;
            if (!enabled) {
                // Drop the Est. Cost column entirely when cost metrics are off.
                this.columns = this.columns.filter(
                    (c) => c.fieldName !== 'estimatedUsdDisplay'
                );
            }
        } catch (err) {
            // Setting may not exist yet on fresh installs — keep the column
            // hidden rather than showing $0 everywhere and confusing users.
            this.columns = this.columns.filter(
                (c) => c.fieldName !== 'estimatedUsdDisplay'
            );
        }
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
        this.loadUsers();
    }

    async loadUsers() {
        this.isLoading = true;
        this.errorMessage = undefined;
        try {
            const data = await getUsageByUser({ startDate: this.startDate, endDate: this.endDate });
            this.rawRows = Array.isArray(data) ? data : [];
            this.allRows = this.rawRows.map((row) => this.toViewModel(row));
            // Pareto tier assignment requires the full sorted set, so it runs
            // once after every row has its base view-model fields populated.
            this.assignPowerUserTiers();
            this.applySort();
            this.applyFilterAndPagination();
            this.hasLoadedOnce = true;
        } catch (err) {
            this.errorMessage = this.extractError(err);
            this.rawRows = [];
            this.allRows = [];
            this.filteredRows = [];
            this.visibleRows = [];
        } finally {
            this.isLoading = false;
        }
    }

    // --- View model construction --------------------------------------------

    toViewModel(row) {
        const ratioPct = this.ratePercent(row.feedbackRatio);
        const usd = Number(row.estimatedUsd || 0);
        const conf = (row.costConfidence || 'HIGH').toUpperCase();
        const cohort = this.cohortFromTimestamp(row.firstUsed);
        return {
            ...row,
            totalTokensDisplay: abbreviateNumber(row.totalTokens || 0),
            estimatedUsdDisplay: `$${usd.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`,
            topPromptsDisplay: this.formatTopPrompts(row.topPrompts),
            feedbackRatioDisplay: ratioPct === null ? '—' : formatPercent(row.feedbackRatio),
            feedbackRatioIcon: this.feedbackRatioIcon(ratioPct),
            feedbackRatioClass: this.feedbackRatioCellClass(ratioPct),
            costConfidence: conf,
            costConfidenceLabel: this.confidenceLabel(conf),
            // Cohort and tier defaults; tier is reassigned post-load by
            // assignPowerUserTiers once every row's request count is known.
            cohortLabel: cohort.label,
            cohortKey: cohort.key,
            tierLabel: 'Standard',
            tierRank: 3,
            tierIcon: null,
            tierClass: 'slds-text-color_weak'
        };
    }

    // Returns { label, key } where label is the human-readable ISO-week
    // ('YYYY-Www', e.g. '2026-W21') and key is sortable ('YYYY-Www' is
    // already sortable as a string when zero-padded).
    cohortFromTimestamp(value) {
        if (!value) return { label: '—', key: '' };
        const ts = typeof value === 'number' ? value : Date.parse(value);
        if (Number.isNaN(ts)) return { label: '—', key: '' };
        // ISO 8601 week-of-year: Thursday-of-week's calendar year, week
        // numbered from the Monday of the year's first week (week containing
        // its first Thursday). Cribbed from the standard JS recipe.
        const d = new Date(ts);
        const dayNr = (d.getUTCDay() + 6) % 7; // 0=Mon, 6=Sun
        d.setUTCDate(d.getUTCDate() - dayNr + 3); // shift to Thursday
        const firstThursday = new Date(Date.UTC(d.getUTCFullYear(), 0, 4));
        const weekNr =
            1 +
            Math.round(
                ((d - firstThursday) / 86400000 -
                    3 +
                    ((firstThursday.getUTCDay() + 6) % 7)) /
                    7
            );
        const wk = String(weekNr).padStart(2, '0');
        const yr = d.getUTCFullYear();
        const label = `${yr}-W${wk}`;
        return { label, key: label };
    }

    // Pareto buckets: top-1% / top-10% / standard. Sorts a copy of allRows
    // by request count DESC, walks the top tail, and writes tierLabel +
    // tierRank + tierIcon + tierClass back into the original row objects so
    // both the datatable cell and any sort-by-tier behave consistently.
    assignPowerUserTiers() {
        if (!Array.isArray(this.allRows) || this.allRows.length === 0) return;
        const sorted = [...this.allRows].sort(
            (a, b) => (Number(b.requestCount) || 0) - (Number(a.requestCount) || 0)
        );
        const total = sorted.length;
        const top1Count = Math.max(1, Math.ceil(total * 0.01));
        const top10Count = Math.max(1, Math.ceil(total * 0.1));
        sorted.forEach((row, idx) => {
            // Skip zero-request rows even when they fall inside the percentile
            // — a tier badge on a user with 0 activity is misleading.
            if ((row.requestCount || 0) <= 0) {
                row.tierLabel = 'Standard';
                row.tierRank = 3;
                row.tierIcon = null;
                row.tierClass = 'slds-text-color_weak';
                return;
            }
            if (idx < top1Count) {
                row.tierLabel = FM_Adoption_Tier_Top1;
                row.tierRank = 1;
                row.tierIcon = 'utility:trophy';
                row.tierClass = 'fm-tier_top1';
            } else if (idx < top10Count) {
                row.tierLabel = FM_Adoption_Tier_Top10;
                row.tierRank = 2;
                row.tierIcon = 'utility:trending';
                row.tierClass = 'fm-tier_top10';
            } else {
                row.tierLabel = 'Standard';
                row.tierRank = 3;
                row.tierIcon = null;
                row.tierClass = 'slds-text-color_weak';
            }
        });
    }

    confidenceLabel(conf) {
        switch (conf) {
            case 'HIGH': return 'High';
            case 'ESTIMATED': return 'Estimated';
            case 'FALLBACK': return 'Fallback';
            case 'NOT_COSTED': return 'Not costed';
            default: return 'High';
        }
    }

    formatTopPrompts(prompts) {
        if (!Array.isArray(prompts) || prompts.length === 0) {
            return '';
        }
        return prompts.slice(0, 3).join(', ');
    }

    feedbackRatioIcon(pct) {
        if (pct === null) return null;
        if (pct > 70) return 'utility:success';
        if (pct >= 50) return 'utility:warning';
        return 'utility:error';
    }

    feedbackRatioCellClass(pct) {
        if (pct === null) return '';
        if (pct > 70) return 'slds-text-color_success';
        if (pct >= 50) return 'fm-text_warning';
        return 'slds-text-color_error';
    }

    ratePercent(value) {
        if (value === null || value === undefined || Number.isNaN(Number(value))) {
            return null;
        }
        const n = Number(value);
        return Math.abs(n) <= 1 ? n * 100 : n;
    }

    // --- Search + sort + pagination ----------------------------------------

    handleSearch(event) {
        this.searchTerm = (event.detail.value || '').trim().toLowerCase();
        this.visibleCount = INITIAL_PAGE_SIZE;
        this.applyFilterAndPagination();
    }

    handleSort(event) {
        // lightning-datatable dispatches fieldName from the column def; honor sortBy if present.
        const columnDef = this.columns.find((c) => c.fieldName === event.detail.fieldName);
        this.sortedBy = (columnDef && columnDef.sortBy) || event.detail.fieldName;
        this.sortedDirection = event.detail.sortDirection;
        this.applySort();
        this.applyFilterAndPagination();
    }

    applySort() {
        const key = this.sortedBy;
        const direction = this.sortedDirection === 'desc' ? -1 : 1;
        this.allRows = [...this.allRows].sort((a, b) => {
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

    applyFilterAndPagination() {
        let rows = this.allRows;
        if (this.searchTerm) {
            rows = rows.filter((r) => {
                const name = (r.userName || '').toLowerCase();
                const dept = (r.department || '').toLowerCase();
                return name.includes(this.searchTerm) || dept.includes(this.searchTerm);
            });
        }
        this.filteredRows = rows;
        this.visibleRows = rows.slice(0, this.visibleCount);
    }

    handleLoadMore() {
        this.visibleCount += PAGE_STEP;
        this.applyFilterAndPagination();
    }

    // --- Drill-in modal ---------------------------------------------------

    /**
     * lightning-datatable button cells emit `rowaction` with the row payload
     * and the action name from typeAttributes.name. We reuse the current
     * startDate/endDate so the drill-in shares scope with the table.
     *
     * We deliberately use `this.template.querySelector(...)` rather than
     * `lwc:ref` — the ref pattern proved flaky on earlier rounds when the
     * referenced element was inside a conditional template. querySelector on
     * the always-rendered tag is the fix pattern we settled on.
     */
    handleRowAction(event) {
        const actionName = event.detail.action && event.detail.action.name;
        const row = event.detail.row || {};
        if (actionName !== 'drillToUser') return;
        const panel = this.template.querySelector('c-ai-insights-drill-panel');
        if (panel && typeof panel.open === 'function') {
            panel.open('User', row.userId, row.userName, this.startDate, this.endDate);
        }
    }

    // --- State getters ------------------------------------------------------

    get hasData() {
        return this.filteredRows.length > 0;
    }

    get showEmptyState() {
        return this.hasLoadedOnce && !this.isLoading && !this.errorMessage && this.rawRows.length === 0;
    }

    get showNoMatches() {
        return this.hasLoadedOnce && !this.isLoading && !this.errorMessage && this.rawRows.length > 0 && this.filteredRows.length === 0;
    }

    get showError() {
        return !!this.errorMessage;
    }

    get showTable() {
        return !this.showEmptyState && !this.showError;
    }

    get showLoadMore() {
        return this.filteredRows.length > this.visibleRows.length;
    }

    get resultSummary() {
        if (!this.hasLoadedOnce) return '';
        const total = this.filteredRows.length;
        const shown = this.visibleRows.length;
        if (total === 0) return '';
        if (total === shown) return `Showing ${shown} of ${total}`;
        return `Showing ${shown} of ${total}`;
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
