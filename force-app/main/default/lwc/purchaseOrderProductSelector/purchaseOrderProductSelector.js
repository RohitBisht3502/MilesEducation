import { LightningElement, wire, track } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import { NavigationMixin } from 'lightning/navigation';

import getActiveProducts from '@salesforce/apex/PurchaseOrderService.getActiveProducts';
import savePurchaseOrder from '@salesforce/apex/PurchaseOrderService.save';
import checkAddressByRecordId from '@salesforce/apex/PurchaseOrderService.checkAddressByRecordId';
import saveAddress from '@salesforce/apex/PurchaseOrderService.saveAddress';
import getAddressByRecordId from '@salesforce/apex/PurchaseOrderService.getAddressByRecordId';
import getMinimumDownPayment from '@salesforce/apex/PurchaseOrderService.getMinimumDownPayment';
import getDiscountThreshold from '@salesforce/apex/PurchaseOrderService.getDiscountThreshold';
import getLoansForLead from '@salesforce/apex/PurchaseOrderService.getLoansForLead';

import MINIMUM_DOWNPAYMENT from '@salesforce/label/c.Minimum_Downpayment';

const MAX_DISCOUNT_PERCENT = 100;
const DEFAULT_COUNTRY = 'India';

export default class PurchaseOrderProductSelector extends NavigationMixin(LightningElement) {
    @track products = [];
    @track loans = [];
    @track sameAsBilling = false;
    @track addressData = {
        billing: { country: DEFAULT_COUNTRY },
        shipping: { country: DEFAULT_COUNTRY }
    };
    @track showAddressModal = false;
    @track missingAddressType = '';

    selectedLoanId = null;
    searchKey = '';
    showCheckout = false;
    discountType = 'fixed';
    wiredProductsResult;
    discountValue = 0;
    downPayment = 0;
    selectedAddressType = 'billing';
    recordId;
    minimumDownPayment = 0;
    discountThreshold = 0;
    approvalComments = '';
    shippingPhone = '';

    hasBillingAddress = false;
    hasShippingAddress = false;

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

    @wire(getDiscountThreshold, { recordId: '$recordId' })
    wiredDiscountThreshold({ data, error }) {
        if (data !== undefined && data !== null) {
            this.discountThreshold = Number(data) || 0;
        } else if (error) {
            this.discountThreshold = 0;
        }
    }

