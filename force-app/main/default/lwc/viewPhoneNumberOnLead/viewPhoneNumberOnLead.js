import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import checkUserCredit from '@salesforce/apex/ViewPhoneNumberController.checkUserCredit';
import getPhoneNumber from '@salesforce/apex/ViewPhoneNumberController.getPhoneNumber';

export default class ViewPhoneNumberOnLead extends LightningElement {
    @api recordId;
    @api objectApiName = 'Lead__c';
    
    @track creditBalance = 0;
    @track phoneNumber = '';
    @track isLoading = false;
    @track hasCredit = true;
    @track showCreditError = false;
    
    get isButtonDisabled() {
        return this.isLoading || !this.hasCredit;
    }
    
    connectedCallback() {
        this.checkCredit();
    }
    
    checkCredit() {
        this.isLoading = true;
        checkUserCredit()
            .then(result => {
                this.creditBalance = Math.floor(result.creditBalance);
                this.hasCredit = this.creditBalance > 0;
                this.showCreditError = !this.hasCredit;
                this.isLoading = false;
            })
            .catch(error => {
                console.error('Error checking credit:', error);
                this.showError('Error', error.body?.message || 'Failed to check credits');
                this.isLoading = false;
            });
    }
    
    handleViewPhone() {
        if (!this.hasCredit) {
            this.showError('Insufficient Credits', 'Please purchase more credits to view phone numbers');
            return;
        }
        
        this.isLoading = true;
        getPhoneNumber({
            recordId: this.recordId,
            objectApiName: this.objectApiName
        })
        .then(result => {
            this.phoneNumber = result;
            this.creditBalance -= 1;
            this.hasCredit = this.creditBalance > 0;
            this.showCreditError = !this.hasCredit;
            
            this.showSuccess('Success', 'Phone number retrieved');
            this.isLoading = false;
        })
        .catch(error => {
            console.error('Error getting phone:', error);
            this.showError('Error', error.body?.message || 'Failed to retrieve phone number');
            this.isLoading = false;
        });
    }
    
    handleCopy() {
        const tempInput = document.createElement('input');
        tempInput.value = this.phoneNumber;
        document.body.appendChild(tempInput);
        tempInput.select();
        document.execCommand('copy');
        document.body.removeChild(tempInput);
        
        this.showSuccess('Copied!', 'Phone number copied to clipboard');
    }
    
    handleClose() {
        this.phoneNumber = '';
    }
    
    showSuccess(title, message) {
        this.dispatchEvent(new ShowToastEvent({
            title, 
            message, 
            variant: 'success', 
            mode: 'dismissable'
        }));
    }
    
    showError(title, message) {
        this.dispatchEvent(new ShowToastEvent({
            title, 
            message, 
            variant: 'error', 
            mode: 'sticky'
        }));
    }
}