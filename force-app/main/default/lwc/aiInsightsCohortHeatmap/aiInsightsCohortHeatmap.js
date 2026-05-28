import { LightningElement, wire } from 'lwc';
import { subscribe, unsubscribe, MessageContext } from 'lightning/messageService';
import AI_INSIGHTS_DATE_RANGE from '@salesforce/messageChannel/AiInsightsDateRange__c';
import getAdoptionCohorts from '@salesforce/apex/AiInsightsController.getAdoptionCohorts';
import { TOOLTIPS } from 'c/aiInsightsTooltips';

/**
 * Cohort retention heatmap. Each row is one ISO-week cohort (users whose first
 * observed request landed in that week); columns are age-in-weeks (0..N);
 * cell color encodes retention percent. Pure CSS-grid + inline color — no
 * chart library.
 *
 * Subscribes to AiInsightsDateRange only. Cohorts are intrinsically org-wide
 * and dimension filters would distort them, so the AiInsightsFilters channel
 * is intentionally not consumed here.
 */
export default class AiInsightsCohortHeatmap extends LightningElement {
    @wire(MessageContext)
    messageContext;

    subscription;
    startDate = new Date(Date.now() - 90 * 24 * 60 * 60 * 1000).toISOString();
    endDate = new Date().toISOString();

    payload;
    isLoading = false;
    hasLoadedOnce = false;
    errorMessage;

    tooltips = TOOLTIPS.overview;

    connectedCallback() {
        this.subscription = subscribe(
            this.messageContext,
            AI_INSIGHTS_DATE_RANGE,
            (message) => this.handleDateRange(message)
        );
        this.loadCohorts();
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
        this.loadCohorts();
    }

    async loadCohorts() {
        this.isLoading = true;
        this.errorMessage = undefined;
        try {
            const data = await getAdoptionCohorts({
                startDate: this.startDate,
                endDate: this.endDate
            });
            this.payload = data;
            this.hasLoadedOnce = true;
        } catch (err) {
            this.errorMessage = this.extractError(err);
            this.payload = undefined;
        } finally {
            this.isLoading = false;
        }
    }

    // --- Derived view models -------------------------------------------------

    get cohortRows() {
        const rows = this.payload && this.payload.cohorts;
        if (!Array.isArray(rows) || rows.length === 0) return [];
        // Cohorts arrive newest-first by default; render oldest at the top so
        // age progresses left → right and time progresses top → bottom.
        return [...rows]
            .sort((a, b) => {
                const ax = a.weekIsoLabel || '';
                const bx = b.weekIsoLabel || '';
                return ax < bx ? -1 : ax > bx ? 1 : 0;
            })
            .map((row) => this.toViewRow(row));
    }

    toViewRow(row) {
        const series = Array.isArray(row.retentionByWeek) ? row.retentionByWeek : [];
        const cohortSize = row.cohortSize || 0;
        const cells = series.map((value, index) => {
            const pct = this.toPercent(value);
            return {
                key: `${row.weekIsoLabel}-${index}`,
                ageWeek: index,
                pct,
                display: pct === null ? '—' : `${Math.round(pct)}%`,
                style: this.cellStyle(pct)
            };
        });
        return {
            key: row.weekIsoLabel,
            label: row.weekIsoLabel || '—',
            cohortSize,
            cohortSizeDisplay: cohortSize.toLocaleString(),
            cells
        };
    }

    toPercent(value) {
        if (value === null || value === undefined) return null;
        const n = Number(value);
        if (Number.isNaN(n)) return null;
        return Math.abs(n) <= 1 ? n * 100 : n;
    }

    // Map retention% → background color. Light gray for zero, deepening blue
    // for higher retention. Color is informational only — the cell's text
    // value carries the data, so the heatmap remains readable in monochrome.
    cellStyle(pct) {
        if (pct === null) return 'background: var(--slds-g-color-neutral-base-95, #f3f3f3); color: var(--slds-g-color-neutral-base-30, #444);';
        // Quantize to a small palette so visually similar values look identical.
        const clamped = Math.max(0, Math.min(100, pct));
        const alpha = (clamped / 100).toFixed(2);
        const fg = clamped >= 60 ? '#fff' : 'var(--slds-g-color-neutral-base-10, #181818)';
        return `background: rgba(1, 118, 211, ${alpha}); color: ${fg};`;
    }

    // --- State getters -------------------------------------------------------

    get hasData() {
        return Array.isArray(this.payload && this.payload.cohorts) && this.payload.cohorts.length > 0;
    }

    get showError() {
        return !!this.errorMessage;
    }

    get showEmptyState() {
        return this.hasLoadedOnce && !this.isLoading && !this.errorMessage && !this.hasData;
    }

    get showHeatmap() {
        return !this.showEmptyState && !this.showError && this.hasData;
    }

    get isTruncated() {
        return !!(this.payload && this.payload.truncated === true);
    }

    get truncationMessage() {
        return 'Cohort data was truncated to 50k rows. Narrow the date range for a complete picture.';
    }

    // The heatmap header renders age-week column labels (W0, W1, W2…). We
    // pick the longest cohort series so every cell column has a header.
    get ageHeaders() {
        const rows = this.cohortRows;
        if (rows.length === 0) return [];
        const widest = rows.reduce((max, r) => Math.max(max, r.cells.length), 0);
        return Array.from({ length: widest }, (_, i) => ({
            key: `hdr-${i}`,
            label: `W${i}`
        }));
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
