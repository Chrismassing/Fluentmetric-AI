import { LightningElement, api, track, wire } from 'lwc';
import { publish, MessageContext } from 'lightning/messageService';
import AI_INSIGHTS_FILTERS from '@salesforce/messageChannel/AiInsightsFilters__c';
import getEntityDetails from '@salesforce/apex/AiInsightsController.getEntityDetails';
import getEntityBreakdown from '@salesforce/apex/AiInsightsController.getEntityBreakdown';
import { abbreviateNumber, formatPercent } from './numberFormat';

const COLLAPSED_CHARS = 200;
const SAMPLE_LIMIT = 20;
const BREAKDOWN_LIMIT = 10;

// Default click-X-see-Y matrix. Lateral pivots default to the dimension a user
// is most likely to want next given the source. The user can change the
// breakdown via the segmented control inside the panel.
const DEFAULT_BREAKDOWN = {
    User: 'PromptTemplate',
    PromptTemplate: 'User',
    Model: 'PromptTemplate',
    Feature: 'User'
};

const ALLOWED_BREAKDOWNS = ['User', 'PromptTemplate', 'Model', 'Feature', 'Day'];

const ENTITY_LABEL = {
    User: 'User',
    PromptTemplate: 'Prompt template',
    Model: 'Model',
    Feature: 'Feature'
};

const ENTITY_ICON = {
    User: 'standard:user',
    PromptTemplate: 'standard:prompt_builder',
    Model: 'standard:einstein',
    Feature: 'standard:apex'
};

/**
 * Pivot drill side-sheet. Replaces the centred details modal as the primary
 * drill surface. Supports a stack of frames so the user can chain
 * User → Prompt → Model → ... and pop back via breadcrumbs.
 *
 * Two tabs:
 *   - Breakdown (default): rows = breakdownBy values for the source entity,
 *     each row drillable to push a new frame.
 *   - Sample requests: opt-in raw request accordion (existing behaviour).
 *
 * The host (aiInsightsApp / parent dashboard) places one instance and opens
 * it imperatively via `open(entityType, entityKey, entityLabel, start, end)`.
 */
export default class AiInsightsDrillPanel extends LightningElement {
    @track isOpen = false;
    @track isLoading = false;
    @track isLoadingBreakdown = false;
    @track errorMessage;
    @track activeTab = 'breakdown'; // 'breakdown' | 'samples'

    // Date range — common to every frame in the stack.
    @track startDate;
    @track endDate;
    // Inbound rail criteria (from the parent dashboard's filter rail).
    // Forwarded to every Apex call so a Model+Feature pre-filter stays in
    // effect as the user pivots inside the drill panel. Stored as the raw
    // JSON string the Explorer / Apex layer expects.
    @track criteriaJson;

    // Stack of {type, key, label, breakdown}. Last element is the current view.
    @track stack = [];

    // Aggregates + recent rows for the current frame.
    @track details;
    @track breakdown = [];
    @track recentRequests = [];
    @track activeSections = [];

    _escapeHandler;

    @wire(MessageContext)
    messageContext;

    // ──────────────────────────────────────────────────────────────────────
    // Public API
    // ──────────────────────────────────────────────────────────────────────

    @api
    async open(entityType, entityKey, entityLabel, startDate, endDate, criteriaJson) {
        const seedStart = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString();
        const seedEnd = new Date().toISOString();
        this.startDate = startDate || seedStart;
        this.endDate = endDate || seedEnd;
        this.criteriaJson = criteriaJson || null;

        // Fresh stack — closing the panel clears prior context.
        this.stack = [
            {
                type: entityType,
                key: entityKey,
                label: entityLabel || entityKey || '—',
                breakdown: DEFAULT_BREAKDOWN[entityType] || 'PromptTemplate'
            }
        ];
        this.errorMessage = undefined;
        this.activeTab = 'breakdown';
        this.isOpen = true;

        this._escapeHandler = (event) => this.handleDocumentKeydown(event);
        document.addEventListener('keydown', this._escapeHandler);

        await this.loadCurrentFrame();
    }

