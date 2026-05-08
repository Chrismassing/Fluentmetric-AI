import { LightningElement, api, wire } from 'lwc';
import { publish, subscribe, unsubscribe, MessageContext } from 'lightning/messageService';
import AI_INSIGHTS_FILTERS from '@salesforce/messageChannel/AiInsightsFilters__c';
import AI_INSIGHTS_DATE_RANGE from '@salesforce/messageChannel/AiInsightsDateRange__c';
import getFilterFacets from '@salesforce/apex/AiInsightsController.getFilterFacets';
import searchUsersInRange from '@salesforce/apex/AiInsightsController.searchUsersInRange';

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

const PUBLISH_DEBOUNCE_MS = 200;
const USER_SEARCH_DEBOUNCE_MS = 300;
const USER_SEARCH_MIN_CHARS = 2;
const STORAGE_KEY = 'fluentmetric_filter_rail_v1';
const STORAGE_KEY_EXPANDED = 'fluentmetric_filter_rail_expanded_by_tab_v1';
const EXPAND_BY_DEFAULT_TAB = 'Explorer';

/**
 * Dynamic filter rail for the FluentMetric AI dashboards.
 *
 * Architecture:
 *   - Owns the single source of truth for the active criteria:
 *     { startDate, endDate, userIds, promptTemplateDevNames, models,
 *       providers, features, appTypes }
 *   - Publishes the full serialized criteria to AiInsightsFilters on any
 *     change (debounced). For backwards compatibility with the existing
 *     dashboards that still listen to AiInsightsDateRange, the rail also
 *     re-publishes the date portion there.
 *   - Hydrates combobox options from getFilterFacets(startDate, endDate) so
 *     every picker shows only values that actually occur in the window.
 *   - User filter uses searchUsersInRange typeahead (min 2 chars) because
 *     user cardinality is unbounded; other facets are precomputed.
 *
 * Persistence: last-used criteria saved to sessionStorage so a tab reload
 * doesn't wipe the filters. Keyed by a versioned constant so we can
 * invalidate cleanly when the criteria shape changes.
 */
export default class AiInsightsFilterRail extends LightningElement {
    @wire(MessageContext)
    messageContext;

    // ── Date state ─────────────────────────────────────────────────
    preset = PRESET_LAST_30;
    customStart;
    customEnd;
    dateError;

    // ── Dimension state (arrays of selected values) ────────────────
    selectedUserIds = [];
    selectedUserLabels = {}; // userId → label (so pills still render if user leaves range)
    selectedPromptTemplateDevNames = [];
    selectedModels = [];
    selectedProviders = [];
    selectedFeatures = [];
    selectedAppTypes = [];

    // ── Facet options (populated from Apex) ────────────────────────
    facetModels = [];
    facetProviders = [];
    facetFeatures = [];
    facetAppTypes = [];
    facetPromptTemplates = [];
    facetTopUsers = [];

    // ── User typeahead state ───────────────────────────────────────
    userQuery = '';
    userSearchResults = [];
    userSearchLoading = false;

    // ── Section collapsed state ────────────────────────────────────
    collapsed = {
        date: true,
        who: true,
        what: true
    };

    // ── Top-level rail expand/collapse state ───────────────────────
    // Tracks whether the rail is rendered full-width or collapsed to a
    // narrow strip. Per-tab decisions live in sessionStorage keyed by
    // STORAGE_KEY_EXPANDED so a user's choice on one tab doesn't leak
    // to others. Default rule: Explorer expands, every other tab
    // collapses — because only Explorer consumes criteria today.
    expanded = false;
    _activeTab;
    _userExpandedByTab = {};

    // ── Timers / subscriptions ─────────────────────────────────────
    subscription;
    publishTimer;
    userSearchTimer;
    facetsLoadedForRange;

    @api
    get activeTab() {
        return this._activeTab;
    }
    set activeTab(value) {
        this._activeTab = value;
        this.resolveExpandedForTab();
    }

