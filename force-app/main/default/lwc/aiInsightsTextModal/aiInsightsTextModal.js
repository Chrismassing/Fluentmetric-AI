import { LightningElement, api, track } from 'lwc';
import { TOOLTIPS } from 'c/aiInsightsTooltips';

const TT = TOOLTIPS.textModal;

/**
 * Reusable full-text modal for prompts and generated outputs.
 *
 * The dashboard truncates prompts and outputs to 200 chars inline so cards stay
 * browsable — but users frequently need to see the untruncated text (structured
 * system messages, bulleted outputs, code). This modal is the "expand" target.
 *
 * Opened imperatively via `@api open(title, content, metadata)`. The metadata
 * block above the body renders optional `{ user, model, date, tokens }` hints
 * so the user never loses context when zoomed in on a single prompt.
 *
 * A11y:
 *   - role="dialog" aria-modal="true" aria-labelledby on the heading
 *   - autofocus on the close button so keyboard users land somewhere
 *     sensible, and Escape closes the dialog
 *
 * Accessibility note: we deliberately do NOT set aria-hidden on background
 * content — the Lightning host manages focus trapping well enough in practice
 * for a dashboard drill-in, and re-implementing a full trap would be brittle.
 */
export default class AiInsightsTextModal extends LightningElement {
    @track isOpen = false;
    @track title = '';
    @track content = '';
    @track metadata;

    copyFeedback; // transient message after a copy action
    copyFeedbackVariant = 'success';

    _escapeHandler;

    tooltips = TT;

    // --- Public API --------------------------------------------------------

    /**
     * Open the modal with the given title and body text.
     * @param {String} title        modal heading (e.g. "Input Prompt")
     * @param {String} content      full untruncated body text
     * @param {Object} [metadata]   optional { user, model, date, tokens } hints
     */
    @api
    open(title, content, metadata) {
        this.title = title || 'Details';
        this.content = content == null ? '' : String(content);
        this.metadata = metadata || undefined;
        this.copyFeedback = undefined;
        this.isOpen = true;

        // Attach Escape-key listener on document while the modal is open. We
        // use document (not the host) because focus may be on any descendant
        // when Escape is pressed.
        this._escapeHandler = (event) => this.handleDocumentKeydown(event);
        document.addEventListener('keydown', this._escapeHandler);
    }

    @api
    close() {
        this.isOpen = false;
        this.copyFeedback = undefined;
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

    // --- Event handlers ----------------------------------------------------

    handleDocumentKeydown(event) {
        if (event.key === 'Escape' || event.key === 'Esc') {
            this.close();
        }
    }

    handleClose() {
        this.close();
    }

    /**
     * Backdrop-click dismissal — only fires when the click lands on the
     * backdrop itself, not when it bubbles up from the modal container.
     */
    handleBackdropClick(event) {
        if (event.target.dataset.role === 'backdrop') {
            this.close();
        }
    }

    // Stop propagation so clicks inside the modal don't trigger backdrop close.
    handleModalClick(event) {
        event.stopPropagation();
    }

    async handleCopy() {
        // navigator.clipboard is available in Lightning Experience; fall back
        // to a textarea-select-copy path when the API isn't present (older
        // browsers, insecure contexts) so the button never silently fails.
        try {
            if (navigator.clipboard && navigator.clipboard.writeText) {
                await navigator.clipboard.writeText(this.content || '');
            } else {
                this.legacyCopy(this.content || '');
            }
            this.copyFeedback = 'Copied to clipboard';
            this.copyFeedbackVariant = 'success';
        } catch (err) {
            this.copyFeedback = 'Copy failed — select the text manually';
            this.copyFeedbackVariant = 'error';
        }
    }

    legacyCopy(text) {
        const ta = document.createElement('textarea');
        ta.value = text;
        ta.setAttribute('readonly', '');
        ta.style.position = 'absolute';
        ta.style.left = '-9999px';
        document.body.appendChild(ta);
        ta.select();
        document.execCommand('copy');
        document.body.removeChild(ta);
    }

    buildMetadataLines() {
        const m = this.metadata || {};
        const out = [];
        if (m.user) out.push({ label: 'User', value: m.user });
        if (m.model) out.push({ label: 'Model', value: m.model });
        if (m.date) out.push({ label: 'Date', value: m.date });
        if (m.tokens !== undefined && m.tokens !== null && m.tokens !== '') {
            out.push({ label: 'Tokens', value: String(m.tokens) });
        }
        return out;
    }

    // --- Getters -----------------------------------------------------------

    get ariaLabelledById() {
        return 'fm-text-modal-heading';
    }

    get hasMetadata() {
        return this.buildMetadataLines().length > 0;
    }

    get metadataLines() {
        return this.buildMetadataLines().map((line, idx) => ({
            key: `${line.label}-${idx}`,
            label: line.label,
            value: line.value
        }));
    }

    get hasCopyFeedback() {
        return !!this.copyFeedback;
    }

    get copyFeedbackClass() {
        const base = 'slds-text-body_small slds-m-left_small';
        if (this.copyFeedbackVariant === 'error') {
            return `${base} slds-text-color_error`;
        }
        return `${base} slds-text-color_success`;
    }
}
