import { LightningElement, api, track } from 'lwc';
import initializeEligibility from '@salesforce/apex/EligibilityQuickActionController.initializeEligibility';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';

export default class EligibilityQuickAction extends LightningElement {
    @api recordId;
    @track isProcessing = false;

    handleCancel() {
        this.closeAndReload();
    }

    handleConfirm() {
        this.isProcessing = true;

        initializeEligibility({ recordId: this.recordId })
            .then(() => {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Eligibility Enabled',
                        message: 'Eligibility folder structure has been created for this Lead.',
                        variant: 'success'
                    })
                );
                this.closeAndReload();
            })
            .catch(error => {
                let message = 'Something went wrong while enabling eligibility.';
                if (error && error.body && error.body.message) {
                    message = error.body.message;
                }

                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error',
                        message,
                        variant: 'error'
                    })
                );
                this.isProcessing = false;
            });
    }

    closeAndReload() {
        this.dispatchEvent(new CloseActionScreenEvent());
        setTimeout(() => window.location.reload(), 800);
    }
}