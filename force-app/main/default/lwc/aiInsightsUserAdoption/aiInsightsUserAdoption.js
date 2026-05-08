import { LightningElement, wire } from 'lwc';
import { subscribe, unsubscribe, MessageContext } from 'lightning/messageService';
import AI_INSIGHTS_DATE_RANGE from '@salesforce/messageChannel/AiInsightsDateRange__c';
import getUsageByUser from '@salesforce/apex/AiInsightsController.getUsageByUser';
import getCostSettings from '@salesforce/apex/AiInsightsController.getCostSettings';
import { abbreviateNumber, formatPercent } from './numberFormat';
import { TOOLTIPS } from 'c/aiInsightsTooltips';

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
        { label: 'Profile', fieldName: 'profileName', type: 'text', sortable: true, helpText: TT.profileName },
        { label: 'Department', fieldName: 'department', type: 'text', sortable: true, helpText: TT.department },
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
            label: 'First Used',
            fieldName: 'firstUsed',
            type: 'date',
            sortable: true,
            helpText: TT.firstUsed,
            typeAttributes: { year: 'numeric', month: 'short', day: '2-digit' }
        },
        {
            label: 'Last Used',
            fieldName: 'lastUsed',
            type: 'date',
            sortable: true,
            helpText: TT.lastUsed,
            typeAttributes: { year: 'numeric', month: 'short', day: '2-digit' }
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
        { label: 'Top Prompts', fieldName: 'topPromptsDisplay', type: 'text', sortable: false, wrapText: true, helpText: TT.topPrompts },
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
        return {
            ...row,
            totalTokensDisplay: abbreviateNumber(row.totalTokens || 0),
            estimatedUsdDisplay: `$${usd.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`,
            topPromptsDisplay: this.formatTopPrompts(row.topPrompts),
            feedbackRatioDisplay: ratioPct === null ? '—' : formatPercent(row.feedbackRatio),
            feedbackRatioIcon: this.feedbackRatioIcon(ratioPct),
            feedbackRatioClass: this.feedbackRatioCellClass(ratioPct),
            costConfidence: conf,
            costConfidenceLabel: this.confidenceLabel(conf)
        };
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
        const modal = this.template.querySelector('c-ai-insights-details-modal');
        if (modal && typeof modal.open === 'function') {
            modal.open('User', row.userId, row.userName, this.startDate, this.endDate);
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
