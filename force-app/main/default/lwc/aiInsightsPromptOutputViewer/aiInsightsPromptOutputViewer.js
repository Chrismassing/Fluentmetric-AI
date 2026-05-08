import { LightningElement, api, wire } from 'lwc';
import { subscribe, unsubscribe, MessageContext } from 'lightning/messageService';
import AI_INSIGHTS_DATE_RANGE from '@salesforce/messageChannel/AiInsightsDateRange__c';
import getPromptOutputs from '@salesforce/apex/AiInsightsController.getPromptOutputs';
import { abbreviateNumber } from './numberFormat';
import { TOOLTIPS } from 'c/aiInsightsTooltips';

const INITIAL_LIMIT = 20;
const PAGE_STEP = 20;
const COLLAPSED_CHARS = 200;
const TT = TOOLTIPS.promptOutputViewer;

/**
 * Output Inspector. Hidden until a prompt template is selected in
 * `aiInsightsPromptAnalytics` — the parent `aiInsightsApp` bridges the
 * `promptselected` event and passes the dev name down via @api.
 *
 * Imperatively calls `AiInsightsController.getPromptOutputs` whenever the
 * prompt selection or the LMS date range changes. Pagination is client-side:
 * the component tracks a growing `limitCount` and re-calls the controller
 * (the method is cacheable, so subsequent pages benefit from caching when
 * `(promptDevName, start, end, limit)` matches). This is simpler than server
 * offset paging and matches the spec's "Load More" behavior.
 *
 * Every field label renders with a `lightning-helptext` pulling from the
 * centralized TOOLTIPS constant.
 */
export default class AiInsightsPromptOutputViewer extends LightningElement {
    @wire(MessageContext)
    messageContext;

    subscription;
    // Seed a default 30-day window so a prompt click works immediately even
    // before the shared date-filter publish has landed — same defensive
    // pattern used by the other dashboards.
    startDate = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString();
    endDate = new Date().toISOString();

    _selectedPromptDevName;
    _selectedPromptLabel;

    rawRows = [];
    visibleRows = [];
    activeSections = [];

    currentLimit = INITIAL_LIMIT;
    totalFetched = 0;
    isLoading = false;
    hasLoadedOnce = false;
    errorMessage;

    tooltips = TT;

    // --- Public API --------------------------------------------------------

    @api
    get selectedPromptDevName() {
        return this._selectedPromptDevName;
    }
    set selectedPromptDevName(value) {
        if (value === this._selectedPromptDevName) {
            return;
        }
        this._selectedPromptDevName = value;
        this.resetPagination();
        this.loadOutputsIfReady();
    }

    /** Optional display label passed down alongside the dev name. */
    @api
    get selectedPromptLabel() {
        return this._selectedPromptLabel;
    }
    set selectedPromptLabel(value) {
        this._selectedPromptLabel = value;
    }

    // --- LMS subscription --------------------------------------------------

    connectedCallback() {
        this.subscription = subscribe(
            this.messageContext,
            AI_INSIGHTS_DATE_RANGE,
            (message) => this.handleDateRange(message)
        );
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
        this.resetPagination();
        this.loadOutputsIfReady();
    }

    resetPagination() {
        this.currentLimit = INITIAL_LIMIT;
        this.totalFetched = 0;
        this.activeSections = [];
    }

    // --- Data load ---------------------------------------------------------

    async loadOutputsIfReady() {
        if (!this._selectedPromptDevName || !this.startDate || !this.endDate) {
            // Stay hidden until a prompt is picked AND a date range is known.
            return;
        }
        this.isLoading = true;
        this.errorMessage = undefined;
        try {
            const data = await getPromptOutputs({
                promptDevName: this._selectedPromptDevName,
                startDate: this.startDate,
                endDate: this.endDate,
                limitCount: this.currentLimit
            });
            this.rawRows = Array.isArray(data) ? data : [];
            this.totalFetched = this.rawRows.length;
            this.visibleRows = this.rawRows.map((row, idx) => this.toViewModel(row, idx));
            this.hasLoadedOnce = true;
        } catch (err) {
            this.errorMessage = this.extractError(err);
            this.rawRows = [];
            this.visibleRows = [];
        } finally {
            this.isLoading = false;
        }
    }

    // --- View model --------------------------------------------------------

