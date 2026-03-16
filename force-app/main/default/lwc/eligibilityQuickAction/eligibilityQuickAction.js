import { LightningElement, api, track, wire } from 'lwc';
import initializeEligibility from '@salesforce/apex/EligibilityQuickActionController.initializeEligibility';
import getEligibilityStatus from '@salesforce/apex/EligibilityQuickActionController.getEligibilityStatus';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';

export default class EligibilityQuickAction extends LightningElement {
    @api recordId;
    @track isProcessing = false;
    @track eligibilityStatus;
    @track statusLoaded = false;

    @wire(getEligibilityStatus, { recordId: '$recordId' })
    wiredStatus({ data, error }) {
        this.statusLoaded = true;
        if (data !== undefined) {
            this.eligibilityStatus = data;
        } else if (error) {
            // eslint-disable-next-line no-console
            console.error(error);
            this.eligibilityStatus = null;
        }
    }

    get isAlreadyInitiated() {
        const status = (this.eligibilityStatus || '').toLowerCase();
        return status && status !== 'yet to initiate';
    }

    get isConfirmDisabled() {
        return this.isProcessing || !this.statusLoaded || this.isAlreadyInitiated;
    }

    handleCancel() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    handleConfirm() {
        if (this.isConfirmDisabled) {
            return;
        }
        this.isProcessing = true;

        initializeEligibility({ recordId: this.recordId })
            .then(() => {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Eligibility Enabled',
                        message: 'Eligibility folder structure has been created for this record.',
                        variant: 'success'
                    })
                );
                this.dispatchEvent(new CloseActionScreenEvent());
                setTimeout(() => {
                    window.location.reload();
                }, 500);
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
}