import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getLauncherTarget from '@salesforce/apex/FmTableauNextController.getLauncherTarget';
import CARD_TITLE from '@salesforce/label/c.FM_TBL_Launcher_Card_Title';
import CARD_SUBTITLE from '@salesforce/label/c.FM_TBL_Launcher_Card_Subtitle';
import LAUNCHER_ERROR from '@salesforce/label/c.FM_TBL_Launcher_Error';

export default class FmTableauNextLauncher extends NavigationMixin(LightningElement) {
    @api title = CARD_TITLE;
    @api subtitle = CARD_SUBTITLE;

    target;
    error;

    @wire(getLauncherTarget)
    handleTarget({ data, error }) {
        if (data) {
            this.target = data;
            this.error = undefined;
        } else if (error) {
            this.target = undefined;
            this.error = error.body && error.body.message ? error.body.message : LAUNCHER_ERROR;
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
