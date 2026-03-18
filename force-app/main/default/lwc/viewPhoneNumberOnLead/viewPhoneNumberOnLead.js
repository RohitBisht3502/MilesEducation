import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import checkUserCredit from '@salesforce/apex/ViewPhoneNumberController.checkUserCredit';
import getPhoneNumber from '@salesforce/apex/ViewPhoneNumberController.getPhoneNumber';

export default class ViewPhoneNumberOnLead extends LightningElement {
    @api recordId;
    @api objectApiName = 'Lead__c';
    @track email = '';
    @track creditBalance = 0;
    @track phoneNumber = '';
    @track isLoading = false;
    @track hasCredit = true;
    @track showCreditError = false;
    @track wireLoading = false;
    wiredCreditResult;

    @wire(checkUserCredit)
    wiredCreditData(result) {
        this.wiredCreditResult = result;
        const { error, data } = result;
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

                this.phoneNumber = result.phoneNumber;
                this.email = result.email;

                this.creditBalance = Math.floor(result.newCreditBalance);
                this.hasCredit = this.creditBalance > 0;
                this.showCreditError = !this.hasCredit;

                this.showSuccess('Success', 'Phone number retrieved successfully.');
                Promise.resolve(refreshApex(this.wiredCreditResult))
                    .finally(() => {
                        this.isLoading = false;
                    });
            })
            .catch(error => {
                console.error('Error getting phone:', error);
                console.error('Error details:', JSON.stringify(error, null, 2));

                let errorMessage = this.getErrorMessage(error);

                if (errorMessage.includes('Logging_Id__c')) {
                    errorMessage = 'Activity log creation failed. Please check field permissions.';
                }

                this.showError('Error', errorMessage);
                this.isLoading = false;
            });
    }

    handleCopy() {
        if (!this.phoneNumber) {
            return;
        }

        const textArea = document.createElement('textarea');
        textArea.value = this.phoneNumber;

        textArea.style.position = 'fixed';
        textArea.style.left = '-999999px';
        textArea.style.top = '-999999px';

        document.body.appendChild(textArea);
        textArea.focus();
        textArea.select();

        try {
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
            document.body.removeChild(textArea);
        }
    }

    handleCopyEmail() {
        if (!this.email) {
            return;
        }

        const textArea = document.createElement('textarea');
        textArea.value = this.email;

        textArea.style.position = 'fixed';
        textArea.style.left = '-999999px';

        document.body.appendChild(textArea);
        textArea.focus();
        textArea.select();

        try {
            const successful = document.execCommand('copy');

            if (successful) {
                this.showSuccess('Copied!', 'Email copied to clipboard');
            } else {
                this.showError('Copy Failed', 'Could not copy email');
            }
        } catch (err) {
            this.showError('Copy Failed', 'Could not copy email');
        }

        document.body.removeChild(textArea);
    }

    handleClose() {
        this.phoneNumber = '';
        this.email = '';

        setTimeout(() => {
            window.location.reload(true);
        }, 500);
    }

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

    selectEmailText(event) {
        const emailElement = this.template.querySelector('.email-value');

        if (emailElement) {
            const range = document.createRange();
            range.selectNodeContents(emailElement);

            const selection = window.getSelection();
            selection.removeAllRanges();
            selection.addRange(range);
        }
    }

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
        this.dispatchEvent(
            new ShowToastEvent({
                title: title,
                message: message,
                variant: 'success',
                mode: 'dismissable'
            })
        );
    }

    showError(title, message) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: title,
                message: message,
                variant: 'error',
                mode: 'sticky'
            })
        );
    }
}
