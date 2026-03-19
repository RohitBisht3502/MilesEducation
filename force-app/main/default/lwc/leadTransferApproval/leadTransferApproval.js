import { LightningElement, api, wire } from 'lwc';
import sendApproval from '@salesforce/apex/LeadTransferController.sendApproval';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import { getRecord } from 'lightning/uiRecordApi';
import USER_ID from '@salesforce/user/Id';

const FIELDS = ['Lead.OwnerId'];

export default class LeadTransferApproval extends LightningElement {

    @api recordId;
    comments = '';
    currentUserId = USER_ID;
    leadOwnerId;

    // 🔥 Fetch Lead Owner
    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredLead({ data, error }) {
        if (data) {
            this.leadOwnerId = data.fields.OwnerId.value;
        }
    }

    // 🔥 Disable condition
    get isSubmitDisabled() {
        return (
            !this.comments ||
            this.comments.trim().length === 0 ||
            this.leadOwnerId === this.currentUserId
        );
    }

    get isSameOwner() {
    return this.leadOwnerId === this.currentUserId;
}

    handleCommentChange(event) {
        this.comments = event.target.value;
    }

    handleSubmit() {
        sendApproval({ leadId: this.recordId, comments: this.comments })
            .then(() => {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Success',
                        message: 'Approval sent successfully',
                        variant: 'success'
                    })
                );

                this.dispatchEvent(new CloseActionScreenEvent());
            })
            .catch(error => {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error',
                        message: error.body.message,
                        variant: 'error'
                    })
                );
            });
    }

    handleCancel() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }
}