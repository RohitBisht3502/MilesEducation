import { LightningElement, api } from 'lwc';
import saveDownPayment from '@salesforce/apex/TransactionPaymentService.saveDownPayment';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import MINIMUM_DOWNPAYMENT from '@salesforce/label/c.Minimum_Downpayment';

export default class DownPaymentlwc extends LightningElement {

    @api recordId; // Purchase_Order__c Id
    downPayment;
    isSaving = false;

    handleDownPayment(event) {
        this.downPayment = parseFloat(event.target.value);
    }

    handleSave() {

        if (!this.downPayment || this.downPayment <= 0) {
            this.showToast('Error', 'Enter a valid down payment amount', 'error');
            return;
        }

        // ✅ Minimum down payment validation using Custom Label
        if (this.downPayment < parseFloat(MINIMUM_DOWNPAYMENT)) {
            this.showToast(
                'Error',
                `Minimum down payment should be ₹${MINIMUM_DOWNPAYMENT}`,
                'error'
            );
            return;
        }

        this.isSaving = true;

        saveDownPayment({
            purchaseOrderId: this.recordId,
            amount: this.downPayment
        })
        .then(() => {
            this.showToast('Success', 'Payment recorded successfully', 'success');
            this.dispatchEvent(new CloseActionScreenEvent());
            setTimeout(() => window.location.reload(), 500);
        })
        .catch(error => {
            this.showToast(
                'Error',
                error.body ? error.body.message : error.message,
                'error'
            );
        })
        .finally(() => {
            this.isSaving = false;
        });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }
}