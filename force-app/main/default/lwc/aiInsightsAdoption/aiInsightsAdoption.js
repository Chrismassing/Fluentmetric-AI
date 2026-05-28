import { LightningElement, wire } from 'lwc';
import { subscribe, unsubscribe, MessageContext } from 'lightning/messageService';
import AI_INSIGHTS_DATE_RANGE from '@salesforce/messageChannel/AiInsightsDateRange__c';
import getOverview from '@salesforce/apex/AiInsightsController.getOverview';
import getUsageByUser from '@salesforce/apex/AiInsightsController.getUsageByUser';
import getPowerUserSegments from '@salesforce/apex/AiInsightsController.getPowerUserSegments';
import { abbreviateNumber } from './numberFormat';
import { TOOLTIPS } from 'c/aiInsightsTooltips';
import FM_Adoption_Tab_Subhead from '@salesforce/label/c.FM_Adoption_Tab_Subhead';
import FM_Section_Adoption_Rate from '@salesforce/label/c.FM_Section_Adoption_Rate';
import FM_Section_Top_Contributors from '@salesforce/label/c.FM_Section_Top_Contributors';
import FM_Section_User_Adoption from '@salesforce/label/c.FM_Section_User_Adoption';
import FM_Section_Feature_Adoption from '@salesforce/label/c.FM_Section_Feature_Adoption';
import FM_Adoption_Pareto_Chip from '@salesforce/label/c.FM_Adoption_Pareto_Chip';
import FM_Adoption_Pareto_Suffix from '@salesforce/label/c.FM_Adoption_Pareto_Suffix';
import FM_Adoption_Entitled_Label from '@salesforce/label/c.FM_Adoption_Entitled_Label';
import FM_Adoption_Fallback_Label from '@salesforce/label/c.FM_Adoption_Fallback_Label';
import FM_Adoption_Fallback_Tip from '@salesforce/label/c.FM_Adoption_Fallback_Tip';

/**
 * Adoption tab container. Owns:
 *   - Adoption-rate chips (entitled denominator + Pareto + fallback tip)
 *   - Embedded adoption funnel
 *   - Top contributors leaderboard (sortable by tokens / requests)
 *   - Per-user adoption table (delegated to c-ai-insights-user-adoption,
 *     which itself includes the cohort heatmap)
 *   - Feature adoption breadth view (delegated to c-ai-insights-feature-adoption)
 *
 * Subscribes to AiInsightsDateRange so the rate chips and leaderboard
 * stay in sync with the global date filter.
 */
export default class AiInsightsAdoption extends LightningElement {
    @wire(MessageContext)
    messageContext;

    subscription;
    startDate = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString();
    endDate = new Date().toISOString();
    presetLabel;

    overview;
    topUsers = [];
    paretoSegments;
    isLoading = false;
    hasLoadedOnce = false;
    errorMessage;

    topUsersSort = 'tokens';
    topUsersLimit = 5;

    tooltips = TOOLTIPS.adoption;

    labels = {
        tabSubhead: FM_Adoption_Tab_Subhead,
        sectionRate: FM_Section_Adoption_Rate,
        sectionTopContributors: FM_Section_Top_Contributors,
        sectionUserAdoption: FM_Section_User_Adoption,
        sectionFeatureAdoption: FM_Section_Feature_Adoption,
        paretoPrefix: FM_Adoption_Pareto_Chip,
        paretoSuffix: FM_Adoption_Pareto_Suffix,
        entitledLabel: FM_Adoption_Entitled_Label,
        fallbackLabel: FM_Adoption_Fallback_Label,
        fallbackTip: FM_Adoption_Fallback_Tip
    };

    connectedCallback() {
        this.subscription = subscribe(
            this.messageContext,
            AI_INSIGHTS_DATE_RANGE,
            (message) => this.handleDateRange(message)
        );
        this.loadAdoption();
    }

    disconnectedCallback() {
        if (this.subscription) {
            unsubscribe(this.subscription);
            this.subscription = undefined;
        }
    }

    handleDateRange(message) {
        if (!message || !message.startDate || !message.endDate) {
            return;
        }
        this.startDate = message.startDate;
        this.endDate = message.endDate;
        this.presetLabel = message.presetLabel;
        this.loadAdoption();
    }

