import { LightningElement, wire } from 'lwc';
import { subscribe, unsubscribe, MessageContext } from 'lightning/messageService';
import AI_INSIGHTS_DATE_RANGE from '@salesforce/messageChannel/AiInsightsDateRange__c';
import getFeatureAdoption from '@salesforce/apex/AiInsightsController.getFeatureAdoption';

/**
 * Per-feature breadth/depth adoption table. Subscribes to AiInsightsDateRange
 * only — the FeatureAdoption analytics already include their own breadth /
 * depth scoping, and feeding the dimension-filter rail in here would just
 * double-count the breadth denominator.
 *
 * Rows are sortable in-place on every numeric column. Click → drill panel
 * uses the same convention as the User Adoption table.
 */
export default class AiInsightsFeatureAdoption extends LightningElement {
    @wire(MessageContext)
    messageContext;

    subscription;
    startDate = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString();
    endDate = new Date().toISOString();

    rawRows = [];
    allRows = [];

    isLoading = false;
    hasLoadedOnce = false;
    errorMessage;

    sortedBy = 'invocationCount';
    sortedDirection = 'desc';

    columns = [
        {
            label: 'Feature',
            fieldName: 'featureName',
            type: 'button',
            sortable: true,
            sortBy: 'featureName',
            wrapText: false,
            typeAttributes: {
                label: { fieldName: 'featureName' },
                name: 'drillToFeature',
                variant: 'base',
                title: 'Open feature drill-in'
            }
        },
        {
            label: 'Unique Users',
            fieldName: 'uniqueUserCount',
            type: 'number',
            sortable: true,
            cellAttributes: { alignment: 'right' },
            typeAttributes: { maximumFractionDigits: 0 },
            helpText: 'Distinct users who triggered this feature in the date range.'
        },
        {
            label: 'Breadth %',
            fieldName: 'breadthDisplay',
            type: 'text',
            sortable: true,
            sortBy: 'breadthRate',
            cellAttributes: { alignment: 'right' },
            helpText:
                'Unique users who triggered this feature ÷ entitled-user denominator. ' +
                'Falls back to total active org users when no AI permission set is configured.'
        },
        {
            label: 'Depth (median)',
            fieldName: 'depthDisplay',
            type: 'text',
            sortable: true,
            sortBy: 'depthMedian',
            cellAttributes: { alignment: 'right' },
            helpText: 'Median invocations per active user — high = deeply engaged audience.'
        },
        {
            label: 'Repeat Users',
            fieldName: 'repeatUserCount',
            type: 'number',
            sortable: true,
            cellAttributes: { alignment: 'right' },
            typeAttributes: { maximumFractionDigits: 0 },
            helpText: 'Users with two or more invocations in the window.'
        },
        {
            label: 'Invocations',
            fieldName: 'invocationCount',
            type: 'number',
            sortable: true,
            cellAttributes: { alignment: 'right' },
            typeAttributes: { maximumFractionDigits: 0 },
            helpText: 'COUNT(Id) on GenAIGatewayRequest__dlm grouped by featureName__c.'
        },
        {
            label: 'First Seen (org)',
            fieldName: 'firstObservedInOrg',
            type: 'date',
            sortable: true,
            typeAttributes: { year: 'numeric', month: 'short', day: '2-digit' },
            helpText:
                'Earliest invocation of this feature anywhere in the org — predates the date filter so you can see when adoption began.'
        }
    ];

    connectedCallback() {
        this.subscription = subscribe(
            this.messageContext,
            AI_INSIGHTS_DATE_RANGE,
            (message) => this.handleDateRange(message)
        );
        this.load();
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
        this.load();
    }

    async load() {
        this.isLoading = true;
        this.errorMessage = undefined;
        try {
            const data = await getFeatureAdoption({
                startDate: this.startDate,
                endDate: this.endDate
            });
            this.rawRows = Array.isArray(data) ? data : [];
            this.allRows = this.rawRows.map((row) => this.toViewModel(row));
            this.applySort();
            this.hasLoadedOnce = true;
        } catch (err) {
            this.errorMessage = this.extractError(err);
            this.rawRows = [];
            this.allRows = [];
        } finally {
            this.isLoading = false;
        }
    }

    toViewModel(row) {
        const breadthPct = this.toPercent(row.breadthRate);
        const depth = Number(row.depthMedian || 0);
        return {
            ...row,
            breadthDisplay: breadthPct === null ? '—' : `${breadthPct.toFixed(1)}%`,
            depthDisplay: depth.toLocaleString(undefined, { maximumFractionDigits: 1 })
        };
    }

    toPercent(value) {
        if (value === null || value === undefined) return null;
        const n = Number(value);
        if (Number.isNaN(n)) return null;
        return Math.abs(n) <= 1 ? n * 100 : n;
    }

    handleSort(event) {
        const def = this.columns.find((c) => c.fieldName === event.detail.fieldName);
        this.sortedBy = (def && def.sortBy) || event.detail.fieldName;
        this.sortedDirection = event.detail.sortDirection;
        this.applySort();
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
            if (typeof av === 'string') return av.localeCompare(bv) * direction;
            return (av < bv ? -1 : 1) * direction;
        });
    }

    handleRowAction(event) {
        const actionName = event.detail.action && event.detail.action.name;
        const row = event.detail.row || {};
        if (actionName !== 'drillToFeature') return;
        const panel = this.template.querySelector('c-ai-insights-drill-panel');
        if (panel && typeof panel.open === 'function') {
            panel.open('Feature', row.featureName, row.featureName, this.startDate, this.endDate);
        }
    }

    get hasData() {
        return Array.isArray(this.allRows) && this.allRows.length > 0;
    }

    get isFallbackDenominator() {
        return !!(this.allRows.length > 0 && this.allRows[0].entitledFallback === true);
    }

    get fallbackTip() {
        return 'Breadth % uses total active org users because no AI permission set is configured.';
    }

    get showError() {
        return !!this.errorMessage;
    }

    get showEmptyState() {
        return this.hasLoadedOnce && !this.isLoading && !this.errorMessage && !this.hasData;
    }

    get showTable() {
        return !this.showEmptyState && !this.showError;
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
