import { LightningElement, wire } from 'lwc';
import { subscribe, unsubscribe, MessageContext } from 'lightning/messageService';
import AI_INSIGHTS_DATE_RANGE from '@salesforce/messageChannel/AiInsightsDateRange__c';
import { TOOLTIPS } from 'c/aiInsightsTooltips';
import FM_Cost_Tab_Heading from '@salesforce/label/c.FM_Cost_Tab_Heading';
import FM_Cost_Tab_Subhead from '@salesforce/label/c.FM_Cost_Tab_Subhead';

/**
 * Cost tab wrapper. Hosts the existing aiInsightsCostAnalysis component
 * inside a tab-level frame (heading + subhead + active-range badge).
 *
 * The cost-analysis child manages its own data fetching, gating
 * (Enable_Cost_Metrics__c), and Wallet/Estimate confidence badges. This
 * wrapper only forwards the active preset label so users see which range
 * is in effect on the tab.
 */
export default class AiInsightsCost extends LightningElement {
    @wire(MessageContext)
    messageContext;

    subscription;
    presetLabel;

    tooltips = TOOLTIPS.cost;

    labels = {
        tabHeading: FM_Cost_Tab_Heading,
        tabSubhead: FM_Cost_Tab_Subhead
    };

    connectedCallback() {
        this.subscription = subscribe(
            this.messageContext,
            AI_INSIGHTS_DATE_RANGE,
            (message) => {
                if (message && message.presetLabel) {
                    this.presetLabel = message.presetLabel;
                }
            }
        );
    }

    disconnectedCallback() {
        if (this.subscription) {
            unsubscribe(this.subscription);
            this.subscription = undefined;
        }
    }
}
