import { LightningElement, api, wire, track } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getEventPicklistValues
from '@salesforce/apex/GoogleMeetService.getEventPicklistValues';
import checkExistingMeetings from '@salesforce/apex/GoogleMeetService.checkExistingMeetings';


// import { getObjectInfo, getPicklistValues } from 'lightning/uiObjectInfoApi';
import EVENT_OBJECT from '@salesforce/schema/Event';
// import MEETING_TYPE_FIELD from '@salesforce/schema/Event.Meeting_type__c';
// import TYPE_OF_MEETING_FIELD from '@salesforce/schema/Event.Type_of_Meeting__c';

import { getObjectInfo, getPicklistValuesByRecordType } 
from 'lightning/uiObjectInfoApi';


import createMeetingWithEvent from '@salesforce/apex/GoogleMeetService.createMeetingWithEvent';
import getCurrentUserInfo from '@salesforce/apex/UserController.getCurrentUserInfo';
import getAvailableUsers from '@salesforce/apex/UserController.getAvailableUsers';
import { CloseActionScreenEvent } from 'lightning/actions';

const LEAD_EMAIL_FIELD = 'Lead__c.Email__c';
const LEAD_NAME_FIELD  = 'Lead__c.Name';

const ORG_MEETING_EMAIL = 'meetings@mileseducation.com';

export default class ContactEventCreator extends LightningElement {
    @api recordId;

    // Form fields
    subject = '';
    description = '';
    startDateTime = '';
    endDateTime = '';
    timezone = 'Asia/Kolkata';

    // Meeting type / duration
    @track meetingType = '';
    duration = '45'; // default 45 minutes

    selectedUser = '';
    customEmail = '';
    @track typeOfMeeting = '';
    @track typeOfMeetingOptions = [];

    
    // Data
    @track participants = [];
    contactEmail = '';
    currentUserEmail = '';
    currentUserName = '';
    organizerEmail = ORG_MEETING_EMAIL;
    @track availableUsers = [];
    @track participantOptions = [];

    // picklist options
    @track meetingTypeOptions = [];

    // State
    isLoading = false;
    showSuccess = false;
    error = '';
    meetingResult = '';

    @wire(getObjectInfo, { objectApiName: EVENT_OBJECT })
    objectInfo;

    @wire(getPicklistValuesByRecordType, {
        objectApiName: EVENT_OBJECT,
        recordTypeId: '$recordTypeId'
    })
    wiredPicklists({ data, error }) {
        if (data) {
            /* Meeting Type */
            if (data.picklistFieldValues.Meeting_type__c) {
                this.meetingTypeOptions =
                    data.picklistFieldValues.Meeting_type__c.values;
            }

            /* Type of Meeting */
            if (data.picklistFieldValues.Type_of_Meeting__c) {
                this.typeOfMeetingOptions =
                    data.picklistFieldValues.Type_of_Meeting__c.values;
            }
        } else if (error) {
            console.error('Picklist load error', error);
        }
    }

    get recordTypeId() {
        return this.objectInfo?.data?.defaultRecordTypeId;
    }




//     @wire(getPicklistValues, {
//     recordTypeId: '$recordTypeId',
//     fieldApiName: TYPE_OF_MEETING_FIELD
// })
// wiredTypeOfMeeting({ data, error }) {
//     if (data && data.values) {
//         this.typeOfMeetingOptions = data.values.map(v => ({
//             label: v.label,
//             value: v.value
//         }));

//         if (!this.typeOfMeeting && data.defaultValue) {
//             this.typeOfMeeting = data.defaultValue.value;
//         }
//     } else if (error) {
//         console.error('Error loading Type of Meeting picklist', error);
//     }
// }


    // ===== Event picklist wiring =====
    // @wire(getObjectInfo, { objectApiName: EVENT_OBJECT })
    // objectInfo;

    // get recordTypeId() {
    //     return this.objectInfo && this.objectInfo.data
    //         ? this.objectInfo.data.defaultRecordTypeId
    //         : null;
    // }

