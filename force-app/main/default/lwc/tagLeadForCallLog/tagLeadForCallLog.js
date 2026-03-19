import { LightningElement, api, track, wire } from 'lwc';
import searchLeads from '@salesforce/apex/TagLeadController.searchLeads';
import tagOrCreateLead from '@salesforce/apex/TagLeadController.tagOrCreateLead';
import markPhoneNumberStatus from '@salesforce/apex/TagLeadController.markPhoneNumberStatus';
import getCityOptions from '@salesforce/apex/LeadNewOverrideController.getCityOptions';
import getSourceOptions from '@salesforce/apex/LeadNewOverrideController.getSourceOptions';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import { getPicklistValues } from 'lightning/uiObjectInfoApi';
import LEAD_OBJECT from '@salesforce/schema/Lead__c';
import CALL_LOG_OBJECT from '@salesforce/schema/Call_Log__c';
import COURSE_FIELD from '@salesforce/schema/Lead__c.Course__c';
import CUSTOMER_NAME_FIELD from '@salesforce/schema/Call_Log__c.Customer_Name__c';
import PHONE_NUMBER_FIELD from '@salesforce/schema/Call_Log__c.Phone_Number__c';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';

const CALL_LOG_FIELDS = [CUSTOMER_NAME_FIELD, PHONE_NUMBER_FIELD];

export default class TagLeadForCallLog extends LightningElement {
    @api recordId;

    @track candidates = [];
    @track formData = {
        firstName: '',
        lastName: '',
        course: '',
        city: '',
        source: '',
        email: '',
        phone: '',
        countryCode: '+91',
        nextFollowUpDate: '',
        l1: '',
        l2: '',
        feedback: ''
    };
    @track searchKeyword = '';
    selectedCandidateId = null;
    isLoading = false;
    viewState = 'search';
    hasAutoSearched = false;
    courseOptions = [];
    cityOptions = [];
    sourceOptions = [];

    connectedCallback() {
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
    }




