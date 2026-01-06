import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import checkUserCredit from '@salesforce/apex/ViewPhoneNumberController.checkUserCredit';
import getPhoneNumber from '@salesforce/apex/ViewPhoneNumberController.getPhoneNumber';

export default class ViewPhoneNumberOnLead extends LightningElement {
    @api recordId;
    @api objectApiName = 'Lead__c'; // Default value
    
    @track creditBalance = 0;
    @track phoneNumber = '';
    @track isLoading = false;
    @track hasCredit = true;
    @track showCreditError = false;
    @track wireLoading = false;
    
    // Wire method for instant credit data loading
    @wire(checkUserCredit)
    wiredCreditData({ error, data }) {
        this.wireLoading = true;
        
        if (data) {
            console.log('Wire data received:', data);
            this.creditBalance = Math.floor(data.creditBalance);
            this.hasCredit = this.creditBalance > 0;
            this.showCreditError = !this.hasCredit;
            this.wireLoading = false;
        } else if (error) {
            console.error('Wire error:', error);
            this.showError('Error Loading Credits', this.getErrorMessage(error));
            this.wireLoading = false;
            this.hasCredit = false;
            this.showCreditError = true;
        }
    }
    
    get isButtonDisabled() {
        return this.isLoading || !this.hasCredit || this.wireLoading;
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
            console.log('Phone result received:', result);
            
            // Set phone number
            this.phoneNumber = result.phoneNumber;
            
            // Update credit balance from server response
            this.creditBalance = Math.floor(result.newCreditBalance);
            this.hasCredit = this.creditBalance > 0;
            this.showCreditError = !this.hasCredit;
            
            this.showSuccess('Success', 'Phone number retrieved successfully.');
            this.isLoading = false;
        })
        .catch(error => {
            console.error('Error getting phone:', error);
            console.error('Error details:', JSON.stringify(error, null, 2));
            
            // Extract error message
            let errorMessage = this.getErrorMessage(error);
            
            // Check for specific errors
            if (errorMessage.includes('Logging_Id__c')) {
                errorMessage = 'Activity log creation failed. Please check field permissions.';
            }
            
            this.showError('Error', errorMessage);
            this.isLoading = false;
        });
    }
    
    handleCopy() {
        if (!this.phoneNumber) return;
        
        // Create temporary textarea for copying
        const textArea = document.createElement('textarea');
        textArea.value = this.phoneNumber;
        
        // Make it invisible
        textArea.style.position = 'fixed';
        textArea.style.left = '-999999px';
        textArea.style.top = '-999999px';
        
        document.body.appendChild(textArea);
        textArea.focus();
        textArea.select();
        
        try {
            // Try to copy
            const successful = document.execCommand('copy');
            if (successful) {
                this.showSuccess('Copied!', 'Phone number copied to clipboard');
            } else {
                this.showError('Copy Failed', 'Could not copy to clipboard');
            }
        } catch (err) {
            console.error('Copy error:', err);
            this.showError('Copy Failed', 'Could not copy to clipboard');
        } finally {
            // Clean up
            document.body.removeChild(textArea);
        }
    }
    
    handleClose() {
        this.phoneNumber = '';
    }
    
    // Select phone number text when clicked
    selectPhoneText(event) {
        if (event.target.classList.contains('phone-number-box')) {
            const phoneElement = this.template.querySelector('.phone-number');
            if (phoneElement) {
                const range = document.createRange();
                range.selectNodeContents(phoneElement);
                const selection = window.getSelection();
                selection.removeAllRanges();
                selection.addRange(range);
            }
        }
    }
    
    // Helper to get error message from different error formats
    getErrorMessage(error) {
        if (error && error.body) {
            if (error.body.message) {
                return error.body.message;
            }
            if (typeof error.body === 'string') {
                return error.body;
            }
        }
        if (error && error.message) {
            return error.message;
        }
        if (typeof error === 'string') {
            return error;
        }
        return 'An unexpected error occurred';
    }
    
    showSuccess(title, message) {
        this.dispatchEvent(new ShowToastEvent({
            title: title, 
            message: message, 
            variant: 'success', 
            mode: 'dismissable'
        }));
    }
    
    showError(title, message) {
        this.dispatchEvent(new ShowToastEvent({
            title: title, 
            message: message, 
            variant: 'error', 
            mode: 'sticky'
        }));
    }
}