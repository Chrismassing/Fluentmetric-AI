import { LightningElement, api, track } from 'lwc';
import getEntityDetails from '@salesforce/apex/AiInsightsController.getEntityDetails';
import { abbreviateNumber, formatPercent, relativeTime } from './numberFormat';
import { TOOLTIPS } from 'c/aiInsightsTooltips';

const TT = TOOLTIPS.entityDetails;
const OUTPUT_TT = TOOLTIPS.promptOutputViewer;
const MODAL_TT = TOOLTIPS.textModal;
const COLLAPSED_CHARS = 200;
const DEFAULT_LIMIT = 20;

/**
 * Entity drill-in modal. Opened imperatively by the dashboard tables; fetches
 * recent requests + aggregate stats for a single User / PromptTemplate / Model
 * / Feature and renders:
 *   - a stats strip (KPI tiles)
 *   - an accordion of recent requests modelled on aiInsightsPromptOutputViewer
 *
 * Uses the reusable aiInsightsTextModal (nested) to render the untruncated
 * prompt / generated text when the user hits Expand inside an accordion row.
 *
 * A11y:
 *   - role="dialog" aria-modal="true" aria-labelledby on the heading
 *   - autofocus on the close button so keyboard users land somewhere sensible
 *   - Escape closes
 *   - backdrop click closes
 *
 * Hard rules honored:
 *   - we do NOT mix lwc:if + lwc:else on the same element (use inverted getters)
 *   - we seed a default 30-day window on open() if the caller omits dates
 *   - every KPI tile has a tooltip via TOOLTIPS.entityDetails.*
 */
export default class AiInsightsDetailsModal extends LightningElement {
    @track isOpen = false;
    @track isLoading = false;
    @track errorMessage;

    // Inputs resolved on open()
    @track entityType;   // "User" | "PromptTemplate" | "Model" | "Feature"
    @track entityKey;
    @track entityLabel;
    @track startDate;
    @track endDate;
    criteriaJson;  // serialised FilterCriteria — forwarded to getEntityDetails

    // Response state
    @track details;               // EntityDetailsDTO
    @track recentRequests = [];   // pre-shaped view-model
    @track activeSections = [];

    tooltips = TT;
    outputTooltips = OUTPUT_TT;
    modalTooltips = MODAL_TT;

    _escapeHandler;

    // ──────────────────────────────────────────────────────────────────────
    // Public API
    // ──────────────────────────────────────────────────────────────────────

    /**
     * Open the modal for a given entity and fetch its details from Apex.
     *
     * @param {String} entityType   "User" | "PromptTemplate" | "Model" | "Feature"
     * @param {String} entityKey    raw key (userId, prompt dev name, model name, feature name)
     * @param {String} entityLabel  resolved display label (falls back to key)
     * @param {String} [startDate]  ISO datetime; defaults to 30 days ago
     * @param {String} [endDate]    ISO datetime; defaults to now
     */
    @api
    async open(entityType, entityKey, entityLabel, startDate, endDate, criteriaJson) {
        this.entityType = entityType;
        this.entityKey = entityKey;
        this.entityLabel = entityLabel || entityKey || '—';
        this.criteriaJson = criteriaJson || null;

        // Seed defaults so a caller forgetting dates still gets a usable
        // modal. This matches the defensive pattern used by the dashboards.
        const seedStart = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString();
        const seedEnd = new Date().toISOString();
        this.startDate = startDate || seedStart;
        this.endDate = endDate || seedEnd;

        this.details = undefined;
        this.recentRequests = [];
        this.activeSections = [];
        this.errorMessage = undefined;
        this.isOpen = true;
        this.isLoading = true;

        // Attach Escape handler on document while the modal is open. Same
        // pattern as aiInsightsTextModal.
        this._escapeHandler = (event) => this.handleDocumentKeydown(event);
        document.addEventListener('keydown', this._escapeHandler);

        try {
            const data = await getEntityDetails({
                entityType: this.entityType,
                entityKey: this.entityKey,
                startDate: this.startDate,
                endDate: this.endDate,
                recentLimit: DEFAULT_LIMIT,
                criteriaJson: this.criteriaJson
            });
            this.details = data || {};
            this.recentRequests = ((data && data.recentRequests) || []).map(
                (row, idx) => this.toRequestCard(row, idx)
            );
        } catch (err) {
            this.errorMessage = this.extractError(err);
        } finally {
            this.isLoading = false;
        }
    }

    @api
    close() {
        this.isOpen = false;
        if (this._escapeHandler) {
            document.removeEventListener('keydown', this._escapeHandler);
            this._escapeHandler = undefined;
        }
    }

    disconnectedCallback() {
        if (this._escapeHandler) {
            document.removeEventListener('keydown', this._escapeHandler);
            this._escapeHandler = undefined;
        }
    }

