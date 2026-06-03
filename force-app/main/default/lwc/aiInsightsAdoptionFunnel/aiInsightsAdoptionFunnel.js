import { LightningElement, wire } from 'lwc';
import { subscribe, unsubscribe, MessageContext } from 'lightning/messageService';
import AI_INSIGHTS_DATE_RANGE from '@salesforce/messageChannel/AiInsightsDateRange__c';
import getEntitlementSnapshot from '@salesforce/apex/AiInsightsController.getEntitlementSnapshot';
import { TOOLTIPS } from 'c/aiInsightsTooltips';
import FM_Adoption_Fallback_Tip from '@salesforce/label/c.FM_Adoption_Fallback_Tip';

/**
 * Three-stage adoption funnel: Total Active Users → Entitled → Active in
 * window. Each stage is a horizontal bar whose width is proportional to the
 * widest stage. Hover help-text explains the denominator math, and an admin
 * tip surfaces when no AI permission set is configured (entitledFallback).
 *
 * Subscribes to AiInsightsDateRange only — the funnel is intrinsically
 * org-wide, dimension filters would distort the entitled denominator.
 */
export default class AiInsightsAdoptionFunnel extends LightningElement {
    @wire(MessageContext)
    messageContext;

    subscription;
    startDate = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString();
    endDate = new Date().toISOString();

    snapshot;
    isLoading = false;
    hasLoadedOnce = false;
    errorMessage;

    // Funnel section heading + entitled-denominator caption read from the
    // adoption namespace. Stage-level tooltips are stitched into each
    // stage object below so the template can bind {stage.tooltip}.
    tooltips = TOOLTIPS.adoption;
    fallbackTip = FM_Adoption_Fallback_Tip;

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
            this.snapshot = await getEntitlementSnapshot({
                startDate: this.startDate,
                endDate: this.endDate
            });
            this.hasLoadedOnce = true;
        } catch (err) {
            this.errorMessage = this.extractError(err);
            this.snapshot = undefined;
        } finally {
            this.isLoading = false;
        }
    }

    // --- Stage view models -------------------------------------------------

    get stages() {
        if (!this.snapshot) return [];
        const total = Number(this.snapshot.totalActiveOrgUsers || 0);
        const entitled = Number(this.snapshot.entitledCount || 0);
        const active = Number(this.snapshot.activeCount || 0);
        // Widest stage anchors the bar widths so every other stage's width is
        // a percentage of it.
        const widest = Math.max(total, entitled, active, 1);

        const fallback = !!this.snapshot.entitledFallback;
        // When the entitled denominator falls back to total active org users,
        // the middle bar would be redundant — collapse to two stages and let
        // the admin tip explain why.
        const stages = [];
        stages.push(
            this.makeStage('Active org users', total, widest, 'utility:user', null, TOOLTIPS.adoption.activeOrgUsers)
        );
        if (!fallback) {
            stages.push(
                this.makeStage(
                    'Entitled',
                    entitled,
                    widest,
                    'utility:identity',
                    'fm-funnel__bar_brand',
                    TOOLTIPS.adoption.entitled
                )
            );
        }
        stages.push(
            this.makeStage(
                'Active in window',
                active,
                widest,
                'utility:check',
                'fm-funnel__bar_success',
                TOOLTIPS.adoption.activeInWindow
            )
        );
        return stages;
    }

    makeStage(label, count, widest, icon, modifier, tooltip) {
        const widthPct = widest > 0 ? Math.max(2, Math.round((count / widest) * 100)) : 0;
        return {
            key: label,
            label,
            count,
            countDisplay: Number(count).toLocaleString(),
            barStyle: `width: ${widthPct}%`,
            icon,
            barClass: `fm-funnel__bar ${modifier || ''}`.trim(),
            tooltip: tooltip || ''
        };
    }

    get adoptionRatePct() {
        if (!this.snapshot) return null;
        const v = this.snapshot.adoptionRate;
        if (v === null || v === undefined) return null;
        const n = Number(v);
        if (Number.isNaN(n)) return null;
        return Math.abs(n) <= 1 ? n * 100 : n;
    }

    get adoptionRateDisplay() {
        const pct = this.adoptionRatePct;
        if (pct === null) return '—';
        return `${pct.toFixed(1)}%`;
    }

    get isFallback() {
        return !!(this.snapshot && this.snapshot.entitledFallback);
    }

    get configuredList() {
        const cfg = this.snapshot && this.snapshot.configuredPermissionSets;
        if (!Array.isArray(cfg) || cfg.length === 0) return '';
        return cfg.join(', ');
    }

    get hasConfiguredList() {
        return !!this.configuredList && !this.isFallback;
    }

    get showError() {
        return !!this.errorMessage;
    }

    get showEmptyState() {
        return this.hasLoadedOnce && !this.isLoading && !this.errorMessage && !this.snapshot;
    }

    get showFunnel() {
        return !this.showEmptyState && !this.showError && !!this.snapshot;
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