    @wire(getActiveProducts, { recordId: '$recordId' })
    wiredProducts(result) {
        this.wiredProductsResult = result;
        const { data, error } = result;

        if (data) {
            this.products = data.map((p) => ({
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

    get currentAddressLabel() {
        return this.selectedAddressType === 'shipping' ? 'Shipping Address' : 'Billing Address';
    }

    get hasSelectedProducts() {
        return this.products.some((p) => p.selected);
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

        return this.products.filter((p) =>
            (p.name || '').toLowerCase().includes(this.searchKey)
        );
    }

    get showProducts() {
        return this.filteredProducts.length > 0;
    }

    get selectedProducts() {
        return this.products
            .filter((p) => p.selected)
            .map((p) => ({ ...p, total: p.price }));
    }

    get hasStudyMaterial() {
        return this.selectedProducts.some((p) => p.type === 'Study Material');
    }

    get cartCount() {
        return this.selectedProducts.length;
    }

    get hasLoans() {
        return this.loans && this.loans.length > 0;
    }

    get processingFee() {
        const tenureMonths = this.getSelectedLoanTenureMonths();
        if (tenureMonths === 6) return 2500;
        if (tenureMonths === 12) return 5000;
        return 0;
    }

    get effectiveMinimumDownPayment() {
        return Math.max(0, Number(this.minimumDownPayment) || 0) + (Number(this.processingFee) || 0);
    }

    get processingFeeMessage() {
        const fee = this.processingFee;
        if (!fee) return '';
        return `Processing fee â‚¹${fee} applied.`;
    }

    get totalDownPayment() {
        return (Number(this.downPayment) || 0) + (Number(this.processingFee) || 0);
    }

    get formattedLoans() {
        return this.loans.map((l) => ({
            ...l,
            className: `loan-card${this.selectedLoanId === l.id ? ' selected' : ''}`,
            isSelected: this.selectedLoanId === l.id
        }));
    }

    get subTotal() {
        return this.selectedProducts.reduce((sum, p) => sum + p.total, 0);
    }

    get discountLabel() {
        return this.discountType === 'percentage' ? 'Discount (%)' : 'Discount Amount (₹)';
    }

    get discountAmount() {
        if (this.subTotal <= 0) return 0;

        if (this.discountType === 'percentage') {
            return Math.round((this.subTotal * Math.min(this.discountValue, 100)) / 100);
        }

        return Math.min(this.discountValue, this.subTotal);
    }

    get discountPercent() {
        if (this.subTotal <= 0) return 0;
        return Math.round(((this.discountAmount / this.subTotal) * 100) * 100) / 100;
    }

    get isApprovalRequired() {
        if (!this.discountThreshold || this.discountThreshold <= 0) return false;
        return this.discountPercent > this.discountThreshold;
    }

    get confirmButtonLabel() {
        return this.isApprovalRequired ? 'Submit for Approval' : 'Confirm Purchase';
    }

    get approvalHint() {
        if (this.discountThreshold && this.discountThreshold > 0) {
            return `Approval required when discount > ${this.discountThreshold}% (current ${this.discountPercent}%).`;
        }
        return 'Approval threshold not set for this course.';
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
        if (this.effectiveMinimumDownPayment > 0) {
            return `Minimum down payment should be Rs ${this.effectiveMinimumDownPayment}`;
            return `Minimum down payment should be ₹${this.minimumDownPayment}`;
        }
        return 'Down payment cannot be negative.';
    }

    validateAddressFields(address, sectionLabel) {
        const required = ['street', 'city', 'state', 'postal', 'country'];

        for (const key of required) {
            const value = address[key];
            if (!value || !String(value).trim()) {
                const fieldLabel =
                    key === 'postal'
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

    normalizeAddress(address = {}) {
        return {
            street: address.street || '',
            city: address.city || '',
            state: address.state || '',
            postal: address.postal || '',
            country: address.country || DEFAULT_COUNTRY
        };
    }

    ensureDefaultCountries() {
        this.addressData = {
            billing: {
                ...this.addressData.billing,
                country: this.addressData.billing?.country || DEFAULT_COUNTRY
            },
            shipping: {
                ...this.addressData.shipping,
                country: this.addressData.shipping?.country || DEFAULT_COUNTRY
            }
        };
    }

    handleLoanSelect(event) {
        this.selectedLoanId = event.target.value;
        this.syncDownPayment();
    }

    addToCart(event) {
        const id = event.currentTarget.dataset.id;

        this.products = this.products.map((p) => {
            if (String(p.id) === id) {
                return { ...p, selected: true };
            }
            return { ...p, selected: false, quantity: 1 };
        });

        this.syncDownPayment();
    }

    removeItem(event) {
        const id = event.currentTarget.dataset.id;
        this.products = this.products.map((p) =>
            String(p.id) === id ? { ...p, selected: false, quantity: 1 } : p
        );
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
                newValue = Math.round(
                    (Math.min(this.discountValue, this.subTotal) / this.subTotal) * 100
                );
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

    handleApprovalComments(event) {
        this.approvalComments = event.target.value || '';
    }

    handleDownPaymentChange(event) {
        const value = Number(event.target.value) || 0;
        this.validateDownPayment(event.target, value);
        this.downPayment = value;
    }

    backToProducts() {
        this.showCheckout = false;
    }

    async proceedToCheckout() {
        if (!this.hasSelectedProducts) {
            this.showToast('Warning', 'Please select at least one product.', 'warning');
            return;
        }

        try {
            const loans = await getLoansForLead({ recordId: this.recordId });
            this.loans = loans.map((l) => ({
                id: l.Id,
                name: l.Name,
                provider: l.Loan_Provider__c,
                status: l.loan_status__c,
                appId: l.application_id__c,
                tenure: l.Tenure__c
            }));

            const addressStatus = await checkAddressByRecordId({ recordId: this.recordId });

            this.hasBillingAddress = addressStatus.hasBilling;
            this.hasShippingAddress = addressStatus.hasShipping;

            const hasStudyMaterial = this.hasStudyMaterial;
            this.selectedAddressType = 'shipping';

            await this.loadAddresses();
            this.ensureDefaultCountries();

            if (!this.hasBillingAddress) {
                this.missingAddressType = 'billing';
                this.showAddressModal = true;
                this.sameAsBilling = false;
                return;
            }

            if (hasStudyMaterial && !this.hasShippingAddress) {
                this.missingAddressType = 'shipping';
                this.showAddressModal = true;
                return;
            }

            this.showCheckout = true;
            this.sameAsBilling = false;
        } catch (error) {
            this.showToast('Error', error.body?.message || error.message, 'error');
        }
    }

    saveAddress() {
        const inputs = this.template.querySelectorAll('lightning-input[data-field]');
        const billing = {};
        const shipping = {};

        inputs.forEach((i) => {
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

        const normalizedBilling = this.normalizeAddress(billing);
        const normalizedShipping = this.sameAsBilling
            ? { ...normalizedBilling }
            : this.normalizeAddress(shipping);

        saveAddress({
            recordId: this.recordId,
            addressType: 'billing',
            address: billing
        })
            .then(async () => {
                if (this.sameAsBilling) {
                    shipping.street = billing.street;
                    shipping.city = billing.city;
                    shipping.state = billing.state;
                    shipping.postal = billing.postal;
                    shipping.country = billing.country;
                }

                const hasShippingInput = this.sameAsBilling || this.shouldShowShippingFields;
                const shouldSaveShipping =
                    this.missingAddressType === 'shipping' ||
                    this.missingAddressType === 'edit' ||
                    hasShippingInput;

                if (shouldSaveShipping) {
                    await saveAddress({
                        recordId: this.recordId,
                        addressType: 'shipping',
                        address: shipping
                    });
                }

                this.addressData = {
                    billing: normalizedBilling,
                    shipping: normalizedShipping
                };

                this.showAddressModal = false;
                this.sameAsBilling = false;
                this.hasBillingAddress = true;

                if (shouldSaveShipping) {
                    this.hasShippingAddress = true;
                }

                await this.loadAddresses();
                this.proceedToCheckout();
            })
            .catch((err) => {
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

        if (this.downPayment < this.effectiveMinimumDownPayment) {
            this.showToast(
                'Error',
                `Minimum down payment should be Rs ${this.effectiveMinimumDownPayment}`,
                'error'
            );
            return;
        }

        if (this.downPayment < this.effectiveMinimumDownPayment) {
            this.showToast(
                'Error',
                `Minimum down payment should be ₹${this.minimumDownPayment || 0}`,
                'error'
            );
            return;
        }

        if (this.isApprovalRequired && !String(this.approvalComments || '').trim()) {
            this.showToast('Error', 'Comments are required for approval.', 'error');
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
            processingFee: this.processingFee,
            phoneNumber: this.shippingPhone,
            addressType: 'shipping',
            approvalComments: this.approvalComments,
            loanId: this.selectedLoanId,
            items: this.selectedProducts.map((p) => ({
                productId: p.id,
                unitPrice: p.price,
                qty: 1,
                learningType: p.type
            }))
        };

        const requestJson = JSON.stringify(payload);

        const successMsg = this.isApprovalRequired
            ? 'Purchase Order submitted for approval.'
            : 'Purchase Order created successfully';

        savePurchaseOrder({ requestJson })
            .then(() => {
                this.showToast('Success', successMsg, 'success');
                this.dispatchEvent(new CloseActionScreenEvent());
                this.resetComponent();
            })
            .catch((error) => {
                const msg = error.body?.message || error.message || 'Unexpected error';
                this.showToast('Error', msg, 'error');
                console.error('Purchase Order creation failed:', error);
            });
    }

    resetComponent() {
        this.showCheckout = false;
        this.products = this.products.map((p) => ({ ...p, selected: false, quantity: 1 }));
        this.discountValue = 0;
        this.discountType = 'percentage';
        this.selectedAddressType = 'billing';
        this.downPayment = 0;
        this.minimumDownPayment = 0;
        this.discountThreshold = 0;
        this.approvalComments = '';
        this.shippingPhone = '';
        this.loans = [];
        this.selectedLoanId = null;
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    closeAddressModal() {
        this.showAddressModal = false;
    }

    async openEditAddressModal() {
        this.missingAddressType = 'edit';
        this.sameAsBilling = false;

        await this.loadAddresses();
        this.ensureDefaultCountries();
        this.showAddressModal = true;
    }

    async loadAddresses() {
        if (!this.recordId) return;

        try {
            const res = await getAddressByRecordId({ recordId: this.recordId });
            const billing = res?.billing || {};
            const shipping = res?.shipping || {};

            this.addressData = {
                billing: this.normalizeAddress(billing),
                shipping: this.normalizeAddress(shipping)
            };
            this.ensureDefaultCountries();

            this.shippingPhone = res?.phone || '';
        } catch (error) {
            this.showToast('Error', error.body?.message || error.message, 'error');
        }
    }

    validateDiscount(inputEl) {
        const input =
            inputEl || this.template.querySelector('lightning-input[data-id="discount"]');

        if (!input) return true;

        const value = Number(this.discountValue) || 0;
        let message = '';

        if (this.discountType === 'percentage') {
            if (value < 0 || value > MAX_DISCOUNT_PERCENT) {
                message = `Discount must be between 0% and ${MAX_DISCOUNT_PERCENT}%`;
            }
        } else {
            if (value < 0 || value > this.subTotal) {
                message = `Discount must be between â‚¹0 and â‚¹${this.subTotal}`;
            }
        }

        input.setCustomValidity(message);
        input.reportValidity();
        return !message;
    }

    validateDownPayment(inputEl, rawValue) {
        const input =
            inputEl || this.template.querySelector('lightning-input[data-id="downPayment"]');

        if (!input) return true;

        const value = rawValue !== undefined ? rawValue : Number(this.downPayment) || 0;
        const min = this.effectiveMinimumDownPayment;
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

    getSelectedLoanTenureMonths() {
        if (!this.selectedLoanId || !this.loans || !this.loans.length) return null;

        const loan = this.loans.find((l) => l.id === this.selectedLoanId);
        if (!loan || !loan.tenure) return null;

        const match = String(loan.tenure).match(/(\d+)/);
        if (!match) return null;

        return Number(match[1]) || null;
    }

    syncDownPayment() {
        const input = this.template.querySelector('lightning-input[data-id="downPayment"]');
        if (input) {
            this.validateDownPayment(input);
        }
    }
}
