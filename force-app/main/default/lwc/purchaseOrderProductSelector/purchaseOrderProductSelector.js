import { LightningElement, wire, track } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import getActiveProducts from '@salesforce/apex/PurchaseOrderService.getActiveProducts';
import savePurchaseOrder from '@salesforce/apex/PurchaseOrderService.save';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';


export default class PurchaseOrderProductSelector extends LightningElement {

    /* ================= STATE ================= */
    searchKey = '';
    showCheckout = false;

    discountType = 'percentage';
    discountValue = 0;

    @track products = [];

    // context ids (Lead Id fetched from page)
    leadId;
    candidateId;
    courseEnrolled;
    learningType;

    /* ================= FETCH LEAD ID ================= */
    @wire(CurrentPageReference)
    getStateParameters(currentPageReference) {
        if (currentPageReference) {
            const state = currentPageReference.state;
            this.leadId = state.recordId; // Lead Id from URL
            console.log('Lead Id fetched from page:', this.leadId);
        }
    }

    /* ================= COMPUTED FLAGS ================= */
    get hasSelectedProducts() {
        return this.products.some(p => p.selected === true);
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

    /* ================= LOAD PRODUCTS ================= */
    @wire(getActiveProducts)
    wiredProducts({ data, error }) {
        if (data) {
            this.products = data.map(p => ({
                id: p.id,
                name: p.name || '',
                sku: p.productCode || '',
                category: p.family || '',
                price: Number(p.unitPrice) || 0,
                quantity: 1,
                selected: false
            }));
        } else if (error) {
            this.showToast('Error', error.body?.message || 'Failed to load products', 'error');
        }
    }

    /* ================= SEARCH ================= */
    handleSearch(event) {
        this.searchKey = event.target.value?.toLowerCase() || '';
    }

    get filteredProducts() {
        return this.products.filter(p =>
            (p.name || '').toLowerCase().includes(this.searchKey)
        );
    }

    /* ================= CART ================= */
    addToCart(event) {
        const id = event.currentTarget.dataset.id;
        this.products = this.products.map(p =>
            String(p.id) === id ? { ...p, selected: true } : p
        );
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
        this.products = this.products.map(p =>
            String(p.id) === id ? { ...p, selected: false, quantity: 1 } : p
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

    /* ================= NAVIGATION ================= */
    proceedToCheckout() {
        if (!this.hasSelectedProducts) {
            this.showToast('Warning', 'Please select at least one product.', 'warning');
            return;
        }
        this.showCheckout = true;
    }

    backToProducts() {
        this.showCheckout = false;
    }

    /* ================= DISCOUNT ================= */
    handleDiscountType(event) {
        this.discountType = event.target.value;
        this.discountValue = 0;
    }

    handleDiscountValue(event) {
        this.discountValue = Number(event.target.value) || 0;
    }

    get discountAmount() {
        if (this.discountType === 'percentage') {
            return Math.round((this.subTotal * this.discountValue) / 100);
        }
        return Math.min(this.discountValue, this.subTotal);
    }

    get finalPayable() {
        return this.subTotal - this.discountAmount;
    }

    /* ================= SAVE ================= */
    confirmPurchase() {
        if (!this.hasSelectedProducts) {
            this.showToast('Warning', 'Please add at least one product before confirming.', 'warning');
            return;
        }

        if (!this.leadId) {
            this.showToast('Error', 'Lead Id not found.', 'error');
            return;
        }

        const payload = {
            leadId: this.leadId,
            candidateId: this.candidateId || null,
            courseEnrolled: this.courseEnrolled || null,
            discount: this.discountAmount,
            learningType: this.learningType || null,
            items: this.selectedProducts.map(p => ({
                productId: p.id,
                unitPrice: p.price,
                qty: p.quantity,
                learningType: this.learningType || null
            }))
        };

        const requestJson = JSON.stringify(payload);
        console.log('Payload to Apex:', requestJson);

        savePurchaseOrder({ requestJson })
            .then(poId => {
    this.showToast('Success', 'Purchase Order created successfully', 'success');

    // 🔥 CLOSE THE MODAL
    this.dispatchEvent(new CloseActionScreenEvent());

    // Optional safety reset (won’t matter after close)
    this.showCheckout = false;
    this.products = this.products.map(p => ({
        ...p,
        selected: false,
        quantity: 1
    }));
})

            .catch(error => {
                const msg = error.body?.message || error.message || 'Unexpected error';
                this.showToast('Error', msg, 'error');
                console.error('Apex Error:', error);
            });
    }

    /* ================= UTIL ================= */
    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}