    // @wire(getPicklistValues, {
    //     recordTypeId: '$recordTypeId',
    //     fieldApiName: MEETING_TYPE_FIELD
    // })
    // wiredMeetingTypeValues({ data, error }) {
    //     if (data && data.values && data.values.length) {
    //         this.meetingTypeOptions = data.values.map(v => ({
    //             label: v.label,
    //             value: v.value
    //         }));
    //         if (!this.meetingType) {
    //             const def = data.defaultValue && data.defaultValue.value
    //                 ? data.defaultValue.value
    //                 : null;
    //             this.meetingType = def || this.meetingTypeOptions[0].value;
    //         }
    //     } else {
    //         this.meetingTypeOptions = [
    //             { label: 'Online', value: 'Online' },
    //             { label: 'Offline', value: 'Offline' }
    //         ];
    //         if (!this.meetingType) {
    //             this.meetingType = 'Online';
    //         }
    //     }
    // }

    // ===== derived getters =====
    get hasParticipants() {
        return this.participants.length > 0;
    }

    get isUserAddDisabled() {
        return !this.selectedUser;
    }

    get isEmailAddDisabled() {
        return !this.customEmail;
    }

    get durationOptions() {
        const isOffline = this.meetingType === 'Offline';
        const values = isOffline ? [30, 45, 60, 90] : [30, 45, 60];
        return values.map(v => ({
            label: `${v} minutes`,
            value: String(v)
        }));
    }

    // ===== lifecycle =====
    connectedCallback() {
        this.loadCurrentUserInfo();
        this.loadAvailableUsers();
        this.loadActivityPicklists();
    }

    @wire(getRecord, { recordId: '$recordId', fields: [LEAD_EMAIL_FIELD, LEAD_NAME_FIELD] })
    wiredLead({ error, data }) {
        if (data) {
            const email = getFieldValue(data, LEAD_EMAIL_FIELD) || '';
            const name  = getFieldValue(data, LEAD_NAME_FIELD) || '';

            this.contactEmail = email;

            if (this.contactEmail && this.contactEmail !== this.currentUserEmail) {
                this.addParticipantWithData(this.contactEmail, name || 'Lead', false);
            }
        } else if (error) {
            this.showToast('Error', 'Error loading lead information', 'error');
        }
    }

    loadActivityPicklists() {
        // Meeting Type (Event)
        getEventPicklistValues({ fieldApiName: 'Meeting_type__c' })
            .then(data => {
                console.log('Meeting type options', data);
                this.meetingTypeOptions = data;
            })
            .catch(error => {
                console.error('Meeting type error', error);
            });

        // Type of Meeting (Event)
        getEventPicklistValues({ fieldApiName: 'Type_of_Meeting__c' })
            .then(data => {
                console.log('Type of meeting options', data);
                this.typeOfMeetingOptions = data;
            })
            .catch(error => {
                console.error('Type of meeting error', error);
            });
    }



    // ===== data loading =====
    async loadCurrentUserInfo() {
        try {
            const userInfo = await getCurrentUserInfo();
            this.currentUserEmail = userInfo.Email;
            this.currentUserName = userInfo.Name;

            this.addParticipantWithData(this.currentUserEmail, this.currentUserName, true);
        } catch (error) {
            console.error('Error loading user info:', error);
        }
    }

    async loadAvailableUsers() {
        try {
            this.availableUsers = await getAvailableUsers();
            this.prepareParticipantOptions();
        } catch (error) {
            console.error('Error loading available users:', error);
        }
    }

    prepareParticipantOptions() {
        const existingParticipantEmails = new Set(this.participants.map(p => p.email));

        this.participantOptions = this.availableUsers
            .filter(user => 
                user.Email !== this.currentUserEmail &&
                !existingParticipantEmails.has(user.Email)
            )
            .map(user => ({
                label: `${user.Name} (${user.Email})`,
                value: user.Email,
                name: user.Name
            }));
    }

    // ===== input handlers =====
    handleSubjectChange(event) {
        this.subject = event.target.value;
        this.clearError();
    }

    handleDescriptionChange(event) {
        this.description = event.target.value;
    }

    handleStartDateTimeChange(event) {
        this.startDateTime = event.target.value;
        this.clearError();
        this.updateEndDateTimeFromDuration();
    }

    handleEndDateTimeChange(event) {
        this.endDateTime = event.target.value;
        this.clearError();
    }

    handleMeetingTypeChange(event) {
        this.meetingType = event.detail.value;
        this.clearError();

        if (!this.durationOptions.find(o => o.value === this.duration)) {
            this.duration = '45';
        }
        this.updateEndDateTimeFromDuration();
    }

    handleDurationChange(event) {
        this.duration = event.detail.value;
        this.clearError();
        this.updateEndDateTimeFromDuration();
    }

