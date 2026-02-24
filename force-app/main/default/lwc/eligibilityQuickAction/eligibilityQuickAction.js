import { LightningElement, api, wire } from 'lwc';
import initializeEligibility from '@salesforce/apex/EligibilityQuickActionController.initializeEligibility';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import GP_LEAD_STATUS_FIELD from '@salesforce/schema/Lead.GP_Lead_Status__c';

export default class EligibilityQuickAction extends LightningElement {
    @api recordId;
    isProcessing = false;

    @wire(getRecord, { recordId: '$recordId', fields: [GP_LEAD_STATUS_FIELD] })
    lead;

    get isConfirmDisabled() {
        const status = getFieldValue(this.lead.data, GP_LEAD_STATUS_FIELD);
        return this.isProcessing || (status && status !== 'Yet to Initiate');
    }

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