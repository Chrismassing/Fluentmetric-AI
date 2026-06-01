import { LightningElement, api, track } from 'lwc';
import parseRateCardUpload from '@salesforce/apex/AiInsightsController.parseRateCardUpload';
import applyRateCardUpload from '@salesforce/apex/AiInsightsController.applyRateCardUpload';
import USER_ID from '@salesforce/user/Id';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import FM_Cost_Upload_Rate_Card_Helper from '@salesforce/label/c.FM_Cost_Upload_Rate_Card_Helper';
import FM_Cost_Upload_Diff_Header from '@salesforce/label/c.FM_Cost_Upload_Diff_Header';
import FM_Cost_Upload_Confirm from '@salesforce/label/c.FM_Cost_Upload_Confirm';
import FM_Cost_Upload_Applied_Toast from '@salesforce/label/c.FM_Cost_Upload_Applied_Toast';

const STEP_UPLOAD = 'upload';
const STEP_REVIEW = 'review';
const STEP_DONE = 'done';

const FIELD_LABELS = {
    standard_action: 'Standard Action',
    custom_action: 'Custom Action',
    standard_voice_action: 'Standard Voice Action',
    custom_voice_action: 'Custom Voice Action',
    starter_prompt: 'Starter Prompt (BYOL)',
    basic_prompt: 'Basic Prompt',
    standard_prompt: 'Standard Prompt',
    advanced_prompt: 'Advanced Prompt'
};

/**
 * Modal-style admin tool: upload a Salesforce Flex Credits Rate Card PDF,
 * review the parsed multipliers diffed against current settings, and apply
 * to the org-default custom-setting record.
 *
 * Wired into aiInsightsCostAnalysis as a CTA on the fallback (non-Wallet)
 * cost tiles so admins of estimate-only orgs can refresh multipliers
 * without hopping to Setup.
 */
export default class AiInsightsRateCardUpload extends LightningElement {
    @api isOpen = false;

    @track step = STEP_UPLOAD;
    @track loading = false;
    @track errorMessage;

    @track contentVersionId;
    @track parsed;
    @track diffRows = [];
    @track parsedJson;
    @track notes = '';

    labels = {
        helper: FM_Cost_Upload_Rate_Card_Helper,
        diffHeader: FM_Cost_Upload_Diff_Header,
        confirm: FM_Cost_Upload_Confirm
    };

    // Scope ContentDocument upload to a record id. lightning-file-upload
    // requires one — current user is always a valid target.
    get recordId() {
        return USER_ID;
    }

    get acceptedFormats() {
        return ['.pdf'];
    }

    get isUploadStep() {
        return this.step === STEP_UPLOAD;
    }

    get isReviewStep() {
        return this.step === STEP_REVIEW;
    }

    get isDoneStep() {
        return this.step === STEP_DONE;
    }

    get hasError() {
        return !!this.errorMessage;
    }

    get hasChanges() {
        return this.diffRows.some((r) => r.willChange);
    }

    get effectiveDateDisplay() {
        return (this.parsed && this.parsed.effectiveDate) || 'unknown';
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
        this.resetState();
    }

    handleBackdropClick(event) {
        if (event.target.dataset.role === 'backdrop') {
            this.handleClose();
        }
    }

    handleModalClick(event) {
        event.stopPropagation();
    }

    handleNotesChange(event) {
        this.notes = event.target.value;
    }

    async handleUploadFinished(event) {
        const files = event.detail.files;
        if (!files || files.length === 0) {
            this.errorMessage = 'No file received';
            return;
        }
        this.contentVersionId = files[0].contentVersionId;
        this.errorMessage = undefined;
        this.loading = true;
        try {
            const result = await parseRateCardUpload({ contentVersionId: this.contentVersionId });
            this.parsed = result.parsed;
            this.parsedJson = JSON.stringify(result.parsed);
            this.diffRows = (result.diff || []).map((row) => ({
                ...row,
                labelDisplay: FIELD_LABELS[row.label] || row.label,
                changeClass: row.willChange ? 'fm-rcu-row fm-rcu-row_changed' : 'fm-rcu-row',
                currentDisplay: row.currentValue == null ? '—' : Number(row.currentValue).toString(),
                newDisplay: row.newValue == null ? '—' : Number(row.newValue).toString()
            }));
            this.step = STEP_REVIEW;
        } catch (err) {
            this.errorMessage = this.extractError(err);
        } finally {
            this.loading = false;
        }
    }

    async handleApply() {
        this.loading = true;
        this.errorMessage = undefined;
        try {
            await applyRateCardUpload({
                contentVersionId: this.contentVersionId,
                parsedJson: this.parsedJson,
                notes: this.notes
            });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Rate card applied',
                    message: FM_Cost_Upload_Applied_Toast,
                    variant: 'success'
                })
            );
            this.step = STEP_DONE;
            this.dispatchEvent(new CustomEvent('rateCardApplied'));
        } catch (err) {
            this.errorMessage = this.extractError(err);
        } finally {
            this.loading = false;
        }
    }

    handleStartOver() {
        this.resetState();
    }

    resetState() {
        this.step = STEP_UPLOAD;
        this.loading = false;
        this.errorMessage = undefined;
        this.contentVersionId = undefined;
        this.parsed = undefined;
        this.diffRows = [];
        this.parsedJson = undefined;
        this.notes = '';
    }

    extractError(err) {
        if (!err) return 'Unknown error';
        if (err.body && err.body.message) return err.body.message;
        if (typeof err === 'string') return err;
        return err.message || 'Unknown error';
    }
}
