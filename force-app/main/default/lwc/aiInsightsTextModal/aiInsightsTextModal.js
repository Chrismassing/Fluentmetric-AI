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

    /**
     * Open the full text in a new browser tab as a minimally-styled HTML page.
     * We use a Blob + object URL rather than a data URL so long content doesn't
     * hit browser URL length limits. The page preserves whitespace (<pre>) and
     * echoes the metadata header so the new tab is self-describing.
     */
    handleDownloadHtml() {
        try {
            const html = this.buildStandaloneHtml();
            const blob = new Blob([html], { type: 'text/html;charset=utf-8' });
            const url = URL.createObjectURL(blob);
            const safeTitle = (this.title || 'fluentmetric').replace(/\W+/g, '_');
            const stamp = new Date().toISOString().slice(0, 19).replace(/[:T]/g, '-');
            const anchor = document.createElement('a');
            anchor.href = url;
            anchor.download = `${safeTitle}_${stamp}.html`;
            anchor.style.display = 'none';
            // documentElement (not body) escapes the modal's shadow-root boundary
            document.documentElement.appendChild(anchor);
            anchor.click();
            document.documentElement.removeChild(anchor);
            setTimeout(() => URL.revokeObjectURL(url), 10000);
            this.copyFeedback = 'Downloaded. Open the file to view in a new tab.';
            this.copyFeedbackVariant = 'success';
        } catch (err) {
            this.copyFeedback = 'Download failed. Try Copy, then paste into a new tab.';
            this.copyFeedbackVariant = 'error';
        }
    }

    /**
     * Open the full text in a new browser tab.
     *
     * LEX runs inside an iframe with strict CSP; data: and blob: URL navigation
     * are both blocked by Chrome/Firefox/Safari from non-same-origin contexts.
     * The only reliable pattern: call window.open('about:blank', '_blank')
     * **synchronously** in the click handler (browser grants popup as a user
     * gesture), then immediately write the HTML into the new window's document
     * in the same synchronous tick. Falls back to handleDownloadHtml if the
     * popup is blocked outright.
     */
    handleOpenInNewWindow() {
        try {
            const html = this.buildStandaloneHtml();
            const win = window.open('about:blank', '_blank');
            if (win) {
                win.document.open('text/html', 'replace');
                win.document.write(html);
                win.document.close();
                this.copyFeedback = 'Opened in new tab';
                this.copyFeedbackVariant = 'success';
                return;
            }
        } catch (err) {
            // Fall through to download fallback
        }
        // Popup was blocked — download the file instead so the user can open it locally.
        this.handleDownloadHtml();
        this.copyFeedback = 'Popup blocked — downloaded as a file instead. Open it to view in a new tab.';
        this.copyFeedbackVariant = 'success';
    }

    buildStandaloneHtml() {
        const safeTitle = this.escapeHtml(this.title || 'FluentMetric AI');
        const safeBody = this.escapeHtml(this.content || '');
        const metaLines = this.buildMetadataLines()
            .map((line) => `<div class="meta"><span class="meta-label">${this.escapeHtml(line.label)}</span><span class="meta-value">${this.escapeHtml(line.value)}</span></div>`)
            .join('');
        return [
            '<!DOCTYPE html>',
            '<html lang="en"><head><meta charset="utf-8">',
            `<title>${safeTitle} — FluentMetric AI</title>`,
            '<style>',
            'body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;margin:0;padding:1.5rem;background:#fafafa;color:#181818;}',
            'h1{font-size:1.25rem;margin:0 0 1rem 0;}',
            '.meta-row{display:flex;flex-wrap:wrap;gap:1rem;margin-bottom:1rem;}',
            '.meta{font-size:.8125rem;}',
            '.meta-label{text-transform:uppercase;letter-spacing:.0625rem;color:#555;margin-right:.25rem;}',
            '.meta-value{color:#181818;font-weight:600;}',
            'pre{white-space:pre-wrap;word-break:break-word;font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:.875rem;background:#fff;border:1px solid #e5e5e5;border-radius:.25rem;padding:1rem;margin:0;}',
            '</style></head><body>',
            `<h1>${safeTitle}</h1>`,
            metaLines ? `<div class="meta-row">${metaLines}</div>` : '',
            `<pre>${safeBody}</pre>`,
            '</body></html>'
        ].join('');
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

    escapeHtml(value) {
        if (value === null || value === undefined) return '';
        return String(value)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#39;');
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
