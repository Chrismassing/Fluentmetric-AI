import { LightningElement, wire, track } from 'lwc';
import { subscribe, unsubscribe, MessageContext } from 'lightning/messageService';
import AI_INSIGHTS_DATE_RANGE from '@salesforce/messageChannel/AiInsightsDateRange__c';
import getCostSettings from '@salesforce/apex/AiInsightsController.getCostSettings';
import getOverview from '@salesforce/apex/AiInsightsController.getOverview';
import FM_Cost_Disabled_Lead from '@salesforce/label/c.FM_Cost_Disabled_Lead';
import FM_Cost_Enable_Button from '@salesforce/label/c.FM_Cost_Enable_Button';
import FM_Cost_Enable_Helper from '@salesforce/label/c.FM_Cost_Enable_Helper';
import FM_Cost_Scope_Title from '@salesforce/label/c.FM_Cost_Scope_Title';
import FM_Cost_Rate_Card_Note from '@salesforce/label/c.FM_Cost_Rate_Card_Note';

/**
 * Cost Settings panel.
 *
 * Purpose: show the saved org-level custom setting values (USD per Flex
 * Credit, Discount %, Fallback Model) and offer live-preview sliders that
 * let the user see what different rates / discounts WOULD produce for the
 * current date range, without persisting anything. Saving still happens in
 * standard Salesforce Setup — this component just opens that page.
 *
 * The preview math is local: we read the current range's Flex Credits once
 * via getOverview and multiply by whatever the sliders currently show.
 */
export default class AiInsightsCostSettings extends LightningElement {
    @wire(MessageContext)
    messageContext;

    subscription;

    // Seed default 30-day window so the panel renders a preview even before
    // the shared date filter has published.
    startDate = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString();
    endDate = new Date().toISOString();

    // Saved settings (from custom setting via Apex)
    @track savedUsdPerCredit;
    @track savedDiscountPercent;
    @track savedFallbackModel;
    @track costMetricsEnabled = false;
    @track savedLoaded = false;
    @track settingsError;

    // Preview slider state — seeded from saved values
    @track previewUsdPerCredit = 0.004;
    @track previewDiscountPercent = 0;

    labels = {
        disabledLead: FM_Cost_Disabled_Lead,
        enableButton: FM_Cost_Enable_Button,
        enableHelper: FM_Cost_Enable_Helper,
        scopeTitle: FM_Cost_Scope_Title,
        rateCardNote: FM_Cost_Rate_Card_Note
    };

    // Current range's Flex Credits (scalar) — drives the preview math
    @track rangeFlexCredits = 0;
    @track rangeLoading = false;

    // ──────────────────────────────────────────────────────────────────────
    // Lifecycle
    // ──────────────────────────────────────────────────────────────────────

    connectedCallback() {
        this.loadSavedSettings();
        this.loadRangeTotals();
        this.subscription = subscribe(
            this.messageContext,
            AI_INSIGHTS_DATE_RANGE,
            (message) => this.handleDateRange(message)
        );
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
        this.loadRangeTotals();
    }

    // ──────────────────────────────────────────────────────────────────────
    // Data load
    // ──────────────────────────────────────────────────────────────────────

    async loadSavedSettings() {
        try {
            const s = await getCostSettings();
            this.costMetricsEnabled = s && s.enabled === true;
            this.savedUsdPerCredit = Number(s.usdPerCredit || 0.004);
            this.savedDiscountPercent = Number(s.discountPercent || 0);
            this.savedFallbackModel = s.fallbackModel || 'Standard-Default';
            // Seed preview sliders from saved values so the default view is
            // "nothing changed yet".
            this.previewUsdPerCredit = this.savedUsdPerCredit;
            this.previewDiscountPercent = this.savedDiscountPercent;
            this.savedLoaded = true;
        } catch (err) {
            this.settingsError = this.extractError(err);
        }
    }

    async loadRangeTotals() {
        this.rangeLoading = true;
        try {
            const ov = await getOverview({
                startDate: this.startDate,
                endDate: this.endDate
            });
            this.rangeFlexCredits = Number((ov && ov.estimatedFlexCredits) || 0);
        } catch (err) {
            // Non-fatal — leave previous value in place. The sliders will
            // still work; preview just shows based on stale total.
        } finally {
            this.rangeLoading = false;
        }
    }