    @wire(getRecord, { recordId: '$recordId', fields: CALL_LOG_FIELDS })
    wiredCallLogHandler(result) {
        this.wiredCallLog = result;
        const { error, data } = result;
        if (data) {
            const phoneNumber = getFieldValue(data, PHONE_NUMBER_FIELD);

            if (phoneNumber && !this.hasAutoSearched) {
                this.searchKeyword = phoneNumber;
                this.formData.phone = phoneNumber;
                this.hasAutoSearched = true;

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

    @wire(getObjectInfo, { objectApiName: LEAD_OBJECT })
    leadObjectInfo;

    @wire(getObjectInfo, { objectApiName: CALL_LOG_OBJECT })
    callLogObjectInfo;

    @wire(getPicklistValues, {
        recordTypeId: '$courseRecordTypeId',
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

    wiredCallLog;

    get courseRecordTypeId() {
        const info = this.leadObjectInfo?.data;
        if (!info) return null;

        const rtis = info.recordTypeInfos || {};

        // Use the Master Record Type ID (ending in AAA) to fetch ALL picklist values
        const master = Object.keys(rtis)
            .map(id => rtis[id])
            .find(rti => rti?.master);

        return master?.recordTypeId || '012000000000000AAA';
    }

    get customerName() {
        return getFieldValue(this.wiredCallLog?.data, CUSTOMER_NAME_FIELD) || 'N/A';
    }

    get phoneNumber() {
        return getFieldValue(this.wiredCallLog?.data, PHONE_NUMBER_FIELD) || '';
    }

    get minDateTime() {
        return new Date().toISOString().slice(0, 16);
    }

    runSearch(keyword) {
        if (!keyword || keyword.trim().length < 2) {
            this.candidates = [];
            this.selectedCandidateId = null;
            this.viewState = 'search';
            return;
        }

        this.isLoading = true;

        searchLeads({ keyword })
            .then(result => {
                if (result && result.length > 0) {
                    this.candidates = result.map(candidate => ({
                        ...candidate,
                        cssClass: candidate.candidateId === this.selectedCandidateId ? 'lead-card selected' : 'lead-card',
                        showTagForm: candidate.candidateId === this.selectedCandidateId,
                        ownerName: candidate.ownerName || 'N/A',
                        courseSummary: candidate.courseSummary || 'No related leads'
                    }));
                    this.selectedCandidateId = null;
                    this.viewState = 'search';
                } else {
                    this.candidates = [];
                    this.viewState = 'notFound';
                }
            })
            .catch(() => {
                this.candidates = [];
                this.viewState = 'notFound';
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleSearchInput(event) {
        this.searchKeyword = event.target.value;
    }

    handleSearchClick() {
        this.runSearch(this.searchKeyword);
    }

    handleSearchKeyPress(event) {
        if (event.key === 'Enter') {
            this.runSearch(this.searchKeyword);
        }
    }

    selectCandidate(event) {
        this.selectedCandidateId = event.currentTarget.dataset.id;
        this.candidates = this.candidates.map(candidate => ({
            ...candidate,
            cssClass: candidate.candidateId === this.selectedCandidateId ? 'lead-card selected' : 'lead-card',
            showTagForm: candidate.candidateId === this.selectedCandidateId
        }));
        this.setDefaultFollowUpDate();
    }

    handleNameChange(event) {
        this.formData.firstName = event.target.value;
    }

    handleLastNameChange(event) {
        this.formData.lastName = event.target.value;
    }

    handleCourseChange(event) {
        this.formData.course = event.target.value;
    }

    handleCityChange(event) {
        this.formData.city = event.target.value;
    }

    handleSourceChange(event) {
        this.formData.source = event.target.value;
    }

    handleEmailChange(event) {
        this.formData.email = event.target.value;
    }

    handlePhoneChange(event) {
        this.formData.phone = event.target.value;
    }

    handleCountryCodeChange(event) {
        this.formData.countryCode = event.target.value;
    }

    handleCreateFollowUpDateChange(event) {
        this.formData.nextFollowUpDate = event.target.value;
    }



    handleCreateNew() {
        this.viewState = 'create';
        this.setDefaultFollowUpDate();
    }

    handleCancel() {
        this.viewState = 'search';
        this.searchKeyword = '';
        this.candidates = [];
        this.selectedCandidateId = null;
        this.setDefaultFollowUpDate();
        this.formData = {
            firstName: '',
            lastName: '',
            course: '',
            city: '',
            source: '',
            email: '',
            phone: this.phoneNumber,
            countryCode: '+91',
            nextFollowUpDate: this.formData.nextFollowUpDate,
            l1: '',
            l2: '',
            feedback: ''
        };
    }

    closeModal() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    get hasCandidates() {
        return this.candidates.length > 0;
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
        return this.viewState === 'search' && this.hasCandidates;
    }

    get isFormValid() {
        return this.formData.lastName.trim() &&
            this.formData.course.trim() &&
            this.formData.city.trim() &&
            this.formData.source.trim() &&
            this.formData.email.trim() &&
            this.formData.phone.trim();
    }

    get submitButtonLabel() {
        return this.isLoading ? 'Creating...' : 'Create New Lead';
    }

    get tagButtonLabel() {
        return this.isLoading ? 'Tagging...' : 'Tag Candidate';
    }

    get spamButtonLabel() {
        return this.isLoading ? 'Saving...' : 'Mark as Spam';
    }

    get dndButtonLabel() {
        return this.isLoading ? 'Saving...' : 'Mark as DND';
    }

    handleTagLead() {
        if (!this.selectedCandidateId) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: 'Please select a candidate to tag',
                variant: 'error'
            }));
            return;
        }

        this.isLoading = true;

        tagOrCreateLead({
            callLogId: this.recordId,
            candidateId: this.selectedCandidateId,
            name: null,
            course: null,
            email: null,
            phone: null,
            city: null,
            source: null,
            firstName: null,
            lastName: null,
            countryCode: null,
            disableRR: true,
            l1: null,
            l2: null,
            feedback: null,
            nextFollowUpDate: null,
            recordTypeId: this.courseRecordTypeId
        })
            .then(() => {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Success',
                    message: 'Candidate tagged successfully!',
                    variant: 'success'
                }));

                this.closeModal();
            })
            .catch((error) => {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Error',
                    message: 'Failed to tag candidate: ' + (error.body?.message || error.message),
                    variant: 'error'
                }));
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleSubmit() {
        if (!this.isFormValid) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: 'Please fill in all required fields',
                variant: 'error'
            }));
            return;
        }

        if (this.formData.nextFollowUpDate && new Date(this.formData.nextFollowUpDate) < new Date()) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: 'Follow up date cannot be in the past',
                variant: 'error'
            }));
            return;
        }

        this.isLoading = true;
        console.log('handleSubmit: Calling tagOrCreateLead with recordTypeId:', this.courseRecordTypeId);

        tagOrCreateLead({
            callLogId: this.recordId,
            candidateId: null,
            name: [this.formData.firstName, this.formData.lastName].filter(Boolean).join(' '),
            course: this.formData.course,
            email: this.formData.email,
            phone: this.formData.phone,
            city: this.formData.city,
            source: this.formData.source,
            firstName: this.formData.firstName,
            lastName: this.formData.lastName,
            countryCode: this.formData.countryCode,
            disableRR: true,
            l1: this.formData.l1 || null,
            l2: this.formData.l2 || null,
            feedback: this.formData.feedback || null,
            nextFollowUpDate: this.formData.nextFollowUpDate || null,
            recordTypeId: this.courseRecordTypeId
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

    handleMarkSpam() {
        this.updatePhoneNumberStatus(true, false, 'Phone number marked as spam successfully!');
    }

    handleMarkDnd() {
        this.updatePhoneNumberStatus(false, true, 'Phone number marked as DND successfully!');
    }

    updatePhoneNumberStatus(isSpam, isDnd, successMessage) {
        this.isLoading = true;

        markPhoneNumberStatus({
            callLogId: this.recordId,
            isSpam,
            isDnd
        })
            .then(() => {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Success',
                    message: successMessage,
                    variant: 'success'
                }));

                this.closeModal();
            })
            .catch((error) => {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Error',
                    message: error.body?.message || error.message || 'Failed to update phone status',
                    variant: 'error'
                }));
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    @wire(getCityOptions)
    wiredCities({ data, error }) {
        if (data) {
            this.cityOptions = data.map(option => ({
                label: option.label,
                value: option.value
            }));
        } else if (error) {
            console.error('Error loading city options:', error);
        }
    }

    @wire(getSourceOptions)
    wiredSources({ data, error }) {
        if (data) {
            this.sourceOptions = data.map(option => ({
                label: option.label,
                value: option.value
            }));
        } else if (error) {
            console.error('Error loading source options:', error);
        }
    }
}
