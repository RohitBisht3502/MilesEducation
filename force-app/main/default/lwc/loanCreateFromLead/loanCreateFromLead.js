import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import { getLayout } from 'lightning/uiLayoutApi';
import getInitData from '@salesforce/apex/LoanQuickActionController.getInitData';
import createLoan from '@salesforce/apex/LoanQuickActionController.createLoan';

const CURRENT_ADDRESS_FLAG = 'Current_Address_Same_As_Permanent__c';
const CURRENT_FIELDS = ['flat_no__c', 'street__c', 'land_mark__c', 'pincode__c'];
const PERMANENT_FIELDS = ['permanent_flat_no__c', 'permanent_street__c', 'permanent_land_mark__c', 'permanent_pincode__c'];

const EXCLUDED_FIELDS = new Set([
    'miles_loan_code__c',
    'loan_status__c',
    'application_id__c',
    'redirection_url__c'
]);

export default class LoanCreateFromLead extends LightningElement {
    @api recordId;

    @track recordTypeOptions = [];
    @track layoutSections = [];

    selectedRecordTypeId;
    selectedRecordTypeLabel = 'New Loan';
    selectedRecordTypeDevName;

    loanObjectApiName = 'Loan__c';

    isLoading = false;
    isSaving = false;
    errorMessage = '';
    noVisibleFields = false;

    prefillValues = {};
    prefillValuesLower = {};
    prefillApplied = false;

    candidateFieldApi;
    courseFieldApi;
    leadLookupFieldApi;
    emailFieldApi;
    mobileFieldApi;

    isResubmitting = false;

    step = 'select';

    get isRecordTypeStep() {
        return this.step === 'select';
    }

    get isFormStep() {
        return this.step === 'form';
    }

    get panelHeader() {
        if (this.isFormStep && this.selectedRecordTypeLabel) {
            return `New Loan: ${this.selectedRecordTypeLabel}`;
        }
        return 'New Loan';
    }

    get disableNext() {
        return !this.selectedRecordTypeId;
    }

    connectedCallback() {
        this.loadInitData();
    }

    renderedCallback() {
        if (!this.isFormStep || this.prefillApplied) return;
        if (!this.prefillValues || Object.keys(this.prefillValues).length === 0) {
            this.prefillApplied = true;
            return;
        }

        const inputs = this.template.querySelectorAll('lightning-input-field');
        if (inputs.length === 0) return;

        inputs.forEach((input) => {
            const apiName = input.fieldName;
            if (!apiName) return;
            const value = this.resolvePrefillValue(apiName);
            if (value === undefined || value === null) return;
            if (input.value === undefined || input.value === null || input.value === '') {
                input.value = value;
            }
        });

        this.prefillApplied = true;
        const visibleFields = Array.from(inputs).filter((i) => i.fieldName);
        this.noVisibleFields = visibleFields.length === 0;
    }

