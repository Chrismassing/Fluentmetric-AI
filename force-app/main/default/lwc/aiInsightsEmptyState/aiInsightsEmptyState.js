import { LightningElement, api } from 'lwc';

/**
 * Reusable empty-state panel used across FluentMetric AI components.
 *
 * Props:
 *   title          string   Header text (required)
 *   message        string   Body copy under the title
 *   iconName       string   SLDS icon name (e.g. "utility:info", "standard:dashboard")
 *   showSetupLink  boolean  When true, render a "View setup instructions" link
 *   setupLabel     string   Optional label override for the setup link
 */
export default class AiInsightsEmptyState extends LightningElement {
    @api title = 'No data';
    @api message = '';
    @api iconName = 'utility:info';
    @api showSetupLink = false;
    @api setupLabel = 'View setup instructions';
    // Optional quick-action button — when label is set, a brand button renders
    // and clicking it fires `primaryaction`. Used by dashboards to offer "widen
    // the date range" or "open Explorer" shortcuts from an empty state, so users
    // recover without hunting for the date filter.
    @api primaryActionLabel;
    @api secondaryActionLabel;

    get iconVariant() {
        // Only large standard: icons render a colored square; utility icons stay neutral.
        return this.iconName && this.iconName.startsWith('utility:') ? 'default' : 'default';
    }

    get hasPrimaryAction() {
        return !!this.primaryActionLabel;
    }

    get hasSecondaryAction() {
        return !!this.secondaryActionLabel;
    }

    get hasAnyAction() {
        return this.hasPrimaryAction || this.hasSecondaryAction;
    }

    handleSetupClick(event) {
        event.preventDefault();
        this.dispatchEvent(new CustomEvent('setupclick', { bubbles: true, composed: true }));
    }

    handlePrimaryAction() {
        this.dispatchEvent(new CustomEvent('primaryaction', { bubbles: true, composed: true }));
    }

    handleSecondaryAction() {
        this.dispatchEvent(new CustomEvent('secondaryaction', { bubbles: true, composed: true }));
    }
}
