import { LightningElement, wire, track } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';

import getActiveProducts from '@salesforce/apex/PurchaseOrderService.getActiveProducts';
import savePurchaseOrder from '@salesforce/apex/PurchaseOrderService.save';
import checkAddressByRecordId from '@salesforce/apex/PurchaseOrderService.checkAddressByRecordId';
import saveAddress from '@salesforce/apex/PurchaseOrderService.saveAddress';

export default class PurchaseOrderProductSelector extends LightningElement {
    @track products = [];
    searchKey = '';
    showCheckout = false;
    discountType = 'percentage';
    discountValue = 0;
    selectedAddressType = 'billing';
    recordId;
    showProducts = false;

    hasBillingAddress = false;
    hasShippingAddress = false;

    // Modal variables
    @track showAddressModal = false;
    @track missingAddressType = ''; // 'billing' | 'shipping'

    @wire(CurrentPageReference)
    getStateParameters(currentPageReference) {
        if (currentPageReference?.state) {
            this.recordId = currentPageReference.state.recordId;
        }
    }

    @wire(getActiveProducts)
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
        if (!this.showProducts) return [];
        return this.products.filter(p =>
            (p.name || '').toLowerCase().includes(this.searchKey)
        );
    }

    get selectedProducts() {
        return this.products
            .filter(p => p.selected)
            .map(p => ({ ...p, total: p.price * p.quantity }));
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

    handleSearch(event) {
        this.searchKey = event.target.value?.toLowerCase() || '';
        this.showProducts = this.searchKey.length > 0;
    }

    handleAddressChange(event) {
        this.selectedAddressType = event.detail.value;
    }

    addToCart(event) {
        const id = event.currentTarget.dataset.id;
        this.products = this.products.map(p => (String(p.id) === id ? { ...p, selected: true } : p));
    }

    updateQty(event) {
        const { id, action } = event.currentTarget.dataset;
        this.products = this.products.map(p => {
            if (String(p.id) === id) {
                const qty = action === 'inc' ? p.quantity + 1 : Math.max(1, p.quantity - 1);
                return { ...p, quantity: qty };
            }
            return p;
        });
    }

    removeItem(event) {
        const id = event.currentTarget.dataset.id;
        this.products = this.products.map(p => (String(p.id) === id ? { ...p, selected: false, quantity: 1 } : p));
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
    }

    handleDiscountValue(event) {
        let value = Number(event.target.value) || 0;

        if (this.discountType === 'percentage') value = Math.min(value, 100);
        if (this.discountType === 'fixed') value = Math.min(value, this.subTotal);

        this.discountValue = value;
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
                return;
            }

            // Shipping missing (only for study material)
            if (hasStudyMaterial && !this.hasShippingAddress) {
                this.missingAddressType = 'shipping';
                this.showAddressModal = true;
                return;
            }

            this.selectedAddressType = 'billing';
            this.showCheckout = true;

        } catch (error) {
            this.showToast('Error', error.body?.message || error.message, 'error');
        }
    }

    // ===== SAVE ADDRESS =====
    saveAddress() {
        const inputs = this.template.querySelectorAll('lightning-input');
        const address = {};

        inputs.forEach(i => {
            address[i.dataset.field] = i.value;
        });

        saveAddress({
            recordId: this.recordId,
            addressType: this.missingAddressType,
            address
        })
            .then(() => {
                this.showToast('Success', 'Address saved successfully', 'success');
                this.showAddressModal = false;

                // Continue checkout automatically after saving
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

        if (!this.recordId) {
            this.showToast('Error', 'Record Id not found.', 'error');
            return;
        }

        const payload = {
            leadId: this.recordId,
            discount: this.discountAmount,
            addressType: this.selectedAddressType,
            items: this.selectedProducts.map(p => ({
                productId: p.id,
                unitPrice: p.price,
                qty: p.quantity,
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
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    closeAddressModal() {
        this.showAddressModal = false;
    }
}