    toViewModel(row, idx) {
        const feedback = this.feedbackShape(row.feedbackValue);
        const tokens = (row.inputTokens || 0) + (row.outputTokens || 0);
        const inputText = row.inputPrompt || '';
        const outputText = row.generatedText || '';
        return {
            ...row,
            sectionName: `output-${idx}-${row.requestId || idx}`,
            feedbackLabel: feedback.label,
            feedbackIcon: feedback.icon,
            feedbackVariant: feedback.variant,
            feedbackBadgeClass: feedback.badgeClass,
            inputPromptCollapsed: this.truncate(inputText, COLLAPSED_CHARS),
            inputPromptNeedsTruncation: inputText.length > COLLAPSED_CHARS,
            generatedTextCollapsed: this.truncate(outputText, COLLAPSED_CHARS),
            generatedTextNeedsTruncation: outputText.length > COLLAPSED_CHARS,
            totalTokensDisplay: abbreviateNumber(tokens),
            inputTokensDisplay: abbreviateNumber(row.inputTokens || 0),
            outputTokensDisplay: abbreviateNumber(row.outputTokens || 0),
            safetyFlagClass: row.isToxic ? 'slds-text-color_error slds-text-title_bold' : 'slds-text-color_success'
        };
    }

    feedbackShape(value) {
        switch ((value || '').toLowerCase()) {
            case 'thumbs_up':
            case 'accepted':
                return {
                    label: 'Accepted',
                    icon: 'utility:success',
                    variant: 'success',
                    badgeClass: 'fm-badge fm-badge_success'
                };
            case 'thumbs_down':
            case 'rejected':
                return {
                    label: 'Rejected',
                    icon: 'utility:error',
                    variant: 'error',
                    badgeClass: 'fm-badge fm-badge_error'
                };
            case 'edited':
                return {
                    label: 'Edited',
                    icon: 'utility:edit',
                    variant: 'warning',
                    badgeClass: 'fm-badge fm-badge_warning'
                };
            default:
                return {
                    label: 'No feedback',
                    icon: 'utility:dash',
                    variant: 'inverse',
                    badgeClass: 'fm-badge fm-badge_neutral'
                };
        }
    }

    truncate(text, maxChars) {
        if (!text) return '';
        if (text.length <= maxChars) return text;
        return `${text.slice(0, maxChars)}…`;
    }

    // --- Accordion + pagination -------------------------------------------

    handleAccordionToggle(event) {
        // lightning-accordion emits an array of open section names.
        this.activeSections = event.detail.openSections || [];
    }

    async handleLoadMore() {
        this.currentLimit += PAGE_STEP;
        await this.loadOutputsIfReady();
    }

    // --- Expand modal -----------------------------------------------------

    /**
     * Fires when the user clicks an expand_alt icon next to an input or output.
     * Looks up the original row from `rawRows` so the modal gets the untruncated
     * text (the card shows a 200-char preview; here we want the full payload).
     */
    handleExpandText(event) {
        // lightning-button places dataset on the host element — use dataset
        // on currentTarget (the bound element, not the inner shadow button).
        const field = event.currentTarget.dataset.field; // "input" | "output"
        const rowId = event.currentTarget.dataset.rowId;
        const raw = this.rawRows.find((r) => String(r.requestId) === String(rowId));
        if (!raw) {
            // eslint-disable-next-line no-console
            console.warn('handleExpandText: row not found', { rowId, field });
            return;
        }
        const isInput = field === 'input';
        const title = isInput ? 'Input Prompt' : 'Generated Output';
        // Prefer the untruncated *Full field (Apex v2); fall back to the
        // truncated preview if the deployment is still serving the old DTO.
        const content = isInput
            ? (raw.inputPromptFull || raw.inputPrompt)
            : (raw.generatedTextFull || raw.generatedText);
        const metadata = {
            user: raw.userName,
            model: raw.model,
            date: raw.requestDate,
            tokens: isInput ? raw.inputTokens : raw.outputTokens
        };
        const modal = this.template.querySelector('c-ai-insights-text-modal');
        if (modal && typeof modal.open === 'function') {
            modal.open(title, content, metadata);
        } else {
            // eslint-disable-next-line no-console
            console.warn('handleExpandText: modal ref missing');
        }
    }

    // --- State getters -----------------------------------------------------

    get showComponent() {
        // Hidden by default; only render the card once a prompt is picked.
        return !!this._selectedPromptDevName;
    }

    get cardTitle() {
        if (this._selectedPromptLabel) {
            return `Outputs — ${this._selectedPromptLabel}`;
        }
        return 'Prompt Outputs';
    }

    get showEmptyState() {
        return this.hasLoadedOnce && !this.isLoading && !this.errorMessage && this.rawRows.length === 0;
    }

    get showError() {
        return !!this.errorMessage;
    }

    get showList() {
        return this.hasLoadedOnce && !this.showEmptyState && !this.showError && this.visibleRows.length > 0;
    }

    get showLoadMore() {
        // If the server returned exactly `currentLimit` rows, there may be more.
        return this.showList && this.totalFetched >= this.currentLimit;
    }

    get resultSummary() {
        if (!this.hasLoadedOnce || this.rawRows.length === 0) return '';
        return `Showing ${this.rawRows.length} output${this.rawRows.length === 1 ? '' : 's'}`;
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