    connectedCallback() {
        this.restoreFromStorage();
        this.restoreExpandedFromStorage();
        this.initializeDates();
        this.resolveExpandedForTab();
        this.subscription = subscribe(this.messageContext, AI_INSIGHTS_FILTERS, (msg) =>
            this.handleExternalCriteria(msg)
        );
        // Kick off first publish + facet load with the seeded range.
        this.publishCriteria({ immediate: true });
        this.loadFacets();
    }

    disconnectedCallback() {
        if (this.subscription) {
            unsubscribe(this.subscription);
            this.subscription = undefined;
        }
        if (this.publishTimer) {
            clearTimeout(this.publishTimer);
        }
        if (this.userSearchTimer) {
            clearTimeout(this.userSearchTimer);
        }
    }

    // ─────────────────────────── Dates ───────────────────────────

    initializeDates() {
        // If we restored a custom range, leave it. Otherwise seed the defaults
        // so switching to Custom starts with a sensible window.
        if (!this.customStart || !this.customEnd) {
            const { startDate, endDate } = this.computeRange(PRESET_LAST_30);
            this.customStart = this.toDateInputValue(startDate);
            this.customEnd = this.toDateInputValue(endDate);
        }
    }

    get presetOptions() {
        return [
            { label: PRESET_LABELS[PRESET_LAST_7], value: PRESET_LAST_7 },
            { label: PRESET_LABELS[PRESET_LAST_30], value: PRESET_LAST_30 },
            { label: PRESET_LABELS[PRESET_LAST_90], value: PRESET_LAST_90 },
            { label: PRESET_LABELS[PRESET_CUSTOM], value: PRESET_CUSTOM }
        ];
    }

    get isCustomRange() {
        return this.preset === PRESET_CUSTOM;
    }

    handlePresetChange(event) {
        this.preset = event.detail.value;
        this.dateError = undefined;
        if (this.preset !== PRESET_CUSTOM) {
            this.publishCriteria();
            this.loadFacets();
        }
    }

    handleCustomStartChange(event) {
        this.customStart = event.detail.value;
        this.maybeApplyCustomRange();
    }

    handleCustomEndChange(event) {
        this.customEnd = event.detail.value;
        this.maybeApplyCustomRange();
    }

    maybeApplyCustomRange() {
        if (!this.customStart || !this.customEnd) {
            return;
        }
        const start = new Date(this.customStart);
        const end = new Date(this.customEnd);
        if (Number.isNaN(start.getTime()) || Number.isNaN(end.getTime())) {
            this.dateError = 'Enter valid start and end dates.';
            return;
        }
        if (start > end) {
            this.dateError = 'Start date must be on or before end date.';
            return;
        }
        this.dateError = undefined;
        this.publishCriteria();
        this.loadFacets();
    }

    computeRange(preset) {
        const end = new Date();
        const start = new Date();
        let days = 30;
        if (preset === PRESET_LAST_7) days = 7;
        else if (preset === PRESET_LAST_90) days = 90;
        start.setDate(start.getDate() - days);
        return { startDate: start, endDate: end };
    }

    computeActiveRange() {
        if (this.preset === PRESET_CUSTOM && this.customStart && this.customEnd) {
            const start = new Date(this.customStart);
            start.setHours(0, 0, 0, 0);
            const end = new Date(this.customEnd);
            end.setHours(23, 59, 59, 999);
            return { startDate: start, endDate: end };
        }
        return this.computeRange(this.preset);
    }

    toDateInputValue(date) {
        const pad = (n) => String(n).padStart(2, '0');
        return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
    }

    // ─────────────────────────── Facets ───────────────────────────

