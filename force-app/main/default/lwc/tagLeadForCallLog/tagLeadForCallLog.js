import { LightningElement, api, track, wire } from 'lwc';
import searchLeads from '@salesforce/apex/TagLeadController.searchLeads';
import tagOrCreateLead from '@salesforce/apex/TagLeadController.tagOrCreateLead';
import getL1L2Values from '@salesforce/apex/Webservice_RunoAllocationAPI.getL1L2Values';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import { getPicklistValues } from 'lightning/uiObjectInfoApi';
import LEAD_OBJECT from '@salesforce/schema/Lead__c';
import CALL_LOG_OBJECT from '@salesforce/schema/Call_Log__c';
import COURSE_FIELD from '@salesforce/schema/Lead__c.Course__c';
import L1_FIELD from '@salesforce/schema/Call_Log__c.L1__c';
import L2_FIELD from '@salesforce/schema/Call_Log__c.L2__c';
import CUSTOMER_NAME_FIELD from '@salesforce/schema/Call_Log__c.Customer_Name__c';
import PHONE_NUMBER_FIELD from '@salesforce/schema/Call_Log__c.Phone_Number__c';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';

const CALL_LOG_FIELDS = [CUSTOMER_NAME_FIELD, PHONE_NUMBER_FIELD];

export default class TagLeadForCallLog extends LightningElement {
    @api recordId;

    @track leads = [];
    @track formData = {
        name: '',
        course: '',
        email: '',
        phone: '',
        nextFollowUpDate: '',
        l1: '',
        l2: '',
        feedback: ''
    };
    
    @track tagData = {
        l1: '',
        l2: '',
        nextFollowUpDate: '',
        feedback: ''
    };
    
    @track searchKeyword = '';
    selectedLeadId = null;
    isLoading = false;
    viewState = 'search'; // 'search', 'notFound', 'create'
    hasAutoSearched = false;
    courseOptions = [];
    l1Options = [];
    l2Options = [];

    fullL1L2Map = {};
    dependentL2Options = [];
    isL2Disabled = true;
    
    // For create form L2 dependency
    createDependentL2Options = [];
    isCreateL2Disabled = true;

    connectedCallback() {
        this.loadDependentMap();
        this.setDefaultFollowUpDate();
    }

   setDefaultFollowUpDate() {
    const next = new Date(Date.now() + 24 * 60 * 60 * 1000);

    const yyyy = next.getFullYear();
    const mm = String(next.getMonth() + 1).padStart(2, '0');
    const dd = String(next.getDate()).padStart(2, '0');
    const hh = String(next.getHours()).padStart(2, '0');
    const mi = String(next.getMinutes()).padStart(2, '0');

    const defaultDate = `${yyyy}-${mm}-${dd}T${hh}:${mi}`;

    this.formData.nextFollowUpDate = defaultDate;
    this.tagData.nextFollowUpDate = defaultDate;
}


    async loadDependentMap() {
        try {
            const mapData = await getL1L2Values();
            this.fullL1L2Map = mapData;

            // Build L1 options from map keys
            this.l1Options = Object.keys(mapData).map(key => ({
                label: key,
                value: key
            }));
        } catch (error) {
            console.error('Error loading L1/L2 dependency:', error);
        }
    }