    @api
    close() {
        this.isOpen = false;
        this.stack = [];
        this.details = undefined;
        this.breakdown = [];
        this.recentRequests = [];
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
    // Frame loading
    // ──────────────────────────────────────────────────────────────────────

    async loadCurrentFrame() {
        const frame = this.currentFrame;
        if (!frame) return;
        this.isLoading = true;
        this.isLoadingBreakdown = true;
        this.errorMessage = undefined;
        try {
            const [details, breakdown] = await Promise.all([
                getEntityDetails({
                    entityType: frame.type,
                    entityKey: frame.key,
                    startDate: this.startDate,
                    endDate: this.endDate,
                    recentLimit: SAMPLE_LIMIT,
                    criteriaJson: this.criteriaJson
                }),
                getEntityBreakdown({
                    entityType: frame.type,
                    entityKey: frame.key,
                    breakdownBy: frame.breakdown,
                    startDate: this.startDate,
                    endDate: this.endDate,
                    metric: 'RequestCount',
                    resultLimit: BREAKDOWN_LIMIT,
                    criteriaJson: this.criteriaJson
                }).catch(() => [])
            ]);
            this.details = details || {};
            this.recentRequests = ((details && details.recentRequests) || []).map(
                (row, idx) => this.toRequestCard(row, idx)
            );
            this.breakdown = (Array.isArray(breakdown) ? breakdown : []).map((row) =>
                this.toBreakdownRow(row, frame.breakdown)
            );
        } catch (err) {
            this.errorMessage = this.extractError(err);
            this.details = undefined;
            this.recentRequests = [];
            this.breakdown = [];
        } finally {
            this.isLoading = false;
            this.isLoadingBreakdown = false;
        }
    }

    // ──────────────────────────────────────────────────────────────────────
    // Stack navigation (push / pop / lateral pivot swap)
    // ──────────────────────────────────────────────────────────────────────

    handleBreakdownRowClick(event) {
        const groupKey = event.currentTarget.dataset.groupKey;
        const groupLabel = event.currentTarget.dataset.groupLabel;
        const targetType = this.currentFrame?.breakdown;
        if (!targetType || !ALLOWED_BREAKDOWNS.includes(targetType) || targetType === 'Day') {
            // Day rows aren't drillable as entities — they're a time bucket.
            return;
        }
        // Push a new frame; default the next breakdown using the matrix.
        this.stack = [
            ...this.stack,
            {
                type: targetType,
                key: groupKey,
                label: groupLabel || groupKey,
                breakdown: DEFAULT_BREAKDOWN[targetType] || 'User'
            }
        ];
        this.activeTab = 'breakdown';
        this.loadCurrentFrame();
    }

    handleBreadcrumbClick(event) {
        const targetIdx = Number(event.currentTarget.dataset.idx);
        if (Number.isNaN(targetIdx) || targetIdx < 0 || targetIdx >= this.stack.length - 1) {
            return; // Last crumb is the current frame; no-op.
        }
        this.stack = this.stack.slice(0, targetIdx + 1);
        this.loadCurrentFrame();
    }

    handleBreakdownSelectorChange(event) {
        const next = event?.target?.value;
        if (!next || !ALLOWED_BREAKDOWNS.includes(next)) return;
        const frame = this.currentFrame;
        if (!frame || frame.breakdown === next) return;
        // Replace the top frame with the new breakdown — lateral pivot, not a
        // new drill level.
        this.stack = [
            ...this.stack.slice(0, -1),
            { ...frame, breakdown: next }
        ];
        this.loadCurrentFrame();
    }

    handleTabClick(event) {
        const tab = event.currentTarget.dataset.tab;
        if (tab === 'breakdown' || tab === 'samples') {
            this.activeTab = tab;
        }
    }

    // ──────────────────────────────────────────────────────────────────────
    // Lifecycle helpers
    // ──────────────────────────────────────────────────────────────────────

    handleClose() {
        this.close();
    }

    /**
     * "Pin to Explorer" hand-off. Builds a FilterCriteria that combines the
     * inbound rail criteria (already on `criteriaJson`) with the current
     * frame's source entity, publishes it on AiInsightsFilters along with a
     * groupBy hint matching the panel's current breakdown dimension, then
     * fires `openinexplorer` so the host (aiInsightsApp) can switch tabs.
     *
     * The Explorer subscribes to AiInsightsFilters and already re-runs on
     * any external publish, so the criteria + groupBy land in one trip.
     */
    handleOpenInExplorer() {
        const frame = this.currentFrame;
        if (!frame) return;
        const inbound = this.parseInboundCriteria();
        const merged = this.mergeEntityIntoCriteria(inbound, frame.type, frame.key);
        merged.startDate = this.startDate;
        merged.endDate = this.endDate;

        // Map the panel's source entity back to the Explorer's groupBy values.
        // We hand off using the frame's *current breakdown* (most useful: the
        // user pivoted to "Day" and wants to keep Day in Explorer) — falling
        // back to the source type when the breakdown is the source itself.
        const groupBy = frame.breakdown || frame.type;

        publish(this.messageContext, AI_INSIGHTS_FILTERS, {
            criteriaJson: JSON.stringify(merged),
            startDate: this.startDate,
            endDate: this.endDate,
            groupBy
        });

        this.dispatchEvent(new CustomEvent('openinexplorer', {
            detail: { groupBy },
            bubbles: true,
            composed: true
        }));
        this.close();
    }

    parseInboundCriteria() {
        if (!this.criteriaJson) return {};
        try {
            const parsed = JSON.parse(this.criteriaJson);
            return parsed && typeof parsed === 'object' ? parsed : {};
        } catch (_) {
            return {};
        }
    }

    /**
     * Layer the source entity onto an existing criteria bag — replaces the
     * matching dimension (User/PromptTemplate/Model/Feature) with the single
     * entity key, leaves the other dimensions untouched. Mirrors the Apex
     * applyEntityToCriteria semantics so the LWC and Apex agree.
     */
    mergeEntityIntoCriteria(criteria, entityType, entityKey) {
        const out = { ...(criteria || {}) };
        if (entityType === 'User') out.userIds = [entityKey];
        else if (entityType === 'PromptTemplate') out.promptTemplateDevNames = [entityKey];
        else if (entityType === 'Model') out.models = [entityKey];
        else if (entityType === 'Feature') out.features = [entityKey];
        return out;
    }

    handleBackdropClick(event) {
        if (event?.target?.dataset?.role === 'backdrop') {
            this.close();
        }
    }

    handleDocumentKeydown(event) {
        if (event.key === 'Escape' || event.key === 'Esc') {
            this.close();
        }
    }

    handleAccordionToggle(event) {
        this.activeSections = event.detail.openSections;
    }

    handleExpandText(event) {
        const requestId = event.currentTarget.dataset.requestId;
        const field = event.currentTarget.dataset.field;
        const row = this.recentRequests.find((r) => r.requestId === requestId);
        if (!row) return;
        const isInput = field === 'input';
        const title = isInput ? 'Input prompt' : 'Generated output';
        const content = isInput ? row.inputPrompt : row.generatedText;
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

    toBreakdownRow(row, breakdownBy) {
        const value = Number(row?.metricValue) || 0;
        return {
            groupKey: row?.groupKey,
            groupLabel: row?.groupLabel || row?.groupKey || '—',
            metricDisplay: abbreviateNumber(value),
            supportingDisplay: row?.supportingCount ? `${abbreviateNumber(row.supportingCount)} supporting` : '',
            isClickable: breakdownBy !== 'Day' && !!row?.groupKey
        };
    }

    toRequestCard(row, idx) {
        const inputText = row.inputPrompt || '';
        const outputText = row.generatedText || '';
        const userName = row.userName || 'Unknown user';
        const dateLabel = this.shortTimestamp(row.requestDate);
        const sectionLabel = dateLabel ? `${userName} — ${dateLabel}` : userName;
        return {
            ...row,
            sectionName: `drill-row-${idx}-${row.requestId || idx}`,
            sectionLabel,
            inputPromptCollapsed: this.truncate(inputText, COLLAPSED_CHARS),
            generatedTextCollapsed: this.truncate(outputText, COLLAPSED_CHARS),
            inputTokensDisplay: abbreviateNumber(row.inputTokens || 0),
            outputTokensDisplay: abbreviateNumber(row.outputTokens || 0)
        };
    }

    truncate(text, max) {
        if (!text) return '';
        return text.length > max ? `${text.slice(0, max)}…` : text;
    }

    shortTimestamp(value) {
        if (!value) return '';
        const d = new Date(value);
        if (Number.isNaN(d.getTime())) return '';
        return d.toLocaleString(undefined, {
            month: 'short',
            day: 'numeric',
            hour: '2-digit',
            minute: '2-digit'
        });
    }

    extractError(err) {
        if (!err) return 'Unknown error';
        if (typeof err === 'string') return err;
        if (err.body && err.body.message) return err.body.message;
        if (Array.isArray(err.body) && err.body.length) return err.body.map((e) => e.message).join(', ');
        return err.message || 'Unknown error';
    }

    // ──────────────────────────────────────────────────────────────────────
    // Getters for the template
    // ──────────────────────────────────────────────────────────────────────

    get currentFrame() {
        return this.stack.length > 0 ? this.stack[this.stack.length - 1] : null;
    }

    get headerLabel() {
        return this.currentFrame ? this.currentFrame.label : '';
    }

    get headerEntityType() {
        const t = this.currentFrame?.type;
        return ENTITY_LABEL[t] || t || '';
    }

    get headerIcon() {
        return ENTITY_ICON[this.currentFrame?.type] || 'standard:default';
    }

    get breadcrumbs() {
        if (this.stack.length <= 1) return [];
        // All but the last frame are clickable breadcrumbs.
        return this.stack.slice(0, -1).map((frame, idx) => ({
            idx,
            label: frame.label,
            type: ENTITY_LABEL[frame.type] || frame.type
        }));
    }

    get hasBreadcrumbs() {
        return this.breadcrumbs.length > 0;
    }

    get breakdownOptions() {
        return [
            { label: 'User', value: 'User' },
            { label: 'Prompt template', value: 'PromptTemplate' },
            { label: 'Model', value: 'Model' },
            { label: 'Feature', value: 'Feature' },
            { label: 'Day', value: 'Day' }
        ];
    }

    get currentBreakdown() {
        return this.currentFrame?.breakdown || 'User';
    }

    get breakdownTitle() {
        const opt = this.breakdownOptions.find((o) => o.value === this.currentBreakdown);
        return opt ? opt.label : this.currentBreakdown;
    }

    get showBreakdownTab() {
        return this.activeTab === 'breakdown';
    }
    get showSamplesTab() {
        return this.activeTab === 'samples';
    }

    get breakdownTabClass() {
        return this.showBreakdownTab
            ? 'slds-tabs_default__item slds-is-active'
            : 'slds-tabs_default__item';
    }
    get samplesTabClass() {
        return this.showSamplesTab
            ? 'slds-tabs_default__item slds-is-active'
            : 'slds-tabs_default__item';
    }

    get hasBreakdownRows() {
        return Array.isArray(this.breakdown) && this.breakdown.length > 0;
    }
    get hasNoBreakdownRows() {
        return !this.isLoadingBreakdown && !this.errorMessage && !this.hasBreakdownRows;
    }

    get hasRecentRequests() {
        return Array.isArray(this.recentRequests) && this.recentRequests.length > 0;
    }
    get hasNoRecentRequests() {
        return !this.isLoading && !this.errorMessage && !this.hasRecentRequests;
    }

    get requestCountDisplay() {
        return abbreviateNumber(this.details?.requestCount || 0);
    }
    get totalTokensDisplay() {
        const input = this.details?.totalInputTokens || 0;
        const output = this.details?.totalOutputTokens || 0;
        return abbreviateNumber(input + output);
    }
    get acceptanceDisplay() {
        return formatPercent(this.details?.acceptanceRate);
    }
    get toxicFlagDisplay() {
        return abbreviateNumber(this.details?.toxicFlagCount || 0);
    }

    get showError() {
        return !!this.errorMessage;
    }
}