    async loadFacets() {
        const range = this.computeActiveRange();
        // Key the load by the computed ISO range so rapid preset flips don't
        // double-fetch. If the user leaves the rail on the same preset the
        // facet list doesn't change — no need to re-call.
        const key = `${range.startDate.toISOString()}|${range.endDate.toISOString()}`;
        if (this.facetsLoadedForRange === key) return;
        this.facetsLoadedForRange = key;
        try {
            const facets = await getFilterFacets({
                startDate: range.startDate.toISOString(),
                endDate: range.endDate.toISOString(),
                topUserLimit: 100
            });
            this.facetModels = facets.models || [];
            this.facetProviders = facets.providers || [];
            this.facetFeatures = facets.features || [];
            this.facetAppTypes = facets.appTypes || [];
            this.facetPromptTemplates = facets.promptTemplates || [];
            this.facetTopUsers = facets.topUsers || [];
            // Backfill labels for previously-selected users so the rail keeps
            // displaying names even if they fall outside the new window.
            (this.facetTopUsers || []).forEach((o) => {
                if (o && o.value && o.label) {
                    this.selectedUserLabels[o.value] = o.label;
                }
            });
        } catch (err) {
            // On failure leave the lists empty — comboboxes show no options,
            // but existing selected pills still render from selectedUserLabels.
            this.facetModels = [];
            this.facetProviders = [];
            this.facetFeatures = [];
            this.facetAppTypes = [];
            this.facetPromptTemplates = [];
            this.facetTopUsers = [];
        }
    }

    // Each combobox needs { label, value }. Facets already have that shape.
    get modelOptions() {
        return this.facetModels.map((o) => ({ label: this.labelWithCount(o), value: o.value }));
    }
    get providerOptions() {
        return this.facetProviders.map((o) => ({ label: this.labelWithCount(o), value: o.value }));
    }
    get featureOptions() {
        return this.facetFeatures.map((o) => ({ label: this.labelWithCount(o), value: o.value }));
    }
    get appTypeOptions() {
        return this.facetAppTypes.map((o) => ({ label: this.labelWithCount(o), value: o.value }));
    }
    get promptTemplateOptions() {
        return this.facetPromptTemplates.map((o) => ({ label: this.labelWithCount(o), value: o.value }));
    }
    get topUserOptions() {
        return this.facetTopUsers.map((o) => ({ label: this.labelWithCount(o), value: o.value }));
    }

    labelWithCount(opt) {
        if (!opt) return '';
        const label = opt.label || opt.value;
        const count = opt.count != null ? ` (${opt.count})` : '';
        return `${label}${count}`;
    }

    // ───────────────────── Multi-select handlers ────────────────────

    handleMultiChange(event) {
        const dim = event.target.dataset.dim;
        // lightning-dual-listbox emits `value` as array.
        const values = Array.isArray(event.detail.value) ? event.detail.value : [];
        switch (dim) {
            case 'model':
                this.selectedModels = values;
                break;
            case 'provider':
                this.selectedProviders = values;
                break;
            case 'feature':
                this.selectedFeatures = values;
                break;
            case 'appType':
                this.selectedAppTypes = values;
                break;
            case 'promptTemplate':
                this.selectedPromptTemplateDevNames = values;
                break;
            case 'topUser':
                this.selectedUserIds = values;
                this.captureUserLabelsFromFacet(values);
                break;
            default:
                return;
        }
        this.publishCriteria();
    }

    captureUserLabelsFromFacet(userIds) {
        (this.facetTopUsers || []).forEach((o) => {
            if (o && userIds.includes(o.value)) {
                this.selectedUserLabels[o.value] = o.label || o.value;
            }
        });
    }

    // ─────────────────────── User typeahead ────────────────────────

    handleUserQueryChange(event) {
        this.userQuery = event.target.value || '';
        if (this.userSearchTimer) clearTimeout(this.userSearchTimer);
        if (this.userQuery.trim().length < USER_SEARCH_MIN_CHARS) {
            this.userSearchResults = [];
            return;
        }
        this.userSearchTimer = setTimeout(() => this.runUserSearch(), USER_SEARCH_DEBOUNCE_MS);
    }