    // ──────────────────────────────────────────────────────────────────────
    // Event handlers
    // ──────────────────────────────────────────────────────────────────────

    handleDocumentKeydown(event) {
        if (event.key === 'Escape' || event.key === 'Esc') {
            this.close();
        }
    }

    handleClose() {
        this.close();
    }

    handleBackdropClick(event) {
        if (event.target.dataset.role === 'backdrop') {
            this.close();
        }
    }

    // Stop propagation so clicks inside the modal don't bubble up to the
    // backdrop and close the dialog.
    handleModalClick(event) {
        event.stopPropagation();
    }

    handleAccordionToggle(event) {
        this.activeSections = event.detail.openSections || [];
    }

    /**
     * Expand a single request's input or output in the nested text modal.
     * Looks up the row by requestId so we don't have to carry the full
     * untruncated text through the DOM.
     */
    handleExpandText(event) {
        const field = event.currentTarget.dataset.field; // "input" | "output"
        const requestId = event.currentTarget.dataset.requestId;
        const row = this.recentRequests.find((r) => String(r.requestId) === String(requestId));
        if (!row) return;
        const isInput = field === 'input';
        const title = isInput ? 'Input Prompt' : 'Generated Output';
        // Prefer the untruncated *Full field; fall back to the truncated
        // preview for safety against older DTO shapes.
        const content = isInput
            ? (row.inputPromptFull || row.inputPrompt)
            : (row.generatedTextFull || row.generatedText);
        const metadata = {
            user: row.userName,
            model: row.model,
            date: row.requestDate,
            tokens: isInput ? row.inputTokens : row.outputTokens
        };
        const modal = this.template.querySelector('c-ai-insights-text-modal');
        if (modal && typeof modal.open === 'function') {
            modal.open(title, content, metadata);
        }
    }

    // ──────────────────────────────────────────────────────────────────────
    // View-model builders
    // ──────────────────────────────────────────────────────────────────────

    toRequestCard(row, idx) {
        const feedback = this.feedbackShape(row.feedbackValue);
        const inputText = row.inputPrompt || '';
        const outputText = row.generatedText || '';
        const tokens = (row.inputTokens || 0) + (row.outputTokens || 0);
        const userName = row.userName || 'Unknown user';
        const dateLabel = this.shortTimestamp(row.requestDate);
        // Section header surfaces both who and when so users can scan the
        // collapsed accordion list without expanding every row.
        const sectionLabel = dateLabel ? `${userName} — ${dateLabel}` : userName;
        return {
            ...row,
            sectionName: `details-row-${idx}-${row.requestId || idx}`,
            sectionLabel,
            feedbackLabel: feedback.label,
            feedbackIcon: feedback.icon,
            feedbackBadgeClass: feedback.badgeClass,
            inputPromptCollapsed: this.truncate(inputText, COLLAPSED_CHARS),
            generatedTextCollapsed: this.truncate(outputText, COLLAPSED_CHARS),
            totalTokensDisplay: abbreviateNumber(tokens),
            inputTokensDisplay: abbreviateNumber(row.inputTokens || 0),
            outputTokensDisplay: abbreviateNumber(row.outputTokens || 0),
            safetyFlagClass: row.isToxic
                ? 'slds-text-color_error slds-text-title_bold'
                : 'slds-text-color_success'
        };
    }

    shortTimestamp(value) {
        if (!value) return '';
        const d = new Date(value);
        if (Number.isNaN(d.getTime())) return '';
        // Locale-aware short stamp: e.g. "May 8, 14:32" — gives both date and
        // time at a glance without overwhelming the section header.
        return d.toLocaleString(undefined, {
            month: 'short',
            day: 'numeric',
            hour: '2-digit',
            minute: '2-digit'
        });
    }

    feedbackShape(value) {
        switch ((value || '').toLowerCase()) {
            case 'thumbs_up':
            case 'accepted':
                return {
                    label: 'Accepted',
                    icon: 'utility:success',
                    badgeClass: 'fm-badge fm-badge_success'
                };
            case 'thumbs_down':
            case 'rejected':
                return {
                    label: 'Rejected',
                    icon: 'utility:error',
                    badgeClass: 'fm-badge fm-badge_error'
                };
            case 'edited':
                return {
                    label: 'Edited',
                    icon: 'utility:edit',
                    badgeClass: 'fm-badge fm-badge_warning'
                };
            default:
                return {
                    label: 'No feedback',
                    icon: 'utility:dash',
                    badgeClass: 'fm-badge fm-badge_neutral'
                };
        }
    }

    truncate(text, maxChars) {
        if (!text) return '';
        if (text.length <= maxChars) return text;
        return `${text.slice(0, maxChars)}…`;
    }

