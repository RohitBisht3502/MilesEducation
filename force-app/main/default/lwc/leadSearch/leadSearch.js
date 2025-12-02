import { LightningElement, track } from 'lwc';
import searchLeadByPhone from '@salesforce/apex/LeadSearchController.searchLeadByPhone';
import submitApproval from '@salesforce/apex/LeadSearchController.submitApproval';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class LeadSearch extends LightningElement {
    phoneNumber = '';
    @track leadList = [];
    selectedLeadId = null;
    showMergeButton = false;

    handlePhoneChange(event) {
        this.phoneNumber = event.target.value;
    }

    handleSearch() {
        searchLeadByPhone({ phoneNumber: this.phoneNumber })
            .then(result => {
                this.leadList = result;
                this.selectedLeadId = null;
                this.showMergeButton = false;
            })
            .catch(error => {
                console.error(error);
                this.showToast('Error', 'Something went wrong', 'error');
            });
    }

    handleLeadSelection(event) {
        this.selectedLeadId = event.target.value;
        this.showMergeButton = true;
    }

    handleMergeLead() {
        if (!this.selectedLeadId) {
            return;
        }

        submitApproval({ leadId: this.selectedLeadId })
            .then(result => {
                this.showToast('Success', result, 'success');
            })
            .catch(error => {
                this.showToast('Error', error.body.message, 'error');
            });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({
            title,
            message,
            variant
        }));
    }
}