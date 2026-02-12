import { LightningElement, wire, track } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';

import getActiveProducts from '@salesforce/apex/PurchaseOrderService.getActiveProducts';
import savePurchaseOrder from '@salesforce/apex/PurchaseOrderService.save';
import checkAddressByRecordId from '@salesforce/apex/PurchaseOrderService.checkAddressByRecordId';
import saveAddress from '@salesforce/apex/PurchaseOrderService.saveAddress';
import getMinimumDownPayment from '@salesforce/apex/PurchaseOrderService.getMinimumDownPayment';
import MINIMUM_DOWNPAYMENT from '@salesforce/label/c.Minimum_Downpayment';

const MAX_DISCOUNT_PERCENT = 5;

export default class PurchaseOrderProductSelector extends LightningElement {
    @track products = [];
    searchKey = '';
    showCheckout = false;
    discountType = 'fixed';

    discountValue = 0;
    downPayment = 0;
    selectedAddressType = 'billing';
    recordId;
    @track sameAsBilling = false;
    minimumDownPayment = 0;
    shippingPhone = '';

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

    @wire(getMinimumDownPayment, { recordId: '$recordId' })
    wiredMinimumDownPayment({ data, error }) {
        if (data !== undefined && data !== null) {
            this.minimumDownPayment = Number(data) || 0;
        } else if (error) {
            this.minimumDownPayment = Number(MINIMUM_DOWNPAYMENT) || 0;
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

get downPaymentMinMessage() {
    if (this.minimumDownPayment > 0) {
        return `Minimum down payment should be ₹${this.minimumDownPayment}`;
    }
    return 'Down payment cannot be negative.';
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
        const value = Number(event.target.value) || 0;
        this.discountValue = value;
        this.validateDiscount(event.target);
        this.syncDownPayment();
    }
    handleDownPaymentChange(event) {
        const value = Number(event.target.value) || 0;
        this.validateDownPayment(event.target, value);
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
                this.sameAsBilling = false;

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

    if (!shipping.phone || !String(shipping.phone).trim()) {
        this.showToast('Error', 'Shipping Phone Number is mandatory.', 'error');
        return;
    }

    if (this.shouldShowShippingFields && !this.validateAddressFields(shipping, 'Shipping')) {
        return;
    }

    this.shippingPhone = shipping.phone;

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

        if (!this.validateDiscount()) {
            this.showToast('Error', 'Please correct the discount value.', 'error');
            return;
        }

        if (!this.validateDownPayment()) {
            this.showToast('Error', 'Please correct the down payment value.', 'error');
            return;
        }

        if (this.downPayment > this.finalPayable) {
            this.showToast('Warning', 'Down payment cannot exceed total payable.', 'warning');
            return;
        }

        if (this.downPayment < Number(this.minimumDownPayment || 0)) {
            this.showToast(
                'Error',
                `Minimum down payment should be ₹${this.minimumDownPayment || 0}`,
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
            phoneNumber: this.shippingPhone,
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
        this.minimumDownPayment = 0;
        this.shippingPhone = '';
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    closeAddressModal() {
        this.showAddressModal = false;
    }
    validateDiscount(inputEl) {
        const input = inputEl || this.template.querySelector('lightning-input[data-id="discount"]');
        if (!input) return true;

        const value = Number(this.discountValue) || 0;
        let message = '';

        if (this.discountType === 'percentage') {
            if (value < 0 || value > MAX_DISCOUNT_PERCENT) {
                message = `Discount must be between 0% and ${MAX_DISCOUNT_PERCENT}%`;
            }
        } else {
            const maxFixed = Math.round((this.subTotal * MAX_DISCOUNT_PERCENT) / 100);
            if (value < 0 || value > maxFixed) {
                message = `Discount must be between â‚¹0 and â‚¹${maxFixed}`;
            } else if (value > this.subTotal) {
                message = 'Discount cannot exceed total amount.';
            }
        }

        input.setCustomValidity(message);
        input.reportValidity();
        return !message;
    }
    validateDownPayment(inputEl, rawValue) {
        const input = inputEl || this.template.querySelector('lightning-input[data-id="downPayment"]');
        if (!input) return true;

        const value = rawValue !== undefined ? rawValue : Number(this.downPayment) || 0;
        const min = Math.max(0, Number(this.minimumDownPayment) || 0);
        let message = '';

        if (value < min) {
            message = `Minimum down payment should be â‚¹${min}`;
        } else if (value > this.finalPayable) {
            message = 'Down payment cannot exceed total payable.';
        }

        input.setCustomValidity(message);
        input.reportValidity();
        return !message;
    }
    syncDownPayment() {
        const input = this.template.querySelector('lightning-input[data-id="downPayment"]');
        if (input) {
            this.validateDownPayment(input);
        }
    }
}