    async runUserSearch() {
        const range = this.computeActiveRange();
        this.userSearchLoading = true;
        try {
            const results = await searchUsersInRange({
                term: this.userQuery,
                startDate: range.startDate.toISOString(),
                endDate: range.endDate.toISOString(),
                maxRows: 25
            });
            this.userSearchResults = results || [];
        } catch (err) {
            this.userSearchResults = [];
        } finally {
            this.userSearchLoading = false;
        }
    }

    handleUserSearchPick(event) {
        event.preventDefault();
        const userId = event.currentTarget.dataset.userId;
        const userLabel = event.currentTarget.dataset.userLabel;
        if (!userId || this.selectedUserIds.includes(userId)) {
            return;
        }
        this.selectedUserIds = [...this.selectedUserIds, userId];
        this.selectedUserLabels = { ...this.selectedUserLabels, [userId]: userLabel || userId };
        this.userQuery = '';
        this.userSearchResults = [];
        this.publishCriteria();
    }

    // ─────────────────────── Selected user pills ───────────────────

    get selectedUserPills() {
        return this.selectedUserIds.map((id) => ({
            value: id,
            label: this.selectedUserLabels[id] || id
        }));
    }

    handleRemoveUserPill(event) {
        const id = event.target.dataset.userId;
        this.selectedUserIds = this.selectedUserIds.filter((u) => u !== id);
        this.publishCriteria();
    }

    // ──────────────────────── Clear actions ────────────────────────

    handleClearDimension(event) {
        const dim = event.target.dataset.dim;
        switch (dim) {
            case 'model':
                this.selectedModels = [];
                break;
            case 'provider':
                this.selectedProviders = [];
                break;
            case 'feature':
                this.selectedFeatures = [];
                break;
            case 'appType':
                this.selectedAppTypes = [];
                break;
            case 'promptTemplate':
                this.selectedPromptTemplateDevNames = [];
                break;
            case 'user':
                this.selectedUserIds = [];
                break;
            default:
                return;
        }
        this.publishCriteria();
    }

    handleClearAll() {
        this.selectedUserIds = [];
        this.selectedPromptTemplateDevNames = [];
        this.selectedModels = [];
        this.selectedProviders = [];
        this.selectedFeatures = [];
        this.selectedAppTypes = [];
        this.publishCriteria();
    }

    // ────────────────────── Section toggles ────────────────────────

    handleToggleSection(event) {
        const section = event.currentTarget.dataset.section;
        this.collapsed = { ...this.collapsed, [section]: !this.collapsed[section] };
    }

    // ──────────────────── Rail expand/collapse ─────────────────────

    resolveExpandedForTab() {
        const tab = this._activeTab;
        // User's explicit choice on this tab wins over the default.
        if (tab && Object.prototype.hasOwnProperty.call(this._userExpandedByTab, tab)) {
            this.expanded = !!this._userExpandedByTab[tab];
            return;
        }
        // No tab context means the rail is rendered in its dedicated spot
        // (Explorer-only). Default to expanded.
        this.expanded = !tab || tab === EXPAND_BY_DEFAULT_TAB;
    }

    handleToggleRail() {
        this.expanded = !this.expanded;
        if (this._activeTab) {
            this._userExpandedByTab = {
                ...this._userExpandedByTab,
                [this._activeTab]: this.expanded
            };
            this.persistExpandedToStorage();
        }
        this.dispatchEvent(
            new CustomEvent('railtoggle', { detail: { expanded: this.expanded } })
        );
    }

    persistExpandedToStorage() {
        try {
            sessionStorage.setItem(STORAGE_KEY_EXPANDED, JSON.stringify(this._userExpandedByTab));
        } catch (err) {
            // Best-effort — sessionStorage can throw in private-browsing or
            // iframe contexts; the rail still functions without persistence.
        }
    }

