import { LightningElement, wire } from 'lwc';
import { publish, subscribe, unsubscribe, MessageContext } from 'lightning/messageService';
import AI_INSIGHTS_FILTERS from '@salesforce/messageChannel/AiInsightsFilters__c';

/**
 * Horizontal summary of every active dashboard filter as removable pills.
 *
 * Displays above the main dashboard tabs so users can see at a glance what
 * is slicing the view and drop any filter with one click without opening
 * the rail. Clicking a pill's × publishes a reduced criteria back on the
 * same LMS channel — the filter rail is the source of truth and will
 * rehydrate its selections from the publish.
 *
 * Renders nothing when no non-date filter is active, so the header stays
 * compact until the user actually applies a filter.
 */
export default class AiInsightsFilterPills extends LightningElement {
    @wire(MessageContext)
    messageContext;

    criteria = {};
    presetLabel = 'Last 30 days';
    subscription;

    connectedCallback() {
        this.subscription = subscribe(this.messageContext, AI_INSIGHTS_FILTERS, (msg) =>
            this.handleCriteria(msg)
        );
    }

    disconnectedCallback() {
        if (this.subscription) {
            unsubscribe(this.subscription);
            this.subscription = undefined;
        }
    }

    handleCriteria(msg) {
        if (!msg) return;
        if (msg.presetLabel) this.presetLabel = msg.presetLabel;
        if (!msg.criteriaJson) return;
        try {
            this.criteria = JSON.parse(msg.criteriaJson) || {};
        } catch (err) {
            this.criteria = {};
        }
    }

    get pills() {
        const c = this.criteria || {};
        const out = [];
        this.addDim(out, 'models', 'Model');
        this.addDim(out, 'providers', 'Provider');
        this.addDim(out, 'features', 'Feature');
        this.addDim(out, 'appTypes', 'App type');
        this.addDim(out, 'promptTemplateDevNames', 'Prompt');
        this.addDim(out, 'userIds', 'User');
        return out;
    }

    addDim(out, key, prettyKey) {
        const vals = (this.criteria && this.criteria[key]) || [];
        vals.forEach((v) => {
            out.push({
                pillKey: `${key}:${v}`,
                dim: key,
                value: v,
                label: `${prettyKey}: ${v}`
            });
        });
    }

    get hasPills() {
        return this.pills.length > 0;
    }

    handleRemove(event) {
        const { dim, value } = event.target.dataset;
        if (!dim) return;
        const next = { ...this.criteria };
        const current = Array.isArray(next[dim]) ? next[dim] : [];
        next[dim] = current.filter((v) => v !== value);
        this.criteria = next;
        publish(this.messageContext, AI_INSIGHTS_FILTERS, {
            criteriaJson: JSON.stringify(next),
            startDate: next.startDate,
            endDate: next.endDate,
            presetLabel: this.presetLabel
        });
    }
}
