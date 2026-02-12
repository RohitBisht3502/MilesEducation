import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getLeadCourses from '@salesforce/apex/LeadNewOverrideController.getLeadCourses';
import createLeadByCourse from '@salesforce/apex/LeadNewOverrideController.createLeadByCourse';

export default class LeadNewOverrideLwc extends NavigationMixin(LightningElement) {
    @track courseOptions = [];
    course = '';
    firstName = '';
    lastName = '';
    phone = '';
    email = '';
    isLoading = false;
    errorMessage = '';

    connectedCallback() {
        this.loadCourses();
    }

    get saveLabel() {
        return this.isLoading ? 'Saving...' : 'Save';
    }

    loadCourses() {
        this.isLoading = true;
        this.errorMessage = '';
        getLeadCourses()
            .then((data) => {
                this.courseOptions = (data || []).map((opt) => ({
                    label: opt.label,
                    value: opt.value
                }));
            })
            .catch((error) => {
                this.errorMessage = this.extractError(error);
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleInputChange(event) {
        const { name, value } = event.target;
        if (name === 'course') this.course = value;
        if (name === 'firstName') this.firstName = value;
        if (name === 'lastName') this.lastName = value;
        if (name === 'phone') this.phone = value;
        if (name === 'email') this.email = value;
    }

    handleCreate() {
        this.errorMessage = '';
        const inputs = this.template.querySelectorAll('lightning-input, lightning-combobox');
        const allValid = Array.from(inputs).reduce((valid, input) => {
            input.reportValidity();
            return valid && input.checkValidity();
        }, true);

        if (!allValid) {
            this.errorMessage = 'Please fill all required fields.';
            return;
        }

        this.isLoading = true;
        createLeadByCourse({
            course: this.course,
            firstName: this.firstName,
            lastName: this.lastName,
            phone: this.phone,
            email: this.email
        })
            .then((result) => {
                if (result && result.success && result.leadId) {
                    this[NavigationMixin.Navigate]({
                        type: 'standard__recordPage',
                        attributes: {
                            recordId: result.leadId,
                            actionName: 'view'
                        }
                    });
                } else {
                    this.errorMessage = (result && result.message) ? result.message : 'Failed to create Lead.';
                }
            })
            .catch((error) => {
                this.errorMessage = this.extractError(error);
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleCancel() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'Lead__c',
                actionName: 'list'
            },
            state: {
                filterName: 'Recent'
            }
        });
    }

    errorCallback(error, stack) {
        this.isLoading = false;
        this.errorMessage = this.extractError(error);
        // eslint-disable-next-line no-console
        console.error('LeadNewOverrideLwc error:', error, stack);
    }

    extractError(error) {
        if (!error) return 'Unexpected error.';
        if (Array.isArray(error.body)) {
            return error.body.map((e) => e.message).join(', ');
        }
        if (error.body && error.body.message) return error.body.message;
        if (error.message) return error.message;
        return 'Unexpected error.';
    }
}