    restoreExpandedFromStorage() {
        try {
            const raw = sessionStorage.getItem(STORAGE_KEY_EXPANDED);
            if (!raw) return;
            const parsed = JSON.parse(raw);
            if (parsed && typeof parsed === 'object') {
                this._userExpandedByTab = parsed;
            }
        } catch (err) {
            // Malformed data — ignore and start fresh.
        }
    }

    get railClass() {
        return this.expanded
            ? 'slds-filters fm-filter-rail'
            : 'slds-filters fm-filter-rail fm-filter-rail_collapsed';
    }

    get toggleIcon() {
        return this.expanded ? 'utility:chevronleft' : 'utility:chevronright';
    }

    get toggleAltText() {
        return this.expanded ? 'Collapse filters' : 'Expand filters';
    }

    get activeFilterCount() {
        return (
            this.selectedUserIds.length +
            this.selectedPromptTemplateDevNames.length +
            this.selectedModels.length +
            this.selectedProviders.length +
            this.selectedFeatures.length +
            this.selectedAppTypes.length
        );
    }

    get hasActiveFilters() {
        return this.activeFilterCount > 0;
    }

    get activeFilterCountAriaLabel() {
        const n = this.activeFilterCount;
        return `${n} ${n === 1 ? 'filter' : 'filters'} active`;
    }

    get sectionDateClass() {
        return this.collapsed.date ? 'fm-section fm-section--collapsed' : 'fm-section';
    }
    get sectionWhoClass() {
        return this.collapsed.who ? 'fm-section fm-section--collapsed' : 'fm-section';
    }
    get sectionWhatClass() {
        return this.collapsed.what ? 'fm-section fm-section--collapsed' : 'fm-section';
    }

    get sectionDateExpanded() {
        return !this.collapsed.date;
    }
    get sectionWhoExpanded() {
        return !this.collapsed.who;
    }
    get sectionWhatExpanded() {
        return !this.collapsed.what;
    }

    // ─────────────────────── Publish pipeline ──────────────────────

    publishCriteria(options) {
        const immediate = !!(options && options.immediate);
        if (this.publishTimer) clearTimeout(this.publishTimer);
        const fire = () => {
            const range = this.computeActiveRange();
            const startIso = range.startDate.toISOString();
            const endIso = range.endDate.toISOString();
            const criteria = {
                startDate: startIso,
                endDate: endIso,
                userIds: this.selectedUserIds.slice(),
                promptTemplateDevNames: this.selectedPromptTemplateDevNames.slice(),
                models: this.selectedModels.slice(),
                providers: this.selectedProviders.slice(),
                features: this.selectedFeatures.slice(),
                appTypes: this.selectedAppTypes.slice()
            };
            publish(this.messageContext, AI_INSIGHTS_FILTERS, {
                criteriaJson: JSON.stringify(criteria),
                startDate: startIso,
                endDate: endIso,
                presetLabel: PRESET_LABELS[this.preset]
            });
            // Keep legacy subscribers in sync — every existing dashboard still
            // listens on AiInsightsDateRange. Drop this publish once every
            // dashboard has migrated to AiInsightsFilters.
            publish(this.messageContext, AI_INSIGHTS_DATE_RANGE, {
                startDate: startIso,
                endDate: endIso,
                presetLabel: PRESET_LABELS[this.preset]
            });
            this.persistToStorage(criteria);
        };
        if (immediate) fire();
        else this.publishTimer = setTimeout(fire, PUBLISH_DEBOUNCE_MS);
    }

