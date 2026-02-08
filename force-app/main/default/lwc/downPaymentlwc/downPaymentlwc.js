import { LightningElement, api } from 'lwc';
import saveDownPayment from '@salesforce/apex/TransactionPaymentService.saveDownPayment';
import getPaymentContext from '@salesforce/apex/TransactionPaymentService.getPaymentContext';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import MINIMUM_DOWNPAYMENT from '@salesforce/label/c.Minimum_Downpayment';

export default class DownPaymentlwc extends LightningElement {

    _recordId;
    downPayment;
    remainingAmount = 0;
    transactions = [];
    isSaving = false;

    @api
    get recordId() {
        return this._recordId;
    }

    set recordId(value) {
        this._recordId = value;
        if (this._recordId) {
            this.loadPaymentContext();
        }
    }

    get hasTransactions() {
        return this.transactions && this.transactions.length > 0;
    }

    handleDownPayment(event) {
        this.downPayment = parseFloat(event.target.value);
    }

    loadPaymentContext() {
        if (!this.recordId) {
            return;
        }

        getPaymentContext({ purchaseOrderId: this.recordId })
            .then((result) => {
                this.remainingAmount = result?.remainingAmount || 0;
                this.transactions = (result?.transactions || []).map((txn, index) => ({
                    ...txn,
                    key: `${index}-${txn.payment || 0}-${txn.status || ''}`
                }));
            })
            .catch((error) => {
                this.showToast(
                    'Error',
                    error.body ? error.body.message : error.message,
                    'error'
                );
            });
    }

    handleSave() {
        if (!this.recordId) {
            this.showToast('Error', 'Purchase Order context not found.', 'error');
            return;
        }

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

        if (this.downPayment > this.remainingAmount) {
            this.showToast(
                'Error',
                `Payment cannot be greater than remaining amount (₹${this.remainingAmount}).`,
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