    // ──────────────────────────────────────────────────────────────────────
    // Getters — header / subtitle
    // ──────────────────────────────────────────────────────────────────────

    get ariaLabelledById() {
        return 'fm-details-modal-heading';
    }

    get entityTypeLabel() {
        switch (this.entityType) {
            case 'User':
                return 'User';
            case 'PromptTemplate':
                return 'Prompt';
            case 'Model':
                return 'Model';
            case 'Feature':
                return 'Feature';
            default:
                return this.entityType || 'Entity';
        }
    }

    get modalTitle() {
        const label = (this.details && this.details.entityLabel) || this.entityLabel || '—';
        return `${this.entityTypeLabel}: ${label}`;
    }

    get showRawKey() {
        // Hide the raw-key subtitle when it's identical to the visible label
        // (common for Model / Feature where key === label).
        const label = (this.details && this.details.entityLabel) || this.entityLabel;
        return this.entityKey && this.entityKey !== label;
    }

    // ──────────────────────────────────────────────────────────────────────
    // Getters — stats strip
    // ──────────────────────────────────────────────────────────────────────

    get requestCountDisplay() {
        return abbreviateNumber((this.details && this.details.requestCount) || 0);
    }

    get totalTokensDisplay() {
        return abbreviateNumber((this.details && this.details.totalTokens) || 0);
    }

    get avgTokensDisplay() {
        const v = this.details && this.details.avgTokensPerRequest;
        if (v === null || v === undefined) return '—';
        return abbreviateNumber(v);
    }

    get firstUsedDisplay() {
        return relativeTime(this.details && this.details.firstUsed);
    }

    get firstUsedTitle() {
        return (this.details && this.details.firstUsed) || '';
    }

    get lastUsedDisplay() {
        return relativeTime(this.details && this.details.lastUsed);
    }

    get lastUsedTitle() {
        return (this.details && this.details.lastUsed) || '';
    }

    // Acceptance rate — tri-band color. `acceptanceRate` is nullable on the
    // DTO; "—" when no feedback exists is a deliberate signal, not an error.
    get acceptancePct() {
        const v = this.details && this.details.acceptanceRate;
        if (v === null || v === undefined) return null;
        const n = Number(v);
        if (Number.isNaN(n)) return null;
        return Math.abs(n) <= 1 ? n * 100 : n;
    }

    get acceptanceDisplay() {
        const pct = this.acceptancePct;
        if (pct === null) return '—';
        return formatPercent(pct / 100);
    }

    get acceptanceTileClass() {
        const pct = this.acceptancePct;
        let tone = 'neutral';
        if (pct !== null) {
            if (pct > 70) tone = 'success';
            else if (pct >= 50) tone = 'warning';
            else tone = 'error';
        }
        return `fm-stat-tile fm-stat-tile_${tone}`;
    }

    // Safety flags — red if any exist, green otherwise.
    get toxicFlagCount() {
        return (this.details && this.details.toxicFlagCount) || 0;
    }

    get toxicFlagDisplay() {
        return abbreviateNumber(this.toxicFlagCount);
    }

    get toxicFlagTileClass() {
        const tone = this.toxicFlagCount > 0 ? 'error' : 'success';
        return `fm-stat-tile fm-stat-tile_${tone}`;
    }

    get uniqueUserDisplay() {
        return abbreviateNumber((this.details && this.details.uniqueUserCount) || 0);
    }

    get uniquePromptDisplay() {
        return abbreviateNumber((this.details && this.details.uniquePromptCount) || 0);
    }

    // Hide "Unique users" when the entity itself IS a user — the tile would
    // just read "1" and confuse the reader. Same for prompts when the entity
    // is a prompt template.
    get showUniqueUsersTile() {
        return this.entityType !== 'User';
    }

    get showUniquePromptsTile() {
        return this.entityType !== 'PromptTemplate';
    }

    // ──────────────────────────────────────────────────────────────────────
    // Getters — recent requests section
    // ──────────────────────────────────────────────────────────────────────

    get hasRecentRequests() {
        return this.recentRequests.length > 0;
    }

    // Inverted getter — LWC forbids `lwc:if` + `lwc:else` on the same element,
    // so the "no recent requests" empty state gets its own boolean.
    get hasNoRecentRequests() {
        return !this.isLoading && !this.errorMessage && this.recentRequests.length === 0 && !!this.details;
    }

    get showError() {
        return !!this.errorMessage;
    }

    get showBody() {
        return !this.isLoading && !this.errorMessage;
    }

    get recentRequestCountLabel() {
        const n = this.recentRequests.length;
        if (n === 0) return '';
        return `${n} recent request${n === 1 ? '' : 's'}`;
    }

    // ──────────────────────────────────────────────────────────────────────
    // Error extraction
    // ──────────────────────────────────────────────────────────────────────

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
