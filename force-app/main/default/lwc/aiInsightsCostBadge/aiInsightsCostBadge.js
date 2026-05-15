import { LightningElement, api } from 'lwc';
import { TOOLTIPS } from 'c/aiInsightsTooltips';

const LABELS = {
    ACTUAL: 'Actual — Salesforce Wallet',
    HIGH: 'High confidence',
    ESTIMATED: 'Estimated',
    FALLBACK: 'Fallback rate',
    NOT_COSTED: 'Not costed'
};

const VARIANTS = {
    ACTUAL: 'slds-theme_success fm-cost-badge_actual',
    HIGH: 'slds-theme_success',
    ESTIMATED: 'slds-theme_warning',
    FALLBACK: 'slds-theme_warning',
    NOT_COSTED: 'slds-theme_error'
};

export default class AiInsightsCostBadge extends LightningElement {
    @api confidence;
    @api compact = false;

    get normalized() {
        const v = (this.confidence || '').toUpperCase();
        return LABELS[v] ? v : 'HIGH';
    }

    get label() {
        return LABELS[this.normalized];
    }

    get tooltip() {
        return TOOLTIPS.costConfidence?.[this.normalized] || this.label;
    }

    get badgeClass() {
        const base = 'slds-badge';
        const variant = VARIANTS[this.normalized] || '';
        const size = this.compact ? 'fm-cost-badge_compact' : '';
        return `${base} ${variant} ${size}`.trim();
    }

    get isNotCosted() {
        return this.normalized === 'NOT_COSTED';
    }
}