    // ──────────────────────────────────────────────────────────────────────
    // Slider handlers
    // ──────────────────────────────────────────────────────────────────────

    handleDiscountChange(event) {
        this.previewDiscountPercent = Number(event.target.value || 0);
    }

    handleUsdRateChange(event) {
        this.previewUsdPerCredit = Number(event.target.value || 0);
    }

    handleResetPreview() {
        this.previewDiscountPercent = this.savedDiscountPercent;
        this.previewUsdPerCredit = this.savedUsdPerCredit;
    }

    /**
     * Deep-link to the standard Setup → Custom Settings Manage page for
     * FluentMetric_Cost_Settings__c. We use window.open with `_blank` (plus
     * opener scrub) because LWC's NavigationMixin doesn't reliably reach
     * Setup URLs, and we've established this pattern for other deep links.
     */
    handleOpenSetup() {
        const url = '/lightning/setup/CustomSettings/home';
        try {
            const win = window.open(url, '_blank');
            if (win) {
                try {
                    win.opener = null;
                } catch (e) {
                    // cross-origin — ignore
                }
            }
        } catch (err) {
            // If popup blocked, navigate the current tab as a fallback —
            // better than a silent failure.
            window.location.href = url;
        }
    }

    // ──────────────────────────────────────────────────────────────────────
    // Computed getters — display helpers
    // ──────────────────────────────────────────────────────────────────────

    get savedUsdPerCreditDisplay() {
        return `$${Number(this.savedUsdPerCredit || 0).toFixed(4)}`;
    }

    get savedDiscountDisplay() {
        return `${Number(this.savedDiscountPercent || 0).toFixed(1)}%`;
    }

    get previewUsdPerCreditDisplay() {
        return `$${Number(this.previewUsdPerCredit || 0).toFixed(4)}`;
    }

    get previewDiscountDisplay() {
        return `${Number(this.previewDiscountPercent || 0).toFixed(1)}%`;
    }

    get rangeFlexCreditsDisplay() {
        return Number(this.rangeFlexCredits || 0).toLocaleString();
    }

    get savedCostDisplay() {
        const cost = this.rangeFlexCredits * this.savedUsdPerCredit * (1 - this.savedDiscountPercent / 100);
        return this.formatCurrency(cost);
    }

    get previewCostDisplay() {
        const cost = this.rangeFlexCredits * this.previewUsdPerCredit * (1 - this.previewDiscountPercent / 100);
        return this.formatCurrency(cost);
    }

    get deltaDisplay() {
        const savedCost = this.rangeFlexCredits * this.savedUsdPerCredit * (1 - this.savedDiscountPercent / 100);
        const previewCost = this.rangeFlexCredits * this.previewUsdPerCredit * (1 - this.previewDiscountPercent / 100);
        const delta = previewCost - savedCost;
        const sign = delta >= 0 ? '+' : '−';
        return `${sign}${this.formatCurrency(Math.abs(delta))}`;
    }

    get isInPreviewMode() {
        // Compare numerically with a small epsilon so float rounding doesn't
        // flash "preview mode" when the sliders haven't moved.
        const epsilon = 0.0001;
        return (
            Math.abs(this.previewUsdPerCredit - this.savedUsdPerCredit) > epsilon ||
            Math.abs(this.previewDiscountPercent - this.savedDiscountPercent) > epsilon
        );
    }

    get notInPreviewMode() {
        return !this.isInPreviewMode;
    }

    get showSettings() {
        return this.savedLoaded && !this.settingsError;
    }

    get showError() {
        return !!this.settingsError;
    }

    get showDisabledNotice() {
        return this.savedLoaded && !this.settingsError && !this.costMetricsEnabled;
    }

    get showEnabledSettings() {
        return this.savedLoaded && !this.settingsError && this.costMetricsEnabled;
    }

    formatCurrency(v) {
        const n = Number(v || 0);
        return `$${n.toLocaleString(undefined, {
            minimumFractionDigits: 2,
            maximumFractionDigits: 2
        })}`;
    }

    extractError(err) {
        if (!err) return 'Unknown error';
        if (err.body && err.body.message) return err.body.message;
        if (typeof err === 'string') return err;
        return err.message || 'Unknown error';
    }
}
