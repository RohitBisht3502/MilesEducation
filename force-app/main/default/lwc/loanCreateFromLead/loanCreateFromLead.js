import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import { getLayout } from 'lightning/uiLayoutApi';
import getInitData from '@salesforce/apex/LoanQuickActionController.getInitData';
import createLoan from '@salesforce/apex/LoanQuickActionController.createLoan';

const CURRENT_ADDRESS_FLAG = 'Permanent_address_same_as_Current__c';
const CURRENT_ADDRESS_FLAG_LOWER = CURRENT_ADDRESS_FLAG.toLowerCase();
const CURRENT_FIELDS = ['flat_no__c', 'street__c', 'land_mark__c', 'pincode__c'];
const PERMANENT_FIELDS = ['permanent_flat_no__c', 'permanent_street__c', 'permanent_land_mark__c', 'permanent_pincode__c'];

const EXCLUDED_FIELDS = new Set([
    'miles_loan_code__c',
    'loan_status__c',
    'application_id__c',
    'redirection_url__c',
    'loan_id__c',
    'loan_provider__c'
]);

const PROVIDERS = {
    PROPELLD: 'PROPELLD',
    AVANSE: 'AVANSE',
    AKSHAR: 'AKSHAR'
};

const COMMON_REQUIRED = new Set([
    'program_name__c',
    'first_name__c',
    'email__c',
    'mobile__c',
    'amount_requested__c',
    'tenure__c'
]);

const AVANSE_PERMANENT_REQUIRED = new Set([
    'permanent_flat_no__c',
    'permanent_street__c',
    'permanent_land_mark__c',
    'permanent_pincode__c'
]);

const AVANSE_CURRENT_REQUIRED = new Set([
    'flat_no__c',
    'street__c',
    'land_mark__c',
    'pincode__c'
]);

const AKSHAR_REQUIRED = new Set([
    'pan_number__c',
    'date_of_birth__c',
    'flat_no__c',
    'street__c',
    'city__c',
    'state__c',
    'pincode__c'
]);