    // Wire Call Log Record
    @wire(getRecord, { recordId: '$recordId', fields: CALL_LOG_FIELDS })
    wiredCallLogHandler(result) {
        this.wiredCallLog = result;
        const { error, data } = result;
        if (data) {
            const phoneNumber = getFieldValue(data, PHONE_NUMBER_FIELD);
            
            // Auto-populate phone number in search box and trigger search
            if (phoneNumber && !this.hasAutoSearched) {
                this.searchKeyword = phoneNumber;
                this.formData.phone = phoneNumber;
                this.hasAutoSearched = true;
                
                // Trigger search automatically
                this.runSearch(phoneNumber);
            }
        } else if (error) {
            console.error('Error loading call log:', error);
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: 'Failed to load call log details',
                variant: 'error'
            }));
        }
    }

    // Get Lead Object Info (required for picklist)
    @wire(getObjectInfo, { objectApiName: LEAD_OBJECT })
    leadObjectInfo;

    // Get Call Log Object Info (required for L1 and L2 picklists)
    @wire(getObjectInfo, { objectApiName: CALL_LOG_OBJECT })
    callLogObjectInfo;

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

    // Store wire result for accessing in getters
    wiredCallLog;

    // Getters for Call Log Details
    get customerName() {
        return getFieldValue(this.wiredCallLog?.data, CUSTOMER_NAME_FIELD) || 'N/A';
    }

    get phoneNumber() {
        return getFieldValue(this.wiredCallLog?.data, PHONE_NUMBER_FIELD) || '';
    }

    get minDateTime() {
        return new Date().toISOString().slice(0, 16);
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
                        selectedClass: '',
                        OwnerName: lead.Owner ? lead.Owner.Name : 'N/A'
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

        // Reset tag data when selecting a new lead
        this.setDefaultFollowUpDate();
        this.tagData = {
            l1: '',
            l2: '',
            nextFollowUpDate: this.tagData.nextFollowUpDate,
            feedback: ''
        };
        this.dependentL2Options = [];
        this.isL2Disabled = true;
    }

    // Handle tag data input changes
    handleL1Change(event) {
        this.tagData.l1 = event.target.value;

        const l2List = this.fullL1L2Map[this.tagData.l1] || [];

        this.dependentL2Options = l2List.map(value => ({
            label: value,
            value: value
        }));

        this.isL2Disabled = this.dependentL2Options.length === 0;
        this.tagData.l2 = ''; // reset L2
    }

    handleL2Change(event) {
        this.tagData.l2 = event.target.value;
    }

    handleTagFollowUpDateChange(event) {
        this.tagData.nextFollowUpDate = event.target.value;
    }

    handleTagFeedbackChange(event) {
        this.tagData.feedback = event.target.value;
    }

    // Handle form input changes for create
    handleNameChange(event) {
        this.formData.name = event.target.value;
    }

    handleCourseChange(event) {
        this.formData.course = event.target.value;
    }

    handleEmailChange(event) {
        this.formData.email = event.target.value;
    }

    handleCreateFollowUpDateChange(event) {
        this.formData.nextFollowUpDate = event.target.value;
    }

    handleCreateL1Change(event) {
        this.formData.l1 = event.target.value;

        const l2List = this.fullL1L2Map[this.formData.l1] || [];

        this.createDependentL2Options = l2List.map(value => ({
            label: value,
            value: value
        }));

        this.isCreateL2Disabled = this.createDependentL2Options.length === 0;
        this.formData.l2 = ''; // reset L2
    }

    handleCreateL2Change(event) {
        this.formData.l2 = event.target.value;
    }

    handleCreateFeedbackChange(event) {
        this.formData.feedback = event.target.value;
    }

    // Show create form
    handleCreateNew() {
        this.viewState = 'create';
        this.setDefaultFollowUpDate();
    }

    // Cancel create form
    handleCancel() {
        this.viewState = 'search';
        this.searchKeyword = '';
        this.leads = [];
        this.selectedLeadId = null;
        this.setDefaultFollowUpDate();
        this.formData = {
            name: '',
            course: '',
            email: '',
            phone: this.phoneNumber,
            nextFollowUpDate: this.formData.nextFollowUpDate,
            l1: '',
            l2: '',
            feedback: ''
        };
        this.tagData = {
            l1: '',
            l2: '',
            nextFollowUpDate: this.tagData.nextFollowUpDate,
            feedback: ''
        };
        this.createDependentL2Options = [];
        this.isCreateL2Disabled = true;
        this.dependentL2Options = [];
        this.isL2Disabled = true;
    }

    // Close modal
    closeModal() {
        this.dispatchEvent(new CloseActionScreenEvent());
        setTimeout(() => window.location.reload(), 800);
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

    get isFormValid() {
        return this.formData.name.trim() && 
               this.formData.course.trim() && 
               this.formData.l1.trim() && 
               this.formData.l2.trim();
    }

    get isTagFormValid() {
        return this.tagData.l1.trim() && this.tagData.l2.trim();
    }

    get submitButtonLabel() {
        return this.isLoading ? 'Creating...' : 'Create New Lead';
    }

    get tagButtonLabel() {
        return this.isLoading ? 'Tagging...' : 'Tag Lead';
    }

    get leadItems() {
        return this.leads.map(lead => ({
            ...lead,
            cssClass: lead.selectedClass ? 'lead-card selected' : 'lead-card',
            showTagForm: lead.Id === this.selectedLeadId
        }));
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

        if (!this.isTagFormValid) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: 'Please fill in L1 and L2 fields',
                variant: 'error'
            }));
            return;
        }

        // Validate date is not in past
        if (this.tagData.nextFollowUpDate && new Date(this.tagData.nextFollowUpDate) < new Date()) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: 'Follow up date cannot be in the past',
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
            disableRR: true,
            l1: this.tagData.l1,
            l2: this.tagData.l2,
            feedback: this.tagData.feedback || null,
            nextFollowUpDate: this.tagData.nextFollowUpDate || null
        })
            .then(() => {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Success',
                    message: 'Lead tagged successfully!',
                    variant: 'success'
                }));

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

        // Validate date is not in past
        if (this.formData.nextFollowUpDate && new Date(this.formData.nextFollowUpDate) < new Date()) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: 'Follow up date cannot be in the past',
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
            disableRR: true,
            l1: this.formData.l1,
            l2: this.formData.l2,
            feedback: this.formData.feedback || null,
            nextFollowUpDate: this.formData.nextFollowUpDate || null
        })
            .then(() => {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Success',
                    message: 'Lead created and tagged successfully!',
                    variant: 'success'
                }));

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