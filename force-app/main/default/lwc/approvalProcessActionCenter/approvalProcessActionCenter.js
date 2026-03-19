import { LightningElement, api, wire, track } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import processApprovalResult from '@salesforce/apex/LeadMergeController.processApprovalResult';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import MERGE_STATUS_FIELD from '@salesforce/schema/Approval_Process__c.Merge_Status__c';
import APPROVER_FIELD from '@salesforce/schema/Approval_Process__c.Approver__c';
import APPROVER_NAME_FIELD from '@salesforce/schema/Approval_Process__c.Approver__r.Name';
import USER_ID from '@salesforce/user/Id';

export default class ApprovalProcessActionCenter extends NavigationMixin(LightningElement) {
    @api recordId;
    @track managerComments = '';
    @track isModalOpen = false;
    @track modalTitle = '';
    @track modalActionLabel = '';
    @track currentStatusAction = '';

    @wire(getRecord, { recordId: '$recordId', fields: [MERGE_STATUS_FIELD, APPROVER_FIELD, APPROVER_NAME_FIELD] })
    approvalRecord;

    get currentUserId() {
        return USER_ID;
    }

    get approverId() {
        return getFieldValue(this.approvalRecord.data, APPROVER_FIELD);
    }

    get approverName() {
        return getFieldValue(this.approvalRecord.data, APPROVER_NAME_FIELD);
    }

    get isUserApprover() {
        return this.currentUserId === this.approverId;
    }

    get currentStatus() {
        return getFieldValue(this.approvalRecord.data, MERGE_STATUS_FIELD);
    }

    get isPending() {
        return this.currentStatus === 'Pending';
    }

    get showActionButtons() {
        return this.isPending && this.isUserApprover;
    }

    handleCommentChange(event) {
        this.managerComments = event.target.value;
    }

    handleApproveAction() {
        this.modalTitle = 'Approve Merge Request';
        this.modalActionLabel = 'Approve';
        this.currentStatusAction = 'Approved';
        this.openModal();
    }

    handleRejectAction() {
        this.modalTitle = 'Reject Merge Request';
        this.modalActionLabel = 'Reject';
        this.currentStatusAction = 'Rejected';
        this.openModal();
    }

    openModal() {
        this.isModalOpen = true;
    }

    closeModal() {
        this.isModalOpen = false;
        this.managerComments = '';
    }

    handleSubmitAction() {
        if (!this.managerComments || this.managerComments.trim() === '') {
            this.showToast('Error', 'Comments are mandatory for finalized decisions.', 'error');
            return;
        }

        processApprovalResult({ 
            approvalId: this.recordId, 
            status: this.currentStatusAction, 
            managerComments: this.managerComments 
        })
        .then(() => {
            this.showToast('Success', `Merge Request ${this.currentStatusAction} successfully.`, 'success');
            this.closeModal();
            // Simple delay before refresh
            setTimeout(() => {
                location.reload();
            }, 500);
        })
        .catch(error => {
            const message = error.body?.message || error.message || 'An error occurred during processing.';
            this.showToast('Error', message, 'error');
        });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}