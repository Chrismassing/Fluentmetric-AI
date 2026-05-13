import { LightningElement, track } from 'lwc';

const GROUP_USERS = 'users';
const GROUP_PROMPTS = 'prompts';
const GROUP_TOKENS = 'tokens';

const STORAGE_KEY = 'fm.activity.groupBy';

/**
 * Activity tab host. Single segmented control swaps which child table is
 * shown — Users (per-user adoption), Prompts (per-prompt analytics), or
 * Tokens (group-by user/prompt/model/day).
 *
 * Each child component owns its own LMS subscription, datatable, and drill
 * panel — this host stays a thin chooser. The active view persists per
 * session so a tab switch returns to the user's last grouping.
 */
export default class AiInsightsActivity extends LightningElement {
    @track activeView = GROUP_USERS;

    connectedCallback() {
        try {
            const saved = sessionStorage.getItem(STORAGE_KEY);
            if (saved === GROUP_USERS || saved === GROUP_PROMPTS || saved === GROUP_TOKENS) {
                this.activeView = saved;
            }
        } catch (_) {
            // sessionStorage may be unavailable in some embeds — ignore.
        }
    }

    handleViewChange(event) {
        const next = event?.target?.dataset?.view;
        if (next === GROUP_USERS || next === GROUP_PROMPTS || next === GROUP_TOKENS) {
            this.activeView = next;
            try { sessionStorage.setItem(STORAGE_KEY, next); } catch (_) { /* ignore */ }
        }
    }

    get isUsers() {
        return this.activeView === GROUP_USERS;
    }
    get isPrompts() {
        return this.activeView === GROUP_PROMPTS;
    }
    get isTokens() {
        return this.activeView === GROUP_TOKENS;
    }

    get usersBtnClass() {
        return this.isUsers ? 'slds-button slds-button_brand' : 'slds-button slds-button_neutral';
    }
    get promptsBtnClass() {
        return this.isPrompts ? 'slds-button slds-button_brand' : 'slds-button slds-button_neutral';
    }
    get tokensBtnClass() {
        return this.isTokens ? 'slds-button slds-button_brand' : 'slds-button slds-button_neutral';
    }
}
