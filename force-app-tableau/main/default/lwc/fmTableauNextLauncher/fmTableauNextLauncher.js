import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getLauncherTarget from '@salesforce/apex/FmTableauNextController.getLauncherTarget';

export default class FmTableauNextLauncher extends NavigationMixin(LightningElement) {
    @api title = 'Explore in Tableau Next';
    @api subtitle = 'Drag-drop pivot freedom over your GenAI Audit data.';

    target;
    error;

    @wire(getLauncherTarget)
    handleTarget({ data, error }) {
        if (data) {
            this.target = data;
            this.error = undefined;
        } else if (error) {
            this.target = undefined;
            this.error = error.body && error.body.message ? error.body.message : 'Could not load launcher target.';
        }
    }

    get ready() {
        return !!this.target;
    }

    get errorMessage() {
        return this.error;
    }

    handleOpen() {
        if (!this.target || !this.target.workspacePath) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__webPage',
            attributes: { url: this.target.workspacePath }
        });
    }
}