    loadInitData() {
        this.isLoading = true;
        this.errorMessage = '';

        getInitData({ leadId: this.recordId })
            .then((data) => {
                this.recordTypeOptions = (data && data.recordTypes) ? data.recordTypes : [];
                this.prefillValues = (data && data.prefillValues) ? data.prefillValues : {};
                this.prefillValuesLower = this.buildLowercaseMap(this.prefillValues);
                this.prefillApplied = false;
                this.applyPrefillToLayout();
                this.candidateFieldApi = data ? data.candidateFieldApi : null;
                this.courseFieldApi = data ? data.courseFieldApi : null;
                this.leadLookupFieldApi = data ? data.leadLookupFieldApi : null;
                this.emailFieldApi = data ? data.emailFieldApi : null;
                this.mobileFieldApi = data ? data.mobileFieldApi : null;
            })
            .catch((error) => {
                this.errorMessage = this.reduceErrors(error);
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleRecordTypeChange(event) {
        this.selectedRecordTypeId = event.detail.value;
        const match = this.recordTypeOptions.find((opt) => opt.value === this.selectedRecordTypeId);
        this.selectedRecordTypeLabel = match ? match.label : 'New Loan';
        this.selectedRecordTypeDevName = match ? match.developerName : null;
    }

    handleNext() {
        if (!this.selectedRecordTypeId) return;
        this.errorMessage = '';
        this.noVisibleFields = false;
        this.prefillApplied = false;
        this.step = 'form';
    }

    handleBack() {
        this.step = 'select';
        this.errorMessage = '';
        this.noVisibleFields = false;
        this.layoutSections = [];
        this.prefillApplied = false;
    }

    handleSave() {
        debugger;
        this.errorMessage = '';
        const inputs = this.template.querySelectorAll('lightning-input-field');
        const allValid = this.validateInputs(inputs);

        if (!allValid) {
            this.errorMessage = 'Please fill all required fields.';
            return;
        }
        this.saveViaApex(inputs);
    }

    handleSuccess() {
        this.isSaving = false;
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Loan created',
                message: 'Loan record created successfully.',
                variant: 'success'
            })
        );
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    handleError(event) {
        this.isSaving = false;
        this.errorMessage = this.reduceErrors(event.detail);
    }

    handleCancel() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    applyPrefillFields(fields) {
        if (!this.prefillValues) return;
        Object.keys(this.prefillValues).forEach((key) => {
            if (fields[key] === undefined || fields[key] === null || fields[key] === '') {
                fields[key] = this.prefillValues[key];
            }
        });
    }

    applyCurrentAddressCopy(fields) {
        if (!fields[CURRENT_ADDRESS_FLAG]) return;

        for (let i = 0; i < CURRENT_FIELDS.length; i += 1) {
            const currentField = CURRENT_FIELDS[i];
            const permanentField = PERMANENT_FIELDS[i];
            if (fields[permanentField] !== undefined) {
                fields[currentField] = fields[permanentField];
            }
        }
    }

    reduceErrors(error) {
        if (!error) return 'Unexpected error.';
        if (Array.isArray(error.body)) {
            return error.body.map((e) => e.message).join(', ');
        }
        if (error.body && error.body.message) return error.body.message;
        if (error.message) return error.message;
        if (error.detail && error.detail.message) return error.detail.message;
        return 'Unexpected error.';
    }

    buildLowercaseMap(obj) {
        const map = {};
        if (!obj) return map;
        Object.keys(obj).forEach((key) => {
            if (!key) return;
            map[key.toLowerCase()] = obj[key];
        });
        return map;
    }

    resolvePrefillValue(apiName) {
        if (!apiName) return undefined;
        if (this.prefillValues && this.prefillValues[apiName] !== undefined) {
            return this.prefillValues[apiName];
        }
        const lowerKey = apiName.toLowerCase();
        if (this.prefillValuesLower && this.prefillValuesLower[lowerKey] !== undefined) {
            return this.prefillValuesLower[lowerKey];
        }
        return undefined;
    }

    validateInputs(inputs) {
        let allValid = true;
        Array.from(inputs).forEach((input) => {
            let isValid = true;
            if (typeof input.reportValidity === 'function') {
                const reported = input.reportValidity();
                if (reported === false) {
                    isValid = false;
                }
            }
            if (isValid && typeof input.checkValidity === 'function') {
                if (!input.checkValidity()) {
                    isValid = false;
                }
            } else if (isValid && input.validity && input.validity.valid === false) {
                isValid = false;
            }
            if (!isValid) {
                allValid = false;
            }
        });
        return allValid;
    }

    @wire(getLayout, {
        objectApiName: 'Loan__c',
        layoutType: 'Full',
        mode: 'Create',
        recordTypeId: '$selectedRecordTypeId'
    })
    wiredLayout({ data, error }) {
        if (error) {
            this.errorMessage = this.reduceErrors(error);
            return;
        }
        if (!data || !data.sections) return;

        this.layoutSections = this.buildLayoutFromUiApi(data.sections);
        this.prefillApplied = false;
        this.applyPrefillToLayout();
    }

    buildLayoutFromUiApi(sections) {
        const result = [];
        sections.forEach((section, sIndex) => {
            const heading = section.heading || 'Information';
            const rows = [];

            (section.layoutRows || []).forEach((row, rIndex) => {
                const cols = [];
                (row.layoutItems || []).forEach((item, cIndex) => {
                    const fieldApiName = this.getFieldApiFromLayoutItem(item);
                    if (this.shouldExcludeField(fieldApiName)) {
                        return;
                    }
                    cols.push({
                        key: `col-${sIndex}-${rIndex}-${cIndex}`,
                        fieldApiName,
                        disabled: this.isFieldDisabled(fieldApiName),
                        prefillValue: this.resolvePrefillValue(fieldApiName)
                    });
                });

                while (cols.length < 2) {
                    cols.push({
                        key: `col-${sIndex}-${rIndex}-${cols.length}`,
                        fieldApiName: null,
                        prefillValue: undefined
                    });
                }

                rows.push({
                    key: `row-${sIndex}-${rIndex}`,
                    cols
                });
            });

            if (rows.length > 0) {
                result.push({
                    key: `section-${sIndex}`,
                    heading,
                    rows
                });
            }
        });
        return result;
    }

    applyPrefillToLayout() {
        if (!this.layoutSections || this.layoutSections.length === 0) return;
        this.layoutSections = this.layoutSections.map((section) => {
            const rows = (section.rows || []).map((row) => {
                const cols = (row.cols || []).map((col) => {
                    if (!col || !col.fieldApiName) {
                        return { ...col, prefillValue: undefined };
                    }
                    return {
                        ...col,
                        prefillValue: this.resolvePrefillValue(col.fieldApiName)
                    };
                });
                return { ...row, cols };
            });
            return { ...section, rows };
        });
    }

    getFieldApiFromLayoutItem(item) {
        if (!item || !item.layoutComponents) return null;
        const comp = item.layoutComponents.find((c) => {
            const type = (c.componentType || c.type || '').toLowerCase();
            return type === 'field';
        });
        if (!comp) return null;
        return comp.apiName || comp.fieldApiName || comp.value || null;
    }

    shouldExcludeField(apiName) {
        if (!apiName) return true;
        return EXCLUDED_FIELDS.has(apiName.toLowerCase());
    }

    isFieldDisabled(apiName) {
        if (!apiName) return false;
        return this.candidateFieldApi && apiName === this.candidateFieldApi;
    }

    saveViaApex(inputs) {
        const fields = {};
        inputs.forEach((input) => {
            if (!input.fieldName) return;
            fields[input.fieldName] = input.value;
        });

        this.applyPrefillFields(fields);
        this.applyCurrentAddressCopy(fields);

        this.isSaving = true;
        createLoan({
            leadId: this.recordId,
            recordTypeId: this.selectedRecordTypeId,
            fields
        })
            .then((loanId) => {
                this.isSaving = false;
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Loan created',
                        message: 'Loan record created successfully.',
                        variant: 'success'
                    })
                );
                this.dispatchEvent(new CloseActionScreenEvent());
            })
            .catch((error) => {
                this.isSaving = false;
                this.errorMessage = this.reduceErrors(error);
            });
    }
}
