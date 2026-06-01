import { LightningElement, wire } from 'lwc';
import { subscribe, unsubscribe, MessageContext } from 'lightning/messageService';
import AI_INSIGHTS_DATE_RANGE from '@salesforce/messageChannel/AiInsightsDateRange__c';
import AI_INSIGHTS_FILTERS from '@salesforce/messageChannel/AiInsightsFilters__c';
import getOverview from '@salesforce/apex/AiInsightsController.getOverview';
import getCostSettings from '@salesforce/apex/AiInsightsController.getCostSettings';
import FM_Cost_Upload_Rate_Card_Button from '@salesforce/label/c.FM_Cost_Upload_Rate_Card_Button';

/**
 * Cost Analysis (Estimated) panel.
 *
 * This is the single surface where $ / Flex Credit figures appear. Default
 * dashboards elsewhere show tokens only. This component honors two gates:
 *
 *   1. `Enable_Cost_Metrics__c` (hierarchy custom setting). When off, the
 *      panel renders an explanatory empty state instead of cost numbers —
 *      it does NOT silently show $0, because that would imply a real
 *      measurement rather than an opt-out.
 *   2. A persistent (per-user, via localStorage) "estimates disclosure"
 *      banner at the top of the panel. Never auto-hidden so the caveat
 *      stays visible across sessions; the dismiss button only collapses
 *      it, it doesn't permanently hide it.
 *
 * Numbers come from `getOverview` (the same endpoint Overview previously
 * read for cost). Confidence badges from `CostCalculatorService` flow
 * through unchanged. Filter-rail dimension filters are acknowledged for
 * the date range only today — `getOverview` doesn't yet accept a full
 * criteria payload (v1 scope).
 */
const BANNER_DISMISSED_KEY = 'fluentmetric_cost_banner_dismissed_v1';

export default class AiInsightsCostAnalysis extends LightningElement {
    @wire(MessageContext)
    messageContext;

    dateSubscription;
    filtersSubscription;

    startDate = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString();
    endDate = new Date().toISOString();
    presetLabel;

    overview;
    isLoading = false;
    hasLoadedOnce = false;
    errorMessage;
    costMetricsEnabled = false;
    costEnabledKnown = false;
    bannerDismissed = false;
    rateCardModalOpen = false;

    labels = {
        uploadRateCard: FM_Cost_Upload_Rate_Card_Button
    };

    connectedCallback() {
        this.bannerDismissed = this.readBannerState();
        this.dateSubscription = subscribe(this.messageContext, AI_INSIGHTS_DATE_RANGE, (msg) =>
            this.handleDateRange(msg)
        );
        this.filtersSubscription = subscribe(this.messageContext, AI_INSIGHTS_FILTERS, (msg) =>
            this.handleFilters(msg)
        );
        this.loadCostEnabled();
    }

    disconnectedCallback() {
        if (this.dateSubscription) unsubscribe(this.dateSubscription);
        if (this.filtersSubscription) unsubscribe(this.filtersSubscription);
        this.dateSubscription = undefined;
        this.filtersSubscription = undefined;
    }

    async loadCostEnabled() {
        try {
            const s = await getCostSettings();
            this.costMetricsEnabled = !!(s && s.enabled === true);
        } catch (err) {
            this.costMetricsEnabled = false;
        } finally {
            this.costEnabledKnown = true;
            if (this.costMetricsEnabled) {
                this.loadOverview();
            }
        }
    }

    handleDateRange(msg) {
        if (!msg || !msg.startDate || !msg.endDate) return;
        this.startDate = msg.startDate;
        this.endDate = msg.endDate;
        this.presetLabel = msg.presetLabel;
        if (this.costMetricsEnabled) this.loadOverview();
    }

    handleFilters(msg) {
        if (!msg) return;
        if (msg.startDate) this.startDate = msg.startDate;
        if (msg.endDate) this.endDate = msg.endDate;
        if (msg.presetLabel) this.presetLabel = msg.presetLabel;
        if (this.costMetricsEnabled) this.loadOverview();
    }