    handleUserSelection(event) {
        this.selectedUser = event.detail.value;
        this.clearError();
    }

    handleCustomEmailChange(event) {
        this.customEmail = event.target.value;
        this.clearError();
    }

    // ===== participants =====
    addParticipantWithData(email, name = '', isCurrentUser = false) {
        if (!email) return;

        if (this.participants.some(p => p.email === email)) {
            this.showToast('Info', 'This email is already in the participants list', 'info');
            return;
        }

        this.participants = [
            ...this.participants,
            {
                id: Date.now() + Math.random(),
                email: email,
                name: name,
                isCurrentUser: isCurrentUser
            }
        ];

        this.prepareParticipantOptions();
    }

    addSelectedUser() {
        if (!this.selectedUser) {
            // this.error = 'Please select a user from the dropdown';
            this.showToast('Error', 'Please select a user from the dropdown', 'error');
            return;
        }

        const selectedUserObj = this.availableUsers.find(user => user.Email === this.selectedUser);
        
        if (selectedUserObj) {
            this.addParticipantWithData(selectedUserObj.Email, selectedUserObj.Name, false);
            this.selectedUser = '';
            this.showToast('Success', `${selectedUserObj.Name} added to participants`, 'success');
        }
    }

    addCustomEmail() {
        if (!this.customEmail) {
            // this.error = 'Please enter an email address';
            this.showToast('Error', 'Please enter an email address', 'error');
            return;
        }

        const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
        if (!emailRegex.test(this.customEmail)) {
            // this.error = 'Please enter a valid email address';
            this.showToast('Error', 'Please enter a valid email address', 'error');
            return;
        }

        const existingUser = this.availableUsers.find(user => user.Email === this.customEmail);
        
        if (existingUser) {
            // this.error = 'This email belongs to an existing user. Please select them from the dropdown instead.';
            this.showToast('Error', 'This email belongs to an existing user. Please select them from the dropdown instead.', 'error');
            return;
        }

        this.addParticipantWithData(this.customEmail, '', false);
        this.customEmail = '';
        this.showToast('Success', 'Custom email added to participants', 'success');
        this.clearError();
    }

    removeParticipant(event) {
        const index = event.target.dataset.index;
        const participant = this.participants[index];

        if (participant.isCurrentUser) {
            this.showToast('Info', 'You cannot remove yourself as the organizer', 'info');
            return;
        }

        this.participants = this.participants.filter((_, i) => i != index);
        this.prepareParticipantOptions();
    }

    clearAllParticipants() {
        this.participants = this.participants.filter(p => p.isCurrentUser || p.email === this.contactEmail);
        this.prepareParticipantOptions();
    }

    // ===== time calc: start + duration => end =====
    updateEndDateTimeFromDuration() {
        if (!this.startDateTime || !this.duration) return;

        try {
            const start = new Date(this.startDateTime);
            const mins = parseInt(this.duration, 10);
            if (isNaN(mins)) return;

            const end = new Date(start.getTime() + mins * 60000);

            const year = end.getFullYear();
            const month = String(end.getMonth() + 1).padStart(2, '0');
            const day = String(end.getDate()).padStart(2, '0');
            const hours = String(end.getHours()).padStart(2, '0');
            const minutes = String(end.getMinutes()).padStart(2, '0');

            this.endDateTime = `${year}-${month}-${day}T${hours}:${minutes}`;
        } catch (e) {
            // ignore
        }
    }

