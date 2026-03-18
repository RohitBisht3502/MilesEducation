import { LightningElement, api, wire, track } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getObjectInfo, getPicklistValuesByRecordType } from 'lightning/uiObjectInfoApi';
import { CloseActionScreenEvent } from 'lightning/actions';

import getEventPicklistValues from '@salesforce/apex/GoogleMeetService.getEventPicklistValues';
import checkExistingMeetings from '@salesforce/apex/GoogleMeetService.checkExistingMeetings';
import createMeetingWithEvent from '@salesforce/apex/GoogleMeetService.createMeetingWithEvent';
import getCurrentUserInfo from '@salesforce/apex/UserController.getCurrentUserInfo';
import getAvailableUsers from '@salesforce/apex/UserController.getAvailableUsers';

import EVENT_OBJECT from '@salesforce/schema/Event';

const LEAD_EMAIL_FIELD = 'Lead__c.Email__c';
const LEAD_NAME_FIELD = 'Lead__c.Name';
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
    duration = '45';

    selectedUser = '';
    customEmail = '';
    @track typeOfMeeting = '';
    @track otherTypeOfMeeting = '';
    @track typeOfMeetingOptions = [];

    // Data
    @track participants = [];
    contactEmail = '';
    currentUserEmail = '';
    currentUserName = '';
    organizerEmail = ORG_MEETING_EMAIL;
    @track availableUsers = [];
    @track participantOptions = [];

    // Picklist options
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
            if (data.picklistFieldValues.Meeting_type__c) {
                this.meetingTypeOptions = data.picklistFieldValues.Meeting_type__c.values;
            }

            if (data.picklistFieldValues.Type_of_Meeting__c) {
                this.typeOfMeetingOptions = data.picklistFieldValues.Type_of_Meeting__c.values;
            }
        } else if (error) {
            console.error('Picklist load error', error);
        }
    }

    get recordTypeId() {
        return this.objectInfo?.data?.defaultRecordTypeId;
    }

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

    connectedCallback() {
        this.loadCurrentUserInfo();
        this.loadAvailableUsers();
        this.loadActivityPicklists();
    }

    @wire(getRecord, { recordId: '$recordId', fields: [LEAD_EMAIL_FIELD, LEAD_NAME_FIELD] })
    wiredLead({ error, data }) {
        if (data) {
            const email = getFieldValue(data, LEAD_EMAIL_FIELD) || '';
            const name = getFieldValue(data, LEAD_NAME_FIELD) || '';

            this.contactEmail = email;

            if (this.contactEmail && this.contactEmail !== this.currentUserEmail) {
                this.addParticipantWithData(this.contactEmail, name || 'Lead', false, true);
            }
        } else if (error) {
            this.showToast('Error', 'Error loading lead information', 'error');
        }
    }

    loadActivityPicklists() {
        getEventPicklistValues({ fieldApiName: 'Meeting_type__c' })
            .then(data => {
                console.log('Meeting type options', data);
                this.meetingTypeOptions = data;
            })
            .catch(error => {
                console.error('Meeting type error', error);
            });

        getEventPicklistValues({ fieldApiName: 'Type_of_Meeting__c' })
            .then(data => {
                console.log('Type of meeting options', data);
                this.typeOfMeetingOptions = data;
            })
            .catch(error => {
                console.error('Type of meeting error', error);
            });
    }

    async loadCurrentUserInfo() {
        try {
            const userInfo = await getCurrentUserInfo();
            this.currentUserEmail = userInfo.Email;
            this.currentUserName = userInfo.Name;

            this.addParticipantWithData(this.currentUserEmail, this.currentUserName, true);

            const skipEmail = new Set([
                this.currentUserEmail,
                this.contactEmail
            ]);

            const managerEmail = userInfo?.Manager?.Email;
            const managerName = userInfo?.Manager?.Name || 'Manager';

            if (managerEmail && !skipEmail.has(managerEmail)) {
                this.addParticipantWithData(managerEmail, managerName, false, false);
            }
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
            .filter(
                user =>
                    user.Email !== this.currentUserEmail &&
                    !existingParticipantEmails.has(user.Email)
            )
            .map(user => ({
                label: `${user.Name} (${user.Email})`,
                value: user.Email,
                name: user.Name
            }));
    }

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
        this.updateSubjectAndDescription();

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

    updateSubjectAndDescription() {
        const mt = (this.meetingType || '').trim();
        const tom = (this.typeOfMeeting || '').trim();

        if (tom) {
            this.subject = tom;
        }

        if (mt || tom) {
            const parts = [];
            if (mt) parts.push(mt);
            if (tom) parts.push(tom);
            this.description = parts.join(' - ');
        }
    }

    handleUserSelection(event) {
        this.selectedUser = event.detail.value;
        this.clearError();
    }

    handleCustomEmailChange(event) {
        this.customEmail = event.target.value;
        this.clearError();
    }

    addParticipantWithData(email, name = '', isCurrentUser = false, isLead = false) {
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
                isCurrentUser: isCurrentUser,
                isLead: isLead,
                canRemove: !(isCurrentUser || isLead)
            }
        ];

        this.prepareParticipantOptions();
    }

    addSelectedUser() {
        if (!this.selectedUser) {
            this.showToast('Error', 'Please select a user from the dropdown', 'error');
            return;
        }

        const selectedUserObj = this.availableUsers.find(
            user => user.Email === this.selectedUser
        );

        if (selectedUserObj) {
            this.addParticipantWithData(selectedUserObj.Email, selectedUserObj.Name, false);
            this.selectedUser = '';
            this.showToast('Success', `${selectedUserObj.Name} added to participants`, 'success');
        }
    }

    addCustomEmail() {
        if (!this.customEmail) {
            this.showToast('Error', 'Please enter an email address', 'error');
            return;
        }

        const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
        if (!emailRegex.test(this.customEmail)) {
            this.showToast('Error', 'Please enter a valid email address', 'error');
            return;
        }

        const existingUser = this.availableUsers.find(
            user => user.Email === this.customEmail
        );

        if (existingUser) {
            this.showToast(
                'Error',
                'This email belongs to an existing user. Please select them from the dropdown instead.',
                'error'
            );
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

        if (participant.isCurrentUser || participant.isLead) {
            this.showToast('Info', 'You cannot remove this participant', 'info');
            return;
        }

        this.participants = this.participants.filter((_, i) => i != index);
        this.prepareParticipantOptions();
    }

    clearAllParticipants() {
        this.participants = this.participants.filter(
            p => p.isCurrentUser || p.email === this.contactEmail
        );
        this.prepareParticipantOptions();
    }

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

    async createMeeting() {
        this.updateSubjectAndDescription();

        if (!this.validateForm()) {
            return;
        }

        this.isLoading = true;
        this.showSuccess = false;

        try {
            const startDate = new Date(this.startDateTime);
            const endDate = new Date(this.endDateTime);

            const hasDuplicate = await checkExistingMeetings({
                startUtc: startDate,
                endUtc: endDate
            });

            if (hasDuplicate) {
                this.isLoading = false;
                this.showToast(
                    'Error',
                    'A meeting already exists at this exact time. Please choose a different time slot.',
                    'error'
                );
                return;
            }

            const emailsSet = new Set();

            this.participants.forEach(p => {
                if (p.email) {
                    emailsSet.add(p.email);
                }
            });

            emailsSet.add(ORG_MEETING_EMAIL);

            const attendeeEmails = Array.from(emailsSet);
            const attendeeList = this.participants
                .filter(p => p && p.email)
                .map(p => {
                    const name = (p.name || '').trim();
                    const email = (p.email || '').trim();
                    return name ? `${name} - ${email}` : email;
                })
                .join(', ');

            const startIso = new Date(this.startDateTime).toISOString();
            const endIso = new Date(this.endDateTime).toISOString();

            const result = await createMeetingWithEvent({
                recordId: this.recordId,
                subject: this.subject,
                description: this.description,
                startUtc: startIso,
                endUtc: endIso,
                timeZoneId: this.timezone,
                attendeeEmails: attendeeEmails,
                attendeeList: attendeeList,
                meetingType: this.meetingType,
                typeOfMeeting: this.typeOfMeeting,
                otherTypeOfMeeting: this.otherTypeOfMeeting,
                durationMinutes: parseInt(this.duration, 10)
            });

            this.meetingResult = result;
            this.showSuccess = true;
            this.showToast('Success', 'Meeting created successfully!', 'success');
            this.clearForm();
            this.dispatchEvent(new CloseActionScreenEvent());
            setTimeout(() => window.location.reload(), 800);
        } catch (error) {
            const errorMessage = this.extractErrorMessage(error);
            this.showToast('Error', errorMessage, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    validateForm() {
        if (!this.contactEmail || this.contactEmail.trim() === '') {
            this.showToast(
                'Error',
                'Lead email is required before scheduling a meeting. Please update Lead email first.',
                'error'
            );
            return false;
        }

        if (!this.subject) {
            this.showToast('Error', 'Please enter a meeting subject', 'error');
            return false;
        }

        if (!this.meetingType) {
            this.showToast('Error', 'Please select a Meeting Type', 'error');
            return false;
        }

        if (!this.startDateTime) {
            this.showToast('Error', 'Please select start date/time', 'error');
            return false;
        }

        if (!this.endDateTime) {
            this.showToast('Error', 'Please select end date/time', 'error');
            return false;
        }

        if (!this.duration) {
            this.showToast('Error', 'Please select meeting duration', 'error');
            return false;
        }

        if (this.participants.length === 0) {
            this.showToast('Error', 'Please add at least one participant', 'error');
            return false;
        }

        if (!this.typeOfMeeting) {
            this.showToast('Error', 'Please select Type of Meeting', 'error');
            return false;
        }

        if (this.showOtherTypeOfMeeting && !this.otherTypeOfMeeting?.trim()) {
            this.showToast('Error', 'Please enter Other Type of Meeting', 'error');
            return false;
        }

        const start = new Date(this.startDateTime);
        const end = new Date(this.endDateTime);
        const now = new Date();

        if (start < now) {
            this.showToast('Error', 'Start date/time cannot be in the past', 'error');
            return false;
        }

        if (end < now) {
            this.showToast('Error', 'End date/time cannot be in the past', 'error');
            return false;
        }

        if (end <= start) {
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
        this.otherTypeOfMeeting = '';

        this.participants = this.participants.filter(
            p => p.isCurrentUser || p.email === this.contactEmail
        );
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

        if (!this.showOtherTypeOfMeeting) {
            this.otherTypeOfMeeting = '';
        }

        this.updateSubjectAndDescription();
        this.clearError();
    }

    handleOtherTypeOfMeetingChange(event) {
        this.otherTypeOfMeeting = event.target.value;
        this.clearError();
    }

    get showOtherTypeOfMeeting() {
        return (this.typeOfMeeting || '').toLowerCase() === 'other';
    }
}