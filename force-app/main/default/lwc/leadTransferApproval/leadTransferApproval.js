import { LightningElement, api, wire } from 'lwc';
import sendApproval from '@salesforce/apex/LeadTransferController.sendApproval';
import getUserAccessInfo from '@salesforce/apex/LeadTransferController.getUserAccessInfo';
import getTransferValidationInfo from '@salesforce/apex/LeadTransferController.getTransferValidationInfo';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import { getRecord } from 'lightning/uiRecordApi';
import USER_ID from '@salesforce/user/Id';

const FIELDS = ['Lead.OwnerId'];

export default class LeadTransferApproval extends LightningElement {

    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        this._recordId = value;
        if (value) {
            this.loadValidation();
        }
    }
    _recordId;
    comments = '';
    currentUserId = USER_ID;
    leadOwnerId;
    accessInfo;
    validationInfo;

    connectedCallback() {
        this.loadAccess();
    }

    loadAccess() {
        getUserAccessInfo()
            .then(result => {
                this.accessInfo = result;
            })
            .catch(error => {
                this.accessInfo = {
                    hasAccess: false,
                    message: error.body?.message || error.message || 'You do not have access.'
                };
            });
    }

    loadValidation() {
        if (!this._recordId) {
            return;
        }

        getTransferValidationInfo({ leadId: this._recordId })
            .then(result => {
                this.validationInfo = result;
            })
            .catch(error => {
                this.validationInfo = {
                    hasPendingRequest: false,
                    message: error.body?.message || error.message
                };
            });
    }

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
            !this.isAuthorized ||
            this.hasPendingRequest ||
            !this.comments ||
            this.comments.trim().length === 0 ||
            this.leadOwnerId === this.currentUserId
        );
    }

    get isSameOwner() {
        return this.leadOwnerId === this.currentUserId;
    }

    get showCommentBox() {
        return !this.showAccessDenied && !this.isSameOwner && !this.hasPendingRequest;
    }

    handleCommentChange(event) {
        this.comments = event.target.value;
    }

    handleSubmit() {
        if (!this.isAuthorized) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: this.accessMessage,
                    variant: 'error'
                })
            );
            return;
        }

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

    get isAuthorized() {
        return this.accessInfo?.hasAccess === true;
    }

    get showAccessDenied() {
        return this.accessInfo?.hasAccess === false;
    }

    get accessMessage() {
        return this.accessInfo?.message || 'You do not have access. Only CC and SR users can transfer leads.';
    }

    get hasPendingRequest() {
        return this.validationInfo?.hasPendingRequest === true;
    }

    get pendingMessage() {
        return this.validationInfo?.message || 'One process already exists for this lead transfer.';
    }
}