import { LightningElement, api, track, wire } from 'lwc';
import getKpiSummary from '@salesforce/apex/FmTableauNextController.getKpiSummary';
import EMPTY_LABEL from '@salesforce/label/c.FM_TBL_Kpi_Empty';

export default class FmTableauKpiTile extends LightningElement {
    @api title = 'GenAI Snapshot';
    @api windowDays = 30;

    @track startDate;
    @track endDate;

    summary;
    error;

    connectedCallback() {
        // Compute once at mount so the @wire cache key is stable. Recomputing
        // Date.now() inside a getter on every render would invalidate the
        // cache and re-fire the Apex call.
        const days = Number(this.windowDays) || 30;
        const end = new Date();
        const start = new Date(end);
        start.setDate(start.getDate() - days);
        this.startDate = start.toISOString();
        this.endDate = end.toISOString();
    }

    @wire(getKpiSummary, { startDate: '$startDate', endDate: '$endDate' })
    handleSummary({ data, error }) {
        if (data) {
            this.summary = data;
            this.error = undefined;
        } else if (error) {
            this.summary = undefined;
            this.error = error.body && error.body.message ? error.body.message : null;
        }
    }

    get isLoading() {
        return !this.summary && !this.error;
    }

    get hasData() {
        return !!this.summary && !this.error;
    }

    get hasError() {
        return !!this.error;
    }

    get isEmpty() {
        return !this.isLoading && !this.hasData && !this.hasError;
    }

    get errorMessage() {
        return this.error;
    }

    get emptyMessage() {
        return EMPTY_LABEL;
    }

    get formattedRequests() {
        return this.summary ? this.summary.totalRequests.toLocaleString() : '';
    }

    get formattedUsers() {
        return this.summary ? this.summary.uniqueUsers.toLocaleString() : '';
    }

    get formattedAcceptance() {
        if (!this.summary || this.summary.acceptanceRate == null) return '—';
        return Math.round(this.summary.acceptanceRate * 100) + '%';
    }

    get formattedTokens() {
        if (!this.summary) return '';
        const total = (this.summary.totalInputTokens || 0) + (this.summary.totalOutputTokens || 0);
        return total.toLocaleString();
    }

    get rangeLabel() {
        return this.summary ? this.summary.dateRangeLabel : '';
    }
}
