import { LightningElement, wire } from 'lwc';
import { publish, subscribe, unsubscribe, MessageContext } from 'lightning/messageService';
import AI_INSIGHTS_DATE_RANGE from '@salesforce/messageChannel/AiInsightsDateRange__c';
import getUsageByPrompt from '@salesforce/apex/AiInsightsController.getUsageByPrompt';
import { abbreviateNumber, formatPercent } from './numberFormat';
import { TOOLTIPS } from 'c/aiInsightsTooltips';
import FM_Empty_Prompts_Title from '@salesforce/label/c.FM_Empty_Prompts_Title';
import FM_Empty_Prompts_Message from '@salesforce/label/c.FM_Empty_Prompts_Message';
import FM_Action_Expand_90_Days from '@salesforce/label/c.FM_Action_Expand_90_Days';

const INITIAL_PAGE_SIZE = 25;
const PAGE_STEP = 25;
const TT = TOOLTIPS.promptAnalytics;

/**
 * Per-prompt-template usage table.
 *
 * Subscribes to the shared date range on `AiInsightsDateRange__c`, calls
 * `AiInsightsController.getUsageByPrompt`, and renders a sortable, searchable
 * lightning-datatable. Clicking a row fires a `promptselected` custom event
 * carrying `{ promptDevName, promptLabel }`; the parent `aiInsightsApp`
 * bridges it to `aiInsightsPromptOutputViewer`.
 *
 * Every column uses `helpText` so hovering the header reveals the metric
 * definition — a tiny but important accessibility / self-service feature.
 */
export default class AiInsightsPromptAnalytics extends LightningElement {
    @wire(MessageContext)
    messageContext;

    subscription;
    // Seed a default 30-day window so the component can render even before the
    // LMS date channel has fired. If the date filter publishes a different
    // range, handleDateRange will overwrite these and re-run the query.
    startDate = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString();
    endDate = new Date().toISOString();

    rawRows = [];
    allRows = [];
    filteredRows = [];
    visibleRows = [];

    sortedBy = 'invocationCount';
    sortedDirection = 'desc';
    searchTerm = '';
    visibleCount = INITIAL_PAGE_SIZE;

    selectedPromptDevName;

    isLoading = false;
    hasLoadedOnce = false;
    errorMessage;