export default class LoanCreateFromLead extends LightningElement {
    _recordId;
    _initLoaded = false;

    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        this._recordId = value;
        if (this._recordId && !this._initLoaded) {
            this._initLoaded = true;
            this.loadInitData();
        }
    }

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
    formValues = {};

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

    connectedCallback() {}

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
                this.formValues[apiName.toLowerCase()] = value;
            }
        });

        this.prefillApplied = true;
        const visibleFields = Array.from(inputs).filter((i) => i.fieldName);
        this.noVisibleFields = visibleFields.length === 0;
        this.updateRequiredFlags();
    }

    loadInitData() {
        this.isLoading = true;
        this.errorMessage = '';

        getInitData({ leadId: this.recordId })
            .then((data) => {
                this.recordTypeOptions = (data && data.recordTypes) ? data.recordTypes : [];
                this.candidateFieldApi = data ? data.candidateFieldApi : null;
                this.courseFieldApi = data ? data.courseFieldApi : null;
                this.leadLookupFieldApi = data ? data.leadLookupFieldApi : null;
                this.emailFieldApi = data ? data.emailFieldApi : null;
                this.mobileFieldApi = data ? data.mobileFieldApi : null;
                this.prefillValues = (data && data.prefillValues) ? data.prefillValues : {};
                this.normalizeMobilePrefill(this.prefillValues);
                this.prefillValuesLower = this.buildLowercaseMap(this.prefillValues);
                this.prefillApplied = false;
                this.applyPrefillToLayout();
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
        this.updateRequiredFlags();
    }

    handleNext() {
        if (!this.selectedRecordTypeId) return;
        this.errorMessage = '';
        this.noVisibleFields = false;
        this.prefillApplied = false;
        this.step = 'form';
        this.updateRequiredFlags();
    }

    handleBack() {
        this.step = 'select';
        this.errorMessage = '';
        this.noVisibleFields = false;
        this.prefillApplied = false;
        this.formValues = {};
    }

    handleSave() {
        this.errorMessage = '';
        const inputs = this.template.querySelectorAll('lightning-input-field');
        const allValid = this.validateInputs(inputs);

        if (!allValid) {
            this.showError('Please fix the highlighted errors before saving.');
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
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Error',
                message: this.errorMessage,
                variant: 'error'
            })
        );
    }

    handleCancel() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    applyPrefillFields(fields) {
        if (!this.prefillValues) return;
        Object.keys(this.prefillValues).forEach((key) => {
            if (fields[key] === undefined || fields[key] === null || fields[key] === '') {
                fields[key] = this.normalizeMobileValue(key, this.prefillValues[key]);
            }
        });
    }

    applyCurrentAddressCopy(fields) {
        if (!fields[CURRENT_ADDRESS_FLAG]) return;

        for (let i = 0; i < CURRENT_FIELDS.length; i += 1) {
            const currentField = CURRENT_FIELDS[i];
            const permanentField = PERMANENT_FIELDS[i];
            if (fields[permanentField] !== undefined) {
                fields[permanentField] = fields[currentField];
            }
        }
    }

    getMobileFieldApiName() {
        return this.mobileFieldApi || 'mobile__c';
    }

    normalizeMobilePrefill(prefillValues) {
        if (!prefillValues) return;
        const apiName = this.getMobileFieldApiName();
        if (prefillValues[apiName] === undefined || prefillValues[apiName] === null) return;
        prefillValues[apiName] = this.stripIndiaPrefix(prefillValues[apiName]);
    }

    normalizeMobileValue(apiName, value) {
        if (!apiName) return value;
        const mobileApi = this.getMobileFieldApiName().toLowerCase();
        if (apiName.toLowerCase() !== mobileApi) return value;
        return this.stripIndiaPrefix(value);
    }

    stripIndiaPrefix(value) {
        if (value === undefined || value === null) return value;
        const raw = String(value).trim();
        if (raw === '') return value;
        let digits = raw.replace(/[^0-9]/g, '');
        if (digits.startsWith('91') && digits.length > 10) {
            digits = digits.substring(2);
        }
        return digits;
    }

    applyMobileValidation(inputs) {
        const mobileApi = this.getMobileFieldApiName().toLowerCase();
        let mobileInput = this.template.querySelector('lightning-input[data-id="mobileInput"]');
        if (!mobileInput && inputs) {
            mobileInput = Array.from(inputs).find(
                (input) => (input.fieldName || '').toLowerCase() === mobileApi
            );
        }
        if (!mobileInput) return true;

        const value = this.stripIndiaPrefix(mobileInput.value);
        if (value !== undefined && value !== null && value !== '') {
            const isValid = /^\d{10}$/.test(String(value));
            if (!isValid) {
                if (typeof mobileInput.setCustomValidity === 'function') {
                    mobileInput.setCustomValidity('Mobile number must be exactly 10 digits.');
                }
                if (typeof mobileInput.reportValidity === 'function') {
                    mobileInput.reportValidity();
                }
                return false;
            } else {
                if (typeof mobileInput.setCustomValidity === 'function') {
                    mobileInput.setCustomValidity('');
                }
                if (typeof mobileInput.reportValidity === 'function') {
                    mobileInput.reportValidity();
                }
                if (String(mobileInput.value) !== value) {
                    mobileInput.value = value;
                    this.formValues[mobileApi] = value;
                }
            }
        } else {
            if (typeof mobileInput.setCustomValidity === 'function') {
                mobileInput.setCustomValidity('');
            }
            if (typeof mobileInput.reportValidity === 'function') {
                mobileInput.reportValidity();
            }
        }
        return true;
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

    isCurrentAddressField(apiName) {
        return !!apiName && CURRENT_FIELDS.includes(apiName.toLowerCase());
    }

    isPermanentAddressField(apiName) {
        return !!apiName && PERMANENT_FIELDS.includes(apiName.toLowerCase());
    }

    syncPermanentAddressFields() {
        if (!this.isTruthy(this.formValues[CURRENT_ADDRESS_FLAG_LOWER])) return;

        for (let i = 0; i < CURRENT_FIELDS.length; i += 1) {
            const currentField = CURRENT_FIELDS[i];
            const permanentField = PERMANENT_FIELDS[i];
            this.formValues[permanentField] = this.formValues[currentField];
        }
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
            return this.normalizeMobileValue(apiName, this.prefillValues[apiName]);
        }
        const lowerKey = apiName.toLowerCase();
        if (this.prefillValuesLower && this.prefillValuesLower[lowerKey] !== undefined) {
            return this.normalizeMobileValue(apiName, this.prefillValuesLower[lowerKey]);
        }
        return undefined;
    }

    validateInputs(inputs) {
        let allValid = this.applyMobileValidation(inputs) !== false;
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

    showError(message) {
        this.errorMessage = message;
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Error',
                message,
                variant: 'error'
            })
        );
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
        const mobileApiLower = this.getMobileFieldApiName().toLowerCase();
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
                        isMobileField: fieldApiName && fieldApiName.toLowerCase() === mobileApiLower,
                        disabled: this.isFieldDisabled(fieldApiName),
                        prefillValue: this.formValues[fieldApiName.toLowerCase()] ?? this.resolvePrefillValue(fieldApiName)
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
        const mobileApiLower = this.getMobileFieldApiName().toLowerCase();
        this.layoutSections = this.layoutSections.map((section) => {
            const rows = (section.rows || []).map((row) => {
                const cols = (row.cols || []).map((col) => {
                    if (!col || !col.fieldApiName) {
                        return { ...col, prefillValue: undefined, required: false };
                    }
                    return {
                        ...col,
                        prefillValue: this.formValues[col.fieldApiName.toLowerCase()] ?? this.resolvePrefillValue(col.fieldApiName),
                        required: this.isFieldRequired(col.fieldApiName),
                        disabled: this.isFieldDisabled(col.fieldApiName),
                        isMobileField: col.fieldApiName.toLowerCase() === mobileApiLower
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
        if (this.isPermanentAddressField(apiName) && this.isTruthy(this.formValues[CURRENT_ADDRESS_FLAG_LOWER])) {
            return true;
        }
        if (apiName === 'program_name__c') return true;
        return this.candidateFieldApi && apiName === this.candidateFieldApi;
    }

    handleFieldChange(event) {
        const apiName = event.target.fieldName;
        if (!apiName) return;
        const key = apiName.toLowerCase();
        this.formValues[key] = event.target.value;
        if (key === CURRENT_ADDRESS_FLAG_LOWER || this.isCurrentAddressField(apiName)) {
            this.syncPermanentAddressFields();
        }
        this.applyPrefillToLayout();
        this.updateRequiredFlags();
    }

    handleMobileChange(event) {
        const mobileApi = this.getMobileFieldApiName().toLowerCase();
        const value = this.stripIndiaPrefix(event.target.value);
        this.formValues[mobileApi] = value;
        if (event.target.value !== value) {
            event.target.value = value;
        }
        this.applyMobileValidation();
    }

    updateRequiredFlags() {
        if (!this.layoutSections || this.layoutSections.length === 0) return;
        this.layoutSections = this.layoutSections.map((section) => {
            const rows = (section.rows || []).map((row) => {
                const cols = (row.cols || []).map((col) => {
                    if (!col || !col.fieldApiName) return { ...col, required: false };
                    return { ...col, required: this.isFieldRequired(col.fieldApiName) };
                });
                return { ...row, cols };
            });
            return { ...section, rows };
        });
    }

    isFieldRequired(apiName) {
        if (!apiName) return false;
        const key = apiName.toLowerCase();
        const provider = (this.selectedRecordTypeDevName || '').toUpperCase();
        const v = this.formValues || {};

        if (COMMON_REQUIRED.has(key)) return true;

        if (provider === PROVIDERS.PROPELLD) {
            return false;
        }

        if (provider === PROVIDERS.AVANSE) {
            if (AVANSE_PERMANENT_REQUIRED.has(key)) return true;

            const sameAsCurrent = this.isTruthy(v['permanent_address_same_as_current__c']);
            if (AVANSE_CURRENT_REQUIRED.has(key)) {
                return true;
            }
            if (!sameAsCurrent && AVANSE_PERMANENT_REQUIRED.has(key)) {
                return true;
            }
            if (key === 'applying_loan_for__c') return true;
            if (key === 'relationship_with_applicant__c') {
                return v['applying_loan_for__c'] === 'OTHER';
            }

            if (key === 'earning_status__c') return true;
            const earning = v['earning_status__c'] === 'Earning' || v['earning_status__c'] === '1';
            if (earning && (key === 'occupation_type__c' || key === 'monthly_income__c')) {
                return true;
            }

            if (key === 'marital_status__c' || key === 'gender__c') return true;
            return false;
        }

        if (provider === PROVIDERS.AKSHAR) {
            return AKSHAR_REQUIRED.has(key);
        }

        return false;
    }

    isTruthy(value) {
        return value === true || value === 'true' || value === 'True';
    }

    saveViaApex(inputs) {
        const fields = {};
        inputs.forEach((input) => {
            if (!input.fieldName) return;
            fields[input.fieldName] = input.value;
        });

        const mobileApi = this.getMobileFieldApiName();
        const mobileKey = mobileApi.toLowerCase();
        if (!fields[mobileApi] && this.formValues[mobileKey]) {
            fields[mobileApi] = this.formValues[mobileKey];
        }

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
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error',
                        message: this.errorMessage,
                        variant: 'error'
                    })
                );
            });
    }
}