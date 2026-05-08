import { LightningElement, wire } from 'lwc';
import { publish, MessageContext } from 'lightning/messageService';
import AI_INSIGHTS_DATE_RANGE from '@salesforce/messageChannel/AiInsightsDateRange__c';

const PRESET_LAST_7 = 'LAST_7';
const PRESET_LAST_30 = 'LAST_30';
const PRESET_LAST_90 = 'LAST_90';
const PRESET_CUSTOM = 'CUSTOM';

const PRESET_LABELS = {
    [PRESET_LAST_7]: 'Last 7 days',
    [PRESET_LAST_30]: 'Last 30 days',
    [PRESET_LAST_90]: 'Last 90 days',
    [PRESET_CUSTOM]: 'Custom'
};

/**
 * Shared date-range picker. Publishes { startDate, endDate, presetLabel } to
 * the AiInsightsDateRange LMS channel on any change. Default: Last 30 days.
 */
export default class AiInsightsDateFilter extends LightningElement {
    preset = PRESET_LAST_30;
    customStart;
    customEnd;
    errorMessage;

    @wire(MessageContext)
    messageContext;

    connectedCallback() {
        // Seed the custom inputs with the default 30-day window so switching to
        // Custom doesn't start empty.
        const { startDate, endDate } = this.computeRange(PRESET_LAST_30);
        this.customStart = this.toDateInputValue(startDate);
        this.customEnd = this.toDateInputValue(endDate);
    }

    get presetOptions() {
        return [
            { label: PRESET_LABELS[PRESET_LAST_7], value: PRESET_LAST_7 },
            { label: PRESET_LABELS[PRESET_LAST_30], value: PRESET_LAST_30 },
            { label: PRESET_LABELS[PRESET_LAST_90], value: PRESET_LAST_90 },
            { label: PRESET_LABELS[PRESET_CUSTOM], value: PRESET_CUSTOM }
        ];
    }

    get isCustom() {
        return this.preset === PRESET_CUSTOM;
    }

    handlePresetChange(event) {
        this.preset = event.detail.value;
        this.errorMessage = undefined;
        if (this.preset !== PRESET_CUSTOM) {
            this.publishPresetRange();
        }
        // For Custom, we wait for the user to actually set two dates before publishing.
    }

    handleCustomStartChange(event) {
        this.customStart = event.detail.value;
        this.maybePublishCustom();
    }

    handleCustomEndChange(event) {
        this.customEnd = event.detail.value;
        this.maybePublishCustom();
    }

    maybePublishCustom() {
        if (!this.customStart || !this.customEnd) {
            return;
        }
        const start = new Date(this.customStart);
        const end = new Date(this.customEnd);
        if (Number.isNaN(start.getTime()) || Number.isNaN(end.getTime())) {
            this.errorMessage = 'Enter valid start and end dates.';
            return;
        }
        if (start > end) {
            this.errorMessage = 'Start date must be on or before end date.';
            return;
        }
        this.errorMessage = undefined;
        // Publish inclusive range: start at 00:00:00, end at 23:59:59.
        const startOfDay = new Date(start);
        startOfDay.setHours(0, 0, 0, 0);
        const endOfDay = new Date(end);
        endOfDay.setHours(23, 59, 59, 999);
        this.publishRange(startOfDay, endOfDay, PRESET_LABELS[PRESET_CUSTOM]);
    }

    publishPresetRange() {
        const { startDate, endDate } = this.computeRange(this.preset);
        this.publishRange(startDate, endDate, PRESET_LABELS[this.preset]);
    }

    publishRange(startDate, endDate, presetLabel) {
        publish(this.messageContext, AI_INSIGHTS_DATE_RANGE, {
            startDate: startDate.toISOString(),
            endDate: endDate.toISOString(),
            presetLabel
        });
    }

    computeRange(preset) {
        const end = new Date();
        const start = new Date();
        let days = 30;
        if (preset === PRESET_LAST_7) {
            days = 7;
        } else if (preset === PRESET_LAST_90) {
            days = 90;
        }
        start.setDate(start.getDate() - days);
        return { startDate: start, endDate: end };
    }

    toDateInputValue(date) {
        // yyyy-MM-dd formatting for lightning-input type=date.
        const pad = (n) => String(n).padStart(2, '0');
        return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
    }
}
