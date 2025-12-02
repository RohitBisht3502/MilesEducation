import { LightningElement, api, track, wire } from 'lwc';
import searchLeads from '@salesforce/apex/TagLeadController.searchLeads';
import tagOrCreateLead from '@salesforce/apex/TagLeadController.tagOrCreateLead';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { getPicklistValues, getObjectInfo } from 'lightning/uiObjectInfoApi';
import PHONE_FIELD from '@salesforce/schema/Call_Log__c.Phone_Number__c';
import LEAD_OBJECT from '@salesforce/schema/Lead__c';
import COURSE_FIELD from '@salesforce/schema/Lead__c.Course__c';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';

export default class TagLeadForCallLog extends LightningElement {
    @api recordId;

    @track leads = [];
    @track formData = {
        name: '',
        course: '',
        email: '',
        phone: ''
    };
    
    searchKeyword = '';
    selectedLeadId = null;
    isLoading = false;
    viewState = 'search'; // 'search', 'notFound', 'create'
    phoneNumber = '';
    hasAutoSearched = false;
    courseOptions = [];

    // Get Lead Object Info (required for picklist)
    @wire(getObjectInfo, { objectApiName: LEAD_OBJECT })
    leadObjectInfo;

    // Get Course Picklist Values
    @wire(getPicklistValues, {
        recordTypeId: '$leadObjectInfo.data.defaultRecordTypeId',
        fieldApiName: COURSE_FIELD
    })
    wiredCoursePicklist({ data, error }) {
        if (data) {
            this.courseOptions = data.values.map(option => ({
                label: option.label,
                value: option.value
            }));
        } else if (error) {
            console.error('Error loading course picklist:', error);
        }
    }

    // Auto-load phone from call log
    @wire(getRecord, { recordId: '$recordId', fields: [PHONE_FIELD] })
    wiredCallLog({ data }) {
        if (data) {
            const phone = getFieldValue(data, PHONE_FIELD);
            if (phone && !this.hasAutoSearched) {
                this.phoneNumber = phone;
                this.searchKeyword = phone;
                this.formData.phone = phone;
                this.hasAutoSearched = true;
                this.runSearch(phone);
            }
        }
    }

    // Reusable search logic
    runSearch(keyword) {
        if (!keyword || keyword.trim().length < 2) {
            this.leads = [];
            this.selectedLeadId = null;
            this.viewState = 'search';
            return;
        }

        this.isLoading = true;

        searchLeads({ keyword })
            .then(result => {
                if (result && result.length > 0) {
                    this.leads = result.map(lead => ({
                        ...lead,
                        selectedClass: ''
                    }));
                    this.selectedLeadId = null;
                    this.viewState = 'search';
                } else {
                    this.leads = [];
                    this.viewState = 'notFound';
                }
            })
            .catch(() => {
                this.leads = [];
                this.viewState = 'notFound';
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    // Handle search input change
    handleSearchInput(event) {
        this.searchKeyword = event.target.value;
    }

    // Handle search button click
    handleSearchClick() {
        this.runSearch(this.searchKeyword);
    }

    // Handle Enter key in search input
    handleSearchKeyPress(event) {
        if (event.key === 'Enter') {
            this.runSearch(this.searchKeyword);
        }
    }

    // Select Lead
    selectLead(event) {
        this.selectedLeadId = event.currentTarget.dataset.id;

        this.leads = this.leads.map(lead => ({
            ...lead,
            selectedClass: lead.Id === this.selectedLeadId ? 'selected' : ''
        }));
    }

    // Handle form input changes
    handleNameChange(event) {
        this.formData.name = event.target.value;
    }

    handleCourseChange(event) {
        this.formData.course = event.target.value;
    }

    handleEmailChange(event) {
        this.formData.email = event.target.value;
    }

    // Show create form
    handleCreateNew() {
        this.viewState = 'create';
    }

    // Cancel create form
    handleCancel() {
        this.viewState = 'search';
        this.searchKeyword = '';
        this.leads = [];
        this.selectedLeadId = null;
        this.formData = {
            name: '',
            course: '',
            email: '',
            phone: this.phoneNumber
        };
    }

    // Close modal
    closeModal() {
        // For Quick Action
        this.dispatchEvent(new CloseActionScreenEvent());
        
        // For custom modal
        this.dispatchEvent(new CustomEvent('close'));
    }

    // Getters for UI
    get hasLeads() {
        return this.leads.length > 0;
    }

    get showSearch() {
        return this.viewState === 'search' || this.viewState === 'notFound';
    }

    get showNotFound() {
        return this.viewState === 'notFound';
    }

    get showCreateForm() {
        return this.viewState === 'create';
    }

    get showLeadResults() {
        return this.viewState === 'search' && this.hasLeads;
    }

    get showTagButton() {
        return this.viewState === 'search' && this.selectedLeadId !== null;
    }

    get isFormValid() {
        return this.formData.name.trim() && this.formData.course.trim();
    }

    get submitButtonLabel() {
        return this.isLoading ? 'Creating...' : 'Create Lead';
    }

    get tagButtonLabel() {
        return this.isLoading ? 'Tagging...' : 'Tag Lead';
    }

    // Tag existing lead to call log
    handleTagLead() {
        if (!this.selectedLeadId) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: 'Please select a lead to tag',
                variant: 'error'
            }));
            return;
        }

        this.isLoading = true;

        tagOrCreateLead({
            callLogId: this.recordId,
            leadId: this.selectedLeadId,
            name: null,
            course: null,
            email: null,
            phone: null,
            disableRR: true
        })
            .then(() => {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Success',
                    message: 'Lead tagged successfully!',
                    variant: 'success'
                }));

                // Close modal after successful tagging
                this.closeModal();
            })
            .catch((error) => {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Error',
                    message: 'Failed to tag lead: ' + (error.body?.message || error.message),
                    variant: 'error'
                }));
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    // Submit - Create new lead and tag to call log
    handleSubmit() {
        if (!this.isFormValid) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: 'Please fill in all required fields',
                variant: 'error'
            }));
            return;
        }

        this.isLoading = true;

        tagOrCreateLead({
            callLogId: this.recordId,
            leadId: null,
            name: this.formData.name,
            course: this.formData.course,
            email: this.formData.email,
            phone: this.phoneNumber,
            disableRR: true
        })
            .then(() => {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Success',
                    message: 'Lead created and tagged successfully!',
                    variant: 'success'
                }));

                // Close modal after successful creation
                this.closeModal();
            })
            .catch((error) => {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Error',
                    message: 'Failed to create lead: ' + (error.body?.message || error.message),
                    variant: 'error'
                }));
            })
            .finally(() => {
                this.isLoading = false;
            });
    }
}