    // ===== main save =====
    // ===== main save =====
    async createMeeting() {
        if (!this.validateForm()) {
            return;
        }

        this.isLoading = true;
        // this.error = '';
        this.showSuccess = false;

        try {

            // Convert string to Date objects
            const startDate = new Date(this.startDateTime);
            const endDate = new Date(this.endDateTime);
            
            // Check for duplicate meeting
            const hasDuplicate = await checkExistingMeetings({
                startUtc: startDate,    // Pass as Date object
                endUtc: endDate         // Pass as Date object
            });
            
            if (hasDuplicate) {
                this.isLoading = false;
                this.showToast('Error', 'A meeting already exists at this exact time. Please choose a different time slot.', 'error');
                return;
            }
            
            const emailsSet = new Set();

            this.participants.forEach(p => {
                if (p.email) {
                    emailsSet.add(p.email);
                }
            });

            // always include org email
            emailsSet.add(ORG_MEETING_EMAIL);

            const attendeeEmails = Array.from(emailsSet);

            // 🔹 Convert to proper ISO strings for Apex Datetime params
            const startIso = new Date(this.startDateTime).toISOString();
            const endIso   = new Date(this.endDateTime).toISOString();

            const result = await createMeetingWithEvent({
                recordId: this.recordId,
                subject: this.subject,
                description: this.description,
                startUtc: startIso,
                endUtc: endIso,
                timeZoneId: this.timezone,
                attendeeEmails: attendeeEmails,
                meetingType: this.meetingType,
                typeOfMeeting: this.typeOfMeeting,
                durationMinutes: parseInt(this.duration, 10)
            });

            this.meetingResult = result;
            this.showSuccess = true;
            this.showToast('Success', 'Meeting created successfully!', 'success');
            this.clearForm();
            this.dispatchEvent(new CloseActionScreenEvent());
            setTimeout(() => window.location.reload(), 800);

        } catch (error) {
            // this.error = this.extractErrorMessage(error);
            // this.showToast('Error', this.error, 'error');
            const errorMessage = this.extractErrorMessage(error);
            this.showToast('Error', errorMessage, 'error');
        } finally {
            this.isLoading = false;
        }
    }


    // ===== validation / utils =====
    validateForm() {
        if (!this.subject) {
            // this.error = 'Please enter a meeting subject';
            this.showToast('Error', 'Please enter a meeting subject', 'error');
            return false;
        }
        if (!this.meetingType) {
            // this.error = 'Please select a Meeting Type';
            this.showToast('Error', 'Please select a Meeting Type', 'error');
            return false;
        }
        if (!this.startDateTime) {
            // this.error = 'Please select start date/time';
            this.showToast('Error', 'Please select start date/time', 'error');
            return false;
        }
        if (!this.endDateTime) {
            // this.error = 'Please select end date/time';
            this.showToast('Error', 'Please select end date/time', 'error');
            return false;
        }
        if (!this.duration) {
            // this.error = 'Please select meeting duration';
            this.showToast('Error', 'Please select meeting duration', 'error');
            return false;
        }
        if (this.participants.length === 0) {
            // this.error = 'Please add at least one participant';
            this.showToast('Error', 'Please add at least one participant', 'error');
            return false;
        }
        if (!this.typeOfMeeting) {
            // this.error = 'Please select Type of Meeting';
            this.showToast('Error', 'Please select Type of Meeting', 'error');
            return false;
        }


        const start = new Date(this.startDateTime);
        const end = new Date(this.endDateTime);
        const now = new Date();

        if (start < now) {
            // this.error = 'Start date/time cannot be in the past';
            this.showToast('Error', 'Start date/time cannot be in the past', 'error');
            return false;
        }
        if (end < now) {
            // this.error = 'End date/time cannot be in the past';
            this.showToast('Error', 'End date/time cannot be in the past', 'error');
            return false;
        }

        if (end <= start) {
            // this.error = 'End date/time must be after start date/time';
            this.showToast('Error', 'End date/time must be after start date/time', 'error');
            return false;
        }

        return true;
    }

    extractErrorMessage(error) {
        let message = 'Unknown error occurred';
        
        if (error.body) {
            if (error.body.message) {
                message = error.body.message;
            } else if (error.body.pageErrors && error.body.pageErrors.length > 0) {
                message = error.body.pageErrors[0].message;
            } else if (error.body.fieldErrors) {
                const fieldErrors = Object.values(error.body.fieldErrors).flat();
                if (fieldErrors.length > 0) {
                    message = fieldErrors[0].message;
                }
            }
        } else if (error.message) {
            message = error.message;
        }
        
        return message;
    }

    clearForm() {
        this.subject = '';
        this.description = '';
        this.startDateTime = '';
        this.endDateTime = '';
        this.selectedUser = '';
        this.customEmail = '';
        this.duration = '45';

        this.participants = this.participants.filter(p => p.isCurrentUser || p.email === this.contactEmail);
        this.prepareParticipantOptions();
    }

    clearAll() {
        this.clearForm();
        this.error = '';
        this.showSuccess = false;
    }

    clearError() {
        this.error = '';
    }

    showToast(title, message, variant) {
        const event = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant
        });
        this.dispatchEvent(event);
    }

    handleTypeOfMeetingChange(event) {
        this.typeOfMeeting = event.detail.value;
        this.clearError();
    }

}