    async loadOverview() {
        this.isLoading = true;
        this.errorMessage = undefined;
        try {
            this.overview = await getOverview({
                startDate: this.startDate,
                endDate: this.endDate
            });
            this.hasLoadedOnce = true;
        } catch (err) {
            this.errorMessage = this.extractError(err);
            this.overview = undefined;
        } finally {
            this.isLoading = false;
        }
    }

    // ───────────── Banner state ─────────────

    handleDismissBanner() {
        this.bannerDismissed = true;
        try {
            localStorage.setItem(BANNER_DISMISSED_KEY, '1');
        } catch (err) {
            // localStorage can throw in some private-browsing contexts — the
            // banner just won't stay dismissed across sessions in that case.
        }
    }

    readBannerState() {
        try {
            return localStorage.getItem(BANNER_DISMISSED_KEY) === '1';
        } catch (err) {
            return false;
        }
    }

    // ───────────── Display getters ─────────────

    get showDisabledState() {
        return this.costEnabledKnown && !this.costMetricsEnabled;
    }

    get showLoading() {
        return this.costMetricsEnabled && this.isLoading && !this.hasLoadedOnce;
    }

    get showError() {
        return this.costMetricsEnabled && !!this.errorMessage;
    }

    get showCards() {
        return this.costMetricsEnabled && this.hasLoadedOnce && !this.errorMessage;
    }

    get showBanner() {
        return this.costMetricsEnabled && !this.bannerDismissed;
    }

    get estimatedUsdDisplay() {
        if (!this.overview) return '—';
        const v = Number(this.overview.estimatedUsdAfterDiscount || 0);
        return `$${v.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
    }

    get estimatedUsdBaseDisplay() {
        if (!this.overview) return '—';
        const v = Number(this.overview.estimatedBaseUsd || 0);
        return `$${v.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
    }

    get estimatedFlexCreditsDisplay() {
        if (!this.overview) return '—';
        const v = Number(this.overview.estimatedFlexCredits || 0);
        return v.toLocaleString();
    }

    get costConfidence() {
        return (this.overview && this.overview.costConfidence) || 'HIGH';
    }

    get costSource() {
        return (this.overview && this.overview.costSource) || 'ESTIMATED_TIER';
    }

    get isWalletActual() {
        return this.costSource === 'ACTUAL_WALLET';
    }

    /**
     * The rate-card upload CTA only makes sense when figures are
     * estimates — Wallet-actuals are sourced from billing, so refreshing
     * the public rate card wouldn't change the headline.
     */
    get canUploadRateCard() {
        return this.costMetricsEnabled && !this.isWalletActual;
    }

    handleOpenRateCardUpload() {
        this.rateCardModalOpen = true;
    }

    handleRateCardModalClose() {
        this.rateCardModalOpen = false;
    }

    handleRateCardApplied() {
        // Multipliers changed — re-fetch overview so tiles reflect them.
        this.loadOverview();
    }

    /**
     * Toggles the legacy "Estimates only" disclosure banner. When Wallet is
     * authoritative, the disclosure no longer applies — the figure is the
     * billed actual — so we hide that banner and show the Wallet callout
     * instead.
     */
    get showEstimateBanner() {
        return this.showBanner && !this.isWalletActual;
    }

    get showWalletCallout() {
        return this.costMetricsEnabled && this.hasLoadedOnce && this.isWalletActual;
    }

    get agentforceUsdDisplay() {
        if (!this.overview) return '—';
        const v = Number(this.overview.agentforceUsd || 0);
        return `$${v.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
    }

    get agentforceActionCountDisplay() {
        if (!this.overview) return '—';
        const v = Number(this.overview.agentforceActionCount || 0);
        return v.toLocaleString();
    }

    get hasAgentforceActions() {
        return !!(this.overview && (this.overview.agentforceActionCount || 0) > 0);
    }

    get dateRangeLabel() {
        return (this.overview && this.overview.dateRangeLabel) || this.presetLabel || '';
    }

    extractError(err) {
        if (!err) return 'Unknown error';
        if (typeof err === 'string') return err;
        if (err.body && err.body.message) return err.body.message;
        if (Array.isArray(err.body) && err.body.length) return err.body.map((e) => e.message).join(', ');
        return err.message || 'Unknown error';
    }
}
