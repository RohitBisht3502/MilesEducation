import { LightningElement, wire, track } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';

import getActiveProducts from '@salesforce/apex/PurchaseOrderService.getActiveProducts';
import savePurchaseOrder from '@salesforce/apex/PurchaseOrderService.save';
import checkAddressByRecordId from '@salesforce/apex/PurchaseOrderService.checkAddressByRecordId';
import saveAddress from '@salesforce/apex/PurchaseOrderService.saveAddress';
import MINIMUM_DOWNPAYMENT from '@salesforce/label/c.Minimum_Downpayment';

export default class PurchaseOrderProductSelector extends LightningElement {
    @track products = [];
    searchKey = '';
    showCheckout = false;
    discountType = 'fixed';

    discountValue = 0;
    downPayment = 0;
    selectedAddressType = 'billing';
    recordId;
   @track sameAsBilling = true; 

    hasBillingAddress = false;
    hasShippingAddress = false;

    // Modal variables
    @track showAddressModal = false;
    @track missingAddressType = ''; 

    @wire(CurrentPageReference)
    getStateParameters(currentPageReference) {
        if (currentPageReference?.state) {
            this.recordId = currentPageReference.state.recordId;
        }
    }

    @wire(getActiveProducts, { recordId: '$recordId' })
    wiredProducts({ data, error }) {
        if (data) {
            this.products = data.map(p => ({
                id: p.id,
                name: p.name || '',
                sku: p.productCode || '',
                category: p.family || '',
                price: Number(p.unitPrice) || 0,
                type: p.type || '', 
                quantity: 1,
                selected: false
            }));
        } else if (error) {
            this.showToast('Error', error.body?.message || 'Failed to load products', 'error');
        }
    }
    get isBillingModal() {
    return this.missingAddressType === 'billing';
}

handleSameAsBilling(event) {
    this.sameAsBilling = event.target.checked;
}


    get addressOptions() {
        const options = [];
        if (this.hasBillingAddress) options.push({ label: 'Billing Address', value: 'billing' });
        if (this.hasShippingAddress) options.push({ label: 'Shipping Address', value: 'shipping' });
        return options;
    }

    get hasSelectedProducts() {
        return this.products.some(p => p.selected);
    }

    get disableCreatePurchase() {
        return !this.hasSelectedProducts;
    }

    get disableConfirmPurchase() {
        return !this.hasSelectedProducts;
    }

    get isPercentage() {
        return this.discountType === 'percentage';
    }

    get isFixed() {
        return this.discountType === 'fixed';
    }

    get filteredProducts() {
        if (!this.products.length) return [];
        if (!this.searchKey) return this.products;
        return this.products.filter(p =>
            (p.name || '').toLowerCase().includes(this.searchKey)
        );
    }

    get showProducts() {
        return this.filteredProducts.length > 0;
    }

    get selectedProducts() {
        return this.products
            .filter(p => p.selected)
            .map(p => ({ ...p, total: p.price }));
    }

    get cartCount() {
        return this.selectedProducts.length;
    }

    get subTotal() {
        return this.selectedProducts.reduce((sum, p) => sum + p.total, 0);
    }

    get discountLabel() {
        return this.discountType === 'percentage' ? 'Discount (%)' : 'Discount Amount (₹)';
    }

    get discountAmount() {
        if (this.subTotal <= 0) return 0;
        if (this.discountType === 'percentage') return Math.round((this.subTotal * Math.min(this.discountValue, 100)) / 100);
        return Math.min(this.discountValue, this.subTotal);
    }

    get finalPayable() {
        return Math.max(0, this.subTotal - this.discountAmount);
    }

get showShippingSection() {
    return !this.sameAsBilling;
}

get sameBillingBoxClass() {
    return `same-checkbox-card${this.sameAsBilling ? ' is-selected' : ''}`;
}

get shouldShowShippingFields() {
    return !this.isBillingModal || !this.sameAsBilling;
}

validateAddressFields(address, sectionLabel) {
    const required = ['street', 'city', 'state', 'postal', 'country'];
    for (const key of required) {
        const value = address[key];
        if (!value || !String(value).trim()) {
            const fieldLabel = key === 'postal'
                ? 'ZIP Code'
                : `${key.charAt(0).toUpperCase()}${key.slice(1)}`;
            this.showToast('Error', `${sectionLabel} ${fieldLabel} is mandatory.`, 'error');
            return false;
        }
    }
    return true;
}



    handleSearch(event) {
        this.searchKey = event.target.value?.toLowerCase() || '';
    }

    handleAddressChange(event) {
        this.selectedAddressType = event.detail.value;
    }

    addToCart(event) {
        const id = event.currentTarget.dataset.id;
        this.products = this.products.map(p => {
            if (String(p.id) === id) {
                return { ...p, selected: true };
            }
            return { ...p, selected: false, quantity: 1 };
        });
        this.syncDownPayment();
    }

    removeItem(event) {
        const id = event.currentTarget.dataset.id;
        this.products = this.products.map(p => (String(p.id) === id ? { ...p, selected: false, quantity: 1 } : p));
        this.syncDownPayment();
    }

    handleDiscountType(event) {
        const newType = event.target.value;
        const oldType = this.discountType;
        if (oldType === newType) return;

        let newValue = this.discountValue;

        if (this.subTotal > 0) {
            if (oldType === 'percentage' && newType === 'fixed') {
                newValue = Math.round((this.subTotal * Math.min(this.discountValue, 100)) / 100);
            }
            if (oldType === 'fixed' && newType === 'percentage') {
                newValue = Math.round((Math.min(this.discountValue, this.subTotal) / this.subTotal) * 100);
            }
        }

        this.discountType = newType;
        this.discountValue = newValue;
        this.syncDownPayment();
    }

