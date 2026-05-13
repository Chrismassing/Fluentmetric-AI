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
 *   variant        string   "default" (illustration + copy) | "skeleton"
 *                           (animated shimmer rows used during initial loads).
 *   skeletonRows   number   Number of placeholder rows to draw in skeleton
 *                           variant. Defaults to 4.
 */
export default class AiInsightsEmptyState extends LightningElement {
    @api title = 'No data';
    @api message = '';
    @api iconName = 'utility:info';
    @api showSetupLink = false;
    @api setupLabel = 'View setup instructions';
    @api variant = 'default';
    @api skeletonRows = 4;
    // Optional quick-action button — when label is set, a brand button renders
    // and clicking it fires `primaryaction`. Used by dashboards to offer "widen
    // the date range" or "open Explorer" shortcuts from an empty state, so users
    // recover without hunting for the date filter.
    @api primaryActionLabel;
    @api secondaryActionLabel;

    get isSkeleton() {
        return this.variant === 'skeleton';
    }
    get isDefault() {
        return !this.isSkeleton;
    }
    // Pre-built array so the template can iterate without arithmetic helpers.
    get skeletonItems() {
        const n = Math.max(1, Math.min(20, Number(this.skeletonRows) || 4));
        const out = [];
        for (let i = 0; i < n; i++) out.push({ key: `s-${i}` });
        return out;
    }

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