    async loadAdoption() {
        this.isLoading = true;
        this.errorMessage = undefined;
        try {
            const [result, usersResult, paretoResult] = await Promise.all([
                getOverview({ startDate: this.startDate, endDate: this.endDate }),
                getUsageByUser({ startDate: this.startDate, endDate: this.endDate }).catch(() => []),
                getPowerUserSegments({ startDate: this.startDate, endDate: this.endDate }).catch(() => null)
            ]);
            this.overview = result;
            this.topUsers = Array.isArray(usersResult) ? usersResult : [];
            this.paretoSegments = paretoResult;
            this.hasLoadedOnce = true;
        } catch (err) {
            this.errorMessage = this.extractError(err);
            this.overview = undefined;
            this.topUsers = [];
            this.paretoSegments = undefined;
        } finally {
            this.isLoading = false;
        }
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

    get showError() {
        return !!this.errorMessage;
    }

    // ───────── Adoption-rate chips ─────────

    get hasAdoptionData() {
        return !!(this.overview && (this.overview.entitledUserCount > 0 || this.overview.totalActiveOrgUsers > 0));
    }

    get adoptionRatePct() {
        const v = this.overview && this.overview.adoptionRate;
        if (v === null || v === undefined) return null;
        const n = Number(v);
        if (Number.isNaN(n)) return null;
        return Math.abs(n) <= 1 ? n * 100 : n;
    }

    get adoptionRateDisplay() {
        const pct = this.adoptionRatePct;
        if (pct === null) return '—';
        return `${pct.toFixed(1)}%`;
    }

    get adoptionDenominatorLabel() {
        if (!this.overview) return '';
        return this.overview.entitledFallback ? this.labels.fallbackLabel : this.labels.entitledLabel;
    }

    get adoptionDenominatorCount() {
        if (!this.overview) return 0;
        return this.overview.entitledFallback
            ? (this.overview.totalActiveOrgUsers || 0)
            : (this.overview.entitledUserCount || 0);
    }

    get adoptionFallbackTip() {
        return this.overview && this.overview.entitledFallback ? this.labels.fallbackTip : '';
    }

    get showAdoptionFallbackTip() {
        return !!(this.overview && this.overview.entitledFallback);
    }

    // ───────── Pareto chip ─────────

    get paretoSharePct() {
        const v = this.paretoSegments && this.paretoSegments.top10PercentVolumeShare;
        if (v === null || v === undefined) return null;
        const n = Number(v);
        if (Number.isNaN(n)) return null;
        return Math.abs(n) <= 1 ? n * 100 : n;
    }

    get paretoChipDisplay() {
        const pct = this.paretoSharePct;
        if (pct === null) return '';
        return `${this.labels.paretoPrefix} ${pct.toFixed(1)}% ${this.labels.paretoSuffix}`;
    }

    get hasParetoChip() {
        const pct = this.paretoSharePct;
        const users = this.paretoSegments && this.paretoSegments.top10PercentUserCount;
        return pct !== null && (users || 0) > 0;
    }

    // ───────── Top contributors leaderboard ─────────

    handleTopUsersSortToggle(event) {
        const value = event?.target?.dataset?.sort;
        if (value === 'tokens' || value === 'requests') {
            this.topUsersSort = value;
        }
    }

    get topUsersByRequestsActive() {
        return this.topUsersSort === 'requests';
    }
    get topUsersByTokensActive() {
        return this.topUsersSort === 'tokens';
    }
    get topUsersTokensClass() {
        return this.topUsersByTokensActive
            ? 'slds-button slds-button_brand'
            : 'slds-button slds-button_neutral';
    }
    get topUsersRequestsClass() {
        return this.topUsersByRequestsActive
            ? 'slds-button slds-button_brand'
            : 'slds-button slds-button_neutral';
    }

    get topUsersRows() {
        if (!Array.isArray(this.topUsers) || this.topUsers.length === 0) return [];
        const sortKey = this.topUsersSort === 'requests' ? 'requestCount' : 'totalTokens';
        const sorted = [...this.topUsers].sort(
            (a, b) => (Number(b?.[sortKey]) || 0) - (Number(a?.[sortKey]) || 0)
        );
        const max = Number(sorted[0]?.[sortKey]) || 0;
        return sorted.slice(0, this.topUsersLimit).map((row) => {
            const value = Number(row?.[sortKey]) || 0;
            const tokens = Number(row?.totalTokens) || 0;
            const requests = Number(row?.requestCount) || 0;
            const widthPct = max > 0 ? Math.max(2, Math.round((value / max) * 100)) : 0;
            return {
                userId: row?.userId || row?.userKey || row?.userName,
                userName: row?.userName || row?.userId || 'Unknown',
                requestCount: requests,
                totalTokens: tokens,
                primaryDisplay:
                    this.topUsersSort === 'requests' ? requests.toLocaleString() : abbreviateNumber(tokens),
                secondaryDisplay:
                    this.topUsersSort === 'requests' ? `${abbreviateNumber(tokens)} tokens` : `${requests.toLocaleString()} req`,
                barStyle: `width: ${widthPct}%`
            };
        });
    }

    get hasTopUsersRows() {
        return this.topUsersRows.length > 0;
    }
}
