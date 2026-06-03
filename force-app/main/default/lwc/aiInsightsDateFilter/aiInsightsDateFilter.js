import { LightningElement, wire } from 'lwc';
import { publish, MessageContext } from 'lightning/messageService';
import AI_INSIGHTS_DATE_RANGE from '@salesforce/messageChannel/AiInsightsDateRange__c';
import FM_Date_Pill_Open from '@salesforce/label/c.FM_Date_Pill_Open';

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
 * Compact date-range pill. The default state is a single button showing the
 * active preset + resolved date window (e.g. "Last 30 days · May 1 – May 31").
 * Clicking the pill opens an SLDS popover with the preset combobox + (when
 * Custom is selected) two date inputs.
 *
 * Publishing semantics on the AiInsightsDateRange channel are unchanged from
 * the previous flat layout — { startDate, endDate, presetLabel } fires on any
 * preset change or custom-range commit.
 */
export default class AiInsightsDateFilter extends LightningElement {
    preset = PRESET_LAST_30;
    customStart;
    customEnd;
    errorMessage;
    popoverOpen = false;

    // Currently-effective window (drives the pill label). Seeded with the
    // default 30-day preset so the pill is meaningful before any LMS publish.
    activeStartDate;
    activeEndDate;

    @wire(MessageContext)
    messageContext;

    labels = {
        pillOpen: FM_Date_Pill_Open
    };

    connectedCallback() {
        // Seed the custom inputs and the pill label with the default 30-day
        // window so the pill renders meaningful resolved dates from first
        // paint, before any user interaction.
        const { startDate, endDate } = this.computeRange(PRESET_LAST_30);
        this.customStart = this.toDateInputValue(startDate);
        this.customEnd = this.toDateInputValue(endDate);
        this.activeStartDate = startDate;
        this.activeEndDate = endDate;
    }

    disconnectedCallback() {
        this.removeOutsideClickListener();
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

    get chevronIcon() {
        return this.popoverOpen ? 'utility:chevronup' : 'utility:chevrondown';
    }

    get chevronAltText() {
        return this.popoverOpen ? 'Close date range' : this.labels.pillOpen;
    }

    /** "{preset} · {May 1 – May 31}" — single-line, fits the toolbar pill. */
    get pillLabel() {
        const presetLabel = PRESET_LABELS[this.preset] || PRESET_LABELS[PRESET_LAST_30];
        const range = this.formatRangeLabel(this.activeStartDate, this.activeEndDate);
        return range ? `${presetLabel} · ${range}` : presetLabel;
    }

    formatRangeLabel(start, end) {
        if (!start || !end) return '';
        const fmt = (d) => d.toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
        return `${fmt(start)} – ${fmt(end)}`;
    }

    handleTogglePopover() {
        this.popoverOpen = !this.popoverOpen;
        if (this.popoverOpen) {
            this.addOutsideClickListener();
        } else {
            this.removeOutsideClickListener();
        }
    }

    handleClosePopover() {
        this.popoverOpen = false;
        this.removeOutsideClickListener();
    }

    /**
     * Stop clicks inside the popover from bubbling up to the document-level
     * outside-click handler. Under Lightning Web Security (closed shadow DOM),
     * a document listener can't see what was clicked — composedPath() stops
     * at the host and event.target is retargeted to <c-ai-insights-date-filter>.
     * Catching the click here, INSIDE the shadow, is the only reliable signal
     * that the click is "inside the popover".
     *
     * Clicks on Lightning datepicker / combobox overlays portaled to
     * document.body are handled separately — see addOutsideClickListener.
     */
    handlePopoverClick(event) {
        event.stopPropagation();
    }

    addOutsideClickListener() {
        if (this._outsideHandler) return;
        this._outsideHandler = (event) => {
            // Clicks inside the popover never reach this handler — they're
            // stopped by handlePopoverClick. Anything we DO see here came from
            // outside our shadow root. The remaining job: don't close when the
            // user clicks a Lightning datepicker / combobox dropdown that was
            // portaled to document.body (light-DOM, so we can inspect it).
            const t = event.target;
            if (t && t.closest && (
                t.closest('.slds-datepicker') ||
                t.closest('.slds-dropdown') ||
                t.closest('.slds-listbox') ||
                t.closest('lightning-datepicker') ||
                t.closest('lightning-calendar') ||
                t.closest('lightning-base-combobox')
            )) return;
            this.popoverOpen = false;
            this.removeOutsideClickListener();
        };
        // Defer attach so the click that opened the popover doesn't immediately close it.
        setTimeout(() => document.addEventListener('click', this._outsideHandler), 0);
    }

    removeOutsideClickListener() {
        if (this._outsideHandler) {
            document.removeEventListener('click', this._outsideHandler);
            this._outsideHandler = undefined;
        }
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
        this.activeStartDate = startDate;
        this.activeEndDate = endDate;
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
