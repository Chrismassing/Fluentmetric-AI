import { LightningElement, api, track, wire } from 'lwc';
import { publish, MessageContext } from 'lightning/messageService';
import AI_INSIGHTS_DATE_RANGE from '@salesforce/messageChannel/AiInsightsDateRange__c';
import { TOOLTIPS } from 'c/aiInsightsTooltips';
import FM_App_Title from '@salesforce/label/c.FM_App_Title';
import FM_App_Subtitle from '@salesforce/label/c.FM_App_Subtitle';

/**
 * Top-level shell for the FluentMetric AI dashboard.
 *
 * Layout:
 *   - Header + Date Filter are pinned above the tabset so the selected range
 *     applies to every tab via the AiInsightsDateRange LMS channel.
 *   - `lightning-tabset variant="standard"` wraps the dashboards. All tabs
 *     stay mounted (no lazy loading) so each child's LMS subscribe runs
 *     during its own connectedCallback — this matters because the date-filter
 *     publish can race an unmounted child and leave it with null dates.
 *
 * On connectedCallback this container also publishes a default date range
 * (configurable via App Builder, default 30 days) so subscribers have
 * something to render before the user touches the date filter.
 */
export default class AiInsightsApp extends LightningElement {
    /** Configurable default date range in days. */
    @api defaultPresetDays = 30;

    @wire(MessageContext)
    messageContext;

    // Current rail expanded state — drives the two-column grid class getters
    // inside the Explorer tab. Starts expanded (Explorer is the only tab
    // that hosts the rail).
    @track railExpanded = true;

    // Tab titles / helper copy pulled from the centralized TOOLTIPS module so
    // every tooltip string lives in one place and stays consistent.
    tooltips = TOOLTIPS.app;

    labels = {
        appTitle: FM_App_Title,
        appSubtitle: FM_App_Subtitle
    };

    connectedCallback() {
        this.publishDefaultRange();
    }

    publishDefaultRange() {
        const days = Number(this.defaultPresetDays) || 30;
        const endDate = new Date();
        const startDate = new Date();
        startDate.setDate(startDate.getDate() - days);
        const presetLabel = `Last ${days} days`;

        publish(this.messageContext, AI_INSIGHTS_DATE_RANGE, {
            startDate: startDate.toISOString(),
            endDate: endDate.toISOString(),
            presetLabel
        });
    }

    handleRailToggle(event) {
        this.railExpanded = !!(event.detail && event.detail.expanded);
    }

    get railColumnClass() {
        if (this.railExpanded) {
            return 'slds-col slds-size_1-of-1 slds-medium-size_4-of-12 slds-large-size_3-of-12 fm-app-rail';
        }
        return 'slds-col slds-size_1-of-1 slds-medium-size_1-of-12 slds-large-size_1-of-12 fm-app-rail fm-app-rail_collapsed';
    }

    get mainColumnClass() {
        if (this.railExpanded) {
            return 'slds-col slds-size_1-of-1 slds-medium-size_8-of-12 slds-large-size_9-of-12';
        }
        return 'slds-col slds-size_1-of-1 slds-medium-size_11-of-12 slds-large-size_11-of-12';
    }

}