    labels = {
        emptyTitle: FM_Empty_Prompts_Title,
        emptyMessage: FM_Empty_Prompts_Message,
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

    columns = [
        {
            label: 'Prompt Template',
            fieldName: 'promptLabel',
            type: 'button',
            sortable: true,
            wrapText: true,
            helpText: TT.promptLabel,
            typeAttributes: {
                label: { fieldName: 'promptLabel' },
                name: 'select',
                variant: 'base',
                title: 'View outputs for this prompt'
            },
            cellAttributes: { class: { fieldName: 'promptLabelClass' } }
        },
        { label: 'Feature', fieldName: 'featureName', type: 'text', sortable: true, helpText: TT.featureName },
        {
            label: 'Invocations',
            fieldName: 'invocationCount',
            type: 'number',
            sortable: true,
            helpText: TT.invocationCount,
            cellAttributes: { alignment: 'right' },
            typeAttributes: { maximumFractionDigits: 0 }
        },
        {
            label: 'Unique Users',
            fieldName: 'uniqueUserCount',
            type: 'number',
            sortable: true,
            helpText: TT.uniqueUserCount,
            cellAttributes: { alignment: 'right' },
            typeAttributes: { maximumFractionDigits: 0 }
        },
        {
            label: 'Acceptance Rate',
            fieldName: 'acceptanceRateDisplay',
            type: 'text',
            sortable: true,
            sortBy: 'acceptanceRate',
            helpText: TT.acceptanceRate,
            cellAttributes: {
                iconName: { fieldName: 'acceptanceRateIcon' },
                iconPosition: 'left',
                class: { fieldName: 'acceptanceRateClass' }
            }
        },
        {
            label: 'Avg Tokens',
            fieldName: 'avgTokensDisplay',
            type: 'text',
            sortable: true,
            sortBy: 'avgTokens',
            helpText: TT.avgTokens,
            cellAttributes: { alignment: 'right' }
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
            label: 'Safety Flags',
            fieldName: 'toxicFlagCount',
            type: 'number',
            sortable: true,
            helpText: TT.toxicFlagCount,
            cellAttributes: {
                alignment: 'right',
                class: { fieldName: 'toxicFlagClass' }
            },
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
            label: 'Cost conf.',
            fieldName: 'costConfidenceLabel',
            type: 'text',
            sortable: true,
            sortBy: 'costConfidence',
            helpText:
                'Confidence in the cost figure for this prompt. HIGH = exact rate-card match; ESTIMATED = prefix walk; ' +
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
        this.loadPrompts();
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
        this.loadPrompts();
    }

    async loadPrompts() {
        this.isLoading = true;
        this.errorMessage = undefined;
        try {
            const data = await getUsageByPrompt({ startDate: this.startDate, endDate: this.endDate });
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

    // --- View model ---------------------------------------------------------

    toViewModel(row) {
        const pct = this.ratePercent(row.acceptanceRate);
        const avgTokens = (row.avgInputTokens || 0) + (row.avgOutputTokens || 0);
        const isSelected = this.selectedPromptDevName === row.promptDevName;
        const toxic = row.toxicFlagCount || 0;
        const conf = (row.costConfidence || 'HIGH').toUpperCase();
        return {
            ...row,
            avgTokens,
            avgTokensDisplay: abbreviateNumber(avgTokens),
            totalTokensDisplay: abbreviateNumber(row.totalTokens || 0),
            acceptanceRateDisplay: pct === null ? '—' : formatPercent(row.acceptanceRate),
            acceptanceRateIcon: this.rateIcon(pct),
            acceptanceRateClass: this.rateClass(pct),
            promptLabelClass: isSelected ? 'fm-row_selected slds-text-title_bold' : '',
            toxicFlagClass: toxic > 0 ? 'slds-text-color_error slds-text-title_bold' : '',
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

    rateIcon(pct) {
        if (pct === null) return null;
        if (pct > 70) return 'utility:success';
        if (pct >= 50) return 'utility:warning';
        return 'utility:error';
    }

    rateClass(pct) {
        if (pct === null) return '';
        if (pct > 70) return 'slds-text-color_success';
        if (pct >= 50) return 'fm-text_warning';
        return 'slds-text-color_error';
    }

    ratePercent(value) {
        if (value === null || value === undefined || Number.isNaN(Number(value))) return null;
        const n = Number(value);
        return Math.abs(n) <= 1 ? n * 100 : n;
    }

    // --- Search / sort / pagination ----------------------------------------

    handleSearch(event) {
        this.searchTerm = (event.detail.value || '').trim().toLowerCase();
        this.visibleCount = INITIAL_PAGE_SIZE;
        this.applyFilterAndPagination();
    }

    handleSort(event) {
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
                const label = (r.promptLabel || '').toLowerCase();
                const feature = (r.featureName || '').toLowerCase();
                return label.includes(this.searchTerm) || feature.includes(this.searchTerm);
            });
        }
        this.filteredRows = rows;
        this.visibleRows = rows.slice(0, this.visibleCount);
    }

    handleLoadMore() {
        this.visibleCount += PAGE_STEP;
        this.applyFilterAndPagination();
    }

    // --- Row selection ------------------------------------------------------

    // Fires when the "Prompt Template" button cell is clicked.
    handleRowAction(event) {
        const row = event.detail.row;
        if (row) this.selectPrompt(row);
    }

    selectPrompt(row) {
        this.selectedPromptDevName = row.promptDevName;
        // Re-build view models so the selected row picks up the highlight class.
        this.allRows = this.rawRows.map((r) => this.toViewModel(r));
        this.applySort();
        this.applyFilterAndPagination();

        this.dispatchEvent(new CustomEvent('promptselected', {
            detail: {
                promptDevName: row.promptDevName,
                promptLabel: row.promptLabel
            },
            bubbles: true,
            composed: true
        }));
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