    handleExternalCriteria(msg) {
        // Respect external publishers (e.g. the filter pills component
        // removing a pill). If the payload doesn't include criteriaJson, skip.
        if (!msg || !msg.criteriaJson) return;
        let parsed;
        try {
            parsed = JSON.parse(msg.criteriaJson);
        } catch (err) {
            return;
        }
        // Avoid an echo loop: only hydrate state from external publishes that
        // materially differ from our current state. Cheap JSON compare is
        // enough here since both sides stringify.
        const current = {
            userIds: this.selectedUserIds,
            promptTemplateDevNames: this.selectedPromptTemplateDevNames,
            models: this.selectedModels,
            providers: this.selectedProviders,
            features: this.selectedFeatures,
            appTypes: this.selectedAppTypes
        };
        const incoming = {
            userIds: parsed.userIds || [],
            promptTemplateDevNames: parsed.promptTemplateDevNames || [],
            models: parsed.models || [],
            providers: parsed.providers || [],
            features: parsed.features || [],
            appTypes: parsed.appTypes || []
        };
        if (JSON.stringify(current) === JSON.stringify(incoming)) return;
        this.selectedUserIds = incoming.userIds;
        this.selectedPromptTemplateDevNames = incoming.promptTemplateDevNames;
        this.selectedModels = incoming.models;
        this.selectedProviders = incoming.providers;
        this.selectedFeatures = incoming.features;
        this.selectedAppTypes = incoming.appTypes;
    }

    // ─────────────────────── Persistence ───────────────────────────

    persistToStorage(criteria) {
        try {
            sessionStorage.setItem(
                STORAGE_KEY,
                JSON.stringify({
                    preset: this.preset,
                    customStart: this.customStart,
                    customEnd: this.customEnd,
                    ...criteria,
                    userLabels: this.selectedUserLabels
                })
            );
        } catch (err) {
            // sessionStorage can throw in some iframes / private browsing —
            // persistence is best-effort.
        }
    }

    restoreFromStorage() {
        try {
            const raw = sessionStorage.getItem(STORAGE_KEY);
            if (!raw) return;
            const parsed = JSON.parse(raw);
            if (parsed.preset) this.preset = parsed.preset;
            if (parsed.customStart) this.customStart = parsed.customStart;
            if (parsed.customEnd) this.customEnd = parsed.customEnd;
            this.selectedUserIds = parsed.userIds || [];
            this.selectedPromptTemplateDevNames = parsed.promptTemplateDevNames || [];
            this.selectedModels = parsed.models || [];
            this.selectedProviders = parsed.providers || [];
            this.selectedFeatures = parsed.features || [];
            this.selectedAppTypes = parsed.appTypes || [];
            this.selectedUserLabels = parsed.userLabels || {};
        } catch (err) {
            // Malformed session data — ignore and start fresh.
        }
    }

    // ───────────────────────── UI getters ──────────────────────────

    get hasAnyFilter() {
        return (
            this.selectedUserIds.length > 0 ||
            this.selectedPromptTemplateDevNames.length > 0 ||
            this.selectedModels.length > 0 ||
            this.selectedProviders.length > 0 ||
            this.selectedFeatures.length > 0 ||
            this.selectedAppTypes.length > 0
        );
    }

    get hasUserSearchResults() {
        return this.userSearchResults && this.userSearchResults.length > 0;
    }

    get userSearchResultsForRender() {
        return this.userSearchResults.map((r) => ({
            userId: r.value,
            label: r.label,
            detail: r.count != null ? `${r.count} requests` : ''
        }));
    }

    // ── Boolean getters for templates (LWC forbids .length in templates) ──
    get hasSelectedUserPills() {
        return this.selectedUserIds.length > 0;
    }
    get hasModelOptions() {
        return this.facetModels && this.facetModels.length > 0;
    }
    get hasProviderOptions() {
        return this.facetProviders && this.facetProviders.length > 0;
    }
    get hasFeatureOptions() {
        return this.facetFeatures && this.facetFeatures.length > 0;
    }
    get hasAppTypeOptions() {
        return this.facetAppTypes && this.facetAppTypes.length > 0;
    }
    get hasPromptTemplateOptions() {
        return this.facetPromptTemplates && this.facetPromptTemplates.length > 0;
    }
    get hasTopUserOptions() {
        return this.facetTopUsers && this.facetTopUsers.length > 0;
    }
}