    handleDiscountValue(event) {
        let value = Number(event.target.value) || 0;

        if (this.discountType === 'percentage') value = Math.min(value, 100);
        if (this.discountType === 'fixed') value = Math.min(value, this.subTotal);

        this.discountValue = value;
        this.syncDownPayment();
    }

    handleDownPaymentChange(event) {
        let value = Number(event.target.value) || 0;
        const max = this.finalPayable;

        if (value > max) {
            event.target.setCustomValidity('Down payment cannot exceed total payable.');
            event.target.reportValidity();
            value = max;
            event.target.setCustomValidity('');
        } else if (value < 0) {
            value = 0;
            event.target.setCustomValidity('Down payment cannot be negative.');
        } else {
            event.target.setCustomValidity('');
        }

        event.target.value = value;
        event.target.reportValidity();
        this.downPayment = value;
    }

    backToProducts() {
        this.showCheckout = false;
    }

    // ===== PROCEED TO CHECKOUT =====
    async proceedToCheckout() {
        if (!this.hasSelectedProducts) {
            this.showToast('Warning', 'Please select at least one product.', 'warning');
            return;
        }

        try {
            const addressStatus = await checkAddressByRecordId({ recordId: this.recordId });

            this.hasBillingAddress = addressStatus.hasBilling;
            this.hasShippingAddress = addressStatus.hasShipping;

            const hasStudyMaterial = this.selectedProducts.some(p => p.type === 'Study Material');

            // Billing missing
            if (!this.hasBillingAddress) {
                this.missingAddressType = 'billing';
                this.showAddressModal = true;
                this.sameAsBilling = true;

                return;
            }

            // Shipping missing (only for study material)
            if (hasStudyMaterial && !this.hasShippingAddress) {
                this.missingAddressType = 'shipping';
               
                return;
            }

            this.selectedAddressType = 'billing';
            this.showCheckout = true;
            this.sameAsBilling = false;


        } catch (error) {
            this.showToast('Error', error.body?.message || error.message, 'error');
        }
    }

    // ===== SAVE ADDRESS =====
 saveAddress() {

    const inputs = this.template.querySelectorAll('lightning-input[data-field]');
    const billing = {};
    const shipping = {};

    inputs.forEach(i => {
        const key = i.dataset.field;

        if (key.startsWith('billing_')) {
            billing[key.replace('billing_', '')] = i.value;
        }

        if (key.startsWith('shipping_')) {
            shipping[key.replace('shipping_', '')] = i.value;
        }
    });

    if (!this.validateAddressFields(billing, 'Billing')) {
        return;
    }

    if (this.shouldShowShippingFields && !this.validateAddressFields(shipping, 'Shipping')) {
        return;
    }

    // save billing first
    saveAddress({
        recordId: this.recordId,
        addressType: 'billing',
        address: billing
    })
    .then(async () => {

        // auto copy if same as billing
        if (this.sameAsBilling) {
            shipping.street  = billing.street;
            shipping.city    = billing.city;
            shipping.state   = billing.state;
            shipping.postal = billing.postal;
            shipping.country= billing.country;
        }

        // save shipping only if needed
        if (this.missingAddressType === 'shipping') {
            await saveAddress({
                recordId: this.recordId,
                addressType: 'shipping',
                address: shipping
            });
        }

        this.showAddressModal = false;
        this.sameAsBilling = false;

        this.proceedToCheckout();

    })
    .catch(err => {
        this.showToast('Error', err.body?.message || err.message, 'error');
    });
}


    confirmPurchase() {
        if (!this.hasSelectedProducts) {
            this.showToast('Warning', 'Please add at least one product before confirming.', 'warning');
            return;
        }

        if (this.downPayment > this.finalPayable) {
            this.showToast('Warning', 'Down payment cannot exceed total payable.', 'warning');
            return;
        }

        if (this.downPayment < parseFloat(MINIMUM_DOWNPAYMENT)) {
            this.showToast(
                'Error',
                `Minimum down payment should be ₹${MINIMUM_DOWNPAYMENT}`,
                'error'
            );
            return;
        }

        if (!this.recordId) {
            this.showToast('Error', 'Record Id not found.', 'error');
            return;
        }

        const payload = {
            leadId: this.recordId,
            discount: this.discountAmount,
            downPayment: this.downPayment,
            addressType: this.selectedAddressType,
            items: this.selectedProducts.map(p => ({
                productId: p.id,
                unitPrice: p.price,
                qty: 1,
                learningType: p.type
            }))
        };

        const requestJson = JSON.stringify(payload);

        savePurchaseOrder({ requestJson })
            .then(() => {
                this.showToast('Success', 'Purchase Order created successfully', 'success');
                this.dispatchEvent(new CloseActionScreenEvent());
                this.resetComponent();
            })
            .catch(error => {
                const msg = error.body?.message || error.message || 'Unexpected error';
                this.showToast('Error', msg, 'error');
                console.error('Purchase Order creation failed:', error);
            });
    }

    resetComponent() {
        this.showCheckout = false;
        this.products = this.products.map(p => ({ ...p, selected: false, quantity: 1 }));
        this.discountValue = 0;
        this.discountType = 'percentage';
        this.selectedAddressType = 'billing';
        this.downPayment = 0;
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    closeAddressModal() {
        this.showAddressModal = false;
    }

    syncDownPayment() {
        const max = this.finalPayable;
        const clamped = Math.min(Math.max(this.downPayment || 0, 0), max);
        if (clamped !== this.downPayment) {
            this.downPayment = clamped;
        }
        const input = this.template.querySelector('lightning-input[data-id="downPayment"]');
        if (input) {
            input.setCustomValidity('');
            input.value = clamped;
            input.reportValidity();
        }
    }
}