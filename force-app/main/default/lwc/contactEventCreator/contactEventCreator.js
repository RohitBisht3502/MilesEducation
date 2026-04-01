import { LightningElement, api, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getObjectInfo, getPicklistValuesByRecordType } from 'lightning/uiObjectInfoApi';
import { CloseActionScreenEvent } from 'lightning/actions';

import getEventPicklistValues from '@salesforce/apex/GoogleMeetService.getEventPicklistValues';
import checkExistingMeetings from '@salesforce/apex/GoogleMeetService.checkExistingMeetings';
import createMeetingWithEvent from '@salesforce/apex/GoogleMeetService.createMeetingWithEvent';
import getCurrentUserInfo from '@salesforce/apex/UserController.getCurrentUserInfo';
import getAvailableUsers from '@salesforce/apex/UserController.getAvailableUsers';
import getMeetingRecordContext from '@salesforce/apex/UserController.getMeetingRecordContext';

import EVENT_OBJECT from '@salesforce/schema/Event';

const ORG_MEETING_EMAIL = 'meetings@mileseducation.com';

export default class ContactEventCreator extends LightningElement {
    _recordId;

    @api
    get recordId() {
        return this._recordId;
    }

    set recordId(value) {
        this._recordId = value;
        if (value) {
            this.loadRecordContext();
        }
    }

    // Form fields
    subject = '';
    subjectManuallyEdited = false;
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
    @track selectedCourses = [];
    @track courseOptions = [];
    @track isCourseDropdownOpen = false;

    // Data
    @track participants = [];
    contactEmail = '';
    candidateName = '';
    currentUserEmail = '';
    currentUserName = '';
    organizerEmail = ORG_MEETING_EMAIL;
    @track availableUsers = [];
    @track participantOptions = [];

    // Picklist options
    @track meetingTypeOptions = [];

    // State
    currentStep = 1;
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

    get hasSelectedCourses() {
        return this.selectedCourses.length > 0;
    }

    get hasSingleCourseOption() {
        return this.courseOptions.length === 1;
    }

    get isStep1() {
        return this.currentStep === 1;
    }

    get isStep2() {
        return this.currentStep === 2;
    }

    get isStep3() {
        return this.currentStep === 3;
    }

    get isStep4() {
        return this.currentStep === 4;
    }

    get isFirstStep() {
        return this.currentStep === 1;
    }

    get isLastStep() {
        return this.currentStep === 4;
    }

    get step1Class() {
        return this.currentStep > 1 ? 'step is-complete' : this.currentStep === 1 ? 'step is-active' : 'step';
    }

    get step2Class() {
        return this.currentStep > 2 ? 'step is-complete' : this.currentStep === 2 ? 'step is-active' : 'step';
    }

    get step3Class() {
        return this.currentStep > 3 ? 'step is-complete' : this.currentStep === 3 ? 'step is-active' : 'step';
    }

    get step4Class() {
        return this.currentStep === 4 ? 'step is-active' : 'step';
    }

    get stepLine1Class() {
        return this.currentStep > 1 ? 'step-line step-line-active' : 'step-line';
    }

    get stepLine2Class() {
        return this.currentStep > 2 ? 'step-line step-line-active' : 'step-line';
    }

    get stepLine3Class() {
        return this.currentStep > 3 ? 'step-line step-line-active' : 'step-line';
    }

    get durationOptions() {
        const isOffline = this.meetingType === 'Offline';
        const values = isOffline ? [30, 45, 60, 90] : [30, 45, 60];

        return values.map(v => ({
            label: `${v} minutes`,
            value: String(v)
        }));
    }

    get selectedCourseSummary() {
        return this.selectedCourses.length ? this.selectedCourses.join(', ') : 'Select courses';
    }

    get computedCourseOptions() {
        return this.courseOptions.map(option => ({
            ...option,
            checked: this.selectedCourses.includes(option.value),
            cssClass: this.selectedCourses.includes(option.value)
                ? 'course-chip course-chip-selected'
                : 'course-chip'
        }));
    }

    connectedCallback() {
        this.loadCurrentUserInfo();
        this.loadAvailableUsers();
        this.loadActivityPicklists();
    }

    async loadRecordContext() {
        if (!this.recordId) {
            return;
        }

        try {
            const recordContext = await getMeetingRecordContext({ recordId: this.recordId });
            this.contactEmail = recordContext?.email || '';
            this.candidateName = recordContext?.name || '';
            this.courseOptions = (recordContext?.availableCourses || []).map(course => ({
                label: course,
                value: course
            }));
            this.selectedCourses = this.selectedCourses.filter(selectedCourse =>
                this.courseOptions.some(option => option.value === selectedCourse)
            );
            this.syncDefaultCourseSelection();

            if (this.contactEmail && this.contactEmail !== this.currentUserEmail) {
                this.addParticipantWithData(this.contactEmail, this.candidateName || 'Record', false, true);
            }
        } catch (error) {
            this.showToast('Error', this.extractErrorMessage(error), 'error');
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
        this.subjectManuallyEdited = true;
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
        this.duration = '45';
    }

    handleCourseDropdownToggle() {
        this.isCourseDropdownOpen = !this.isCourseDropdownOpen;
    }

    handleCourseOptionClick(event) {
        if (this.hasSingleCourseOption) {
            return;
        }

        const courseValue = event.currentTarget.dataset.value;
        if (!courseValue) {
            return;
        }

        if (this.selectedCourses.includes(courseValue)) {
            this.selectedCourses = this.selectedCourses.filter(value => value !== courseValue);
        } else {
            this.selectedCourses = [...this.selectedCourses, courseValue];
        }

        this.clearError();
        this.updateSubjectAndDescription();
    }

    handleCoursePillRemove(event) {
        if (this.hasSingleCourseOption) {
            return;
        }

        const courseValue = event.currentTarget.dataset.value;
        this.selectedCourses = this.selectedCourses.filter(value => value !== courseValue);
        this.clearError();
        this.updateSubjectAndDescription();
    }

    syncDefaultCourseSelection() {
        if (this.courseOptions.length === 1) {
            const onlyCourse = this.courseOptions[0].value;
            this.selectedCourses = [onlyCourse];
            this.updateSubjectAndDescription();
            return;
        }

        this.selectedCourses = this.selectedCourses.filter(selectedCourse =>
            this.courseOptions.some(option => option.value === selectedCourse)
        );
    }

    getDefaultSubject() {
        const purpose = (this.typeOfMeeting || '').trim();
        const recordName = (this.candidateName || '').trim();

        if (purpose && recordName) {
            return `${purpose} - ${recordName}`;
        }

        return purpose || recordName || '';
    }

    updateSubjectAndDescription() {
        const mt = (this.meetingType || '').trim();
        const tom = (this.typeOfMeeting || '').trim();
        const courses = this.selectedCourses.filter(Boolean);

        if (!this.subjectManuallyEdited) {
            this.subject = this.getDefaultSubject();
        }

        if (mt || tom || courses.length) {
            const parts = [];
            if (mt) parts.push(mt);
            if (tom) parts.push(tom);
            if (courses.length) parts.push(`Courses: ${courses.join(', ')}`);
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
                durationMinutes: parseInt(this.duration, 10),
                selectedCourses: this.selectedCourses
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
        return this.validateStep1() && this.validateStep2() && this.validateStep3();
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
        this.subjectManuallyEdited = false;
        this.description = '';
        this.startDateTime = '';
        this.endDateTime = '';
        this.selectedUser = '';
        this.customEmail = '';
        this.duration = '45';
        this.otherTypeOfMeeting = '';
        this.selectedCourses = [];
        this.syncDefaultCourseSelection();

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

    goToNextStep() {
        if (this.currentStep === 1 && !this.validateStep1()) {
            return;
        }

        if (this.currentStep === 2 && !this.validateStep2()) {
            return;
        }

        if (this.currentStep === 3 && !this.validateStep3()) {
            return;
        }

        if (this.currentStep < 4) {
            this.currentStep += 1;
        }
    }

    goToPreviousStep() {
        if (this.currentStep > 1) {
            this.currentStep -= 1;
        }
    }

    validateStep1() {
        if (!this.contactEmail || this.contactEmail.trim() === '') {
            this.showToast('Error', 'Record email is required before scheduling a meeting. Please update the email first.', 'error');
            return false;
        }

        if (!this.selectedCourses.length) {
            this.showToast('Error', 'Please select at least one course', 'error');
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

        if (!this.typeOfMeeting) {
            this.showToast('Error', 'Please select Type of Meeting', 'error');
            return false;
        }

        if (this.showOtherTypeOfMeeting && !this.otherTypeOfMeeting?.trim()) {
            this.showToast('Error', 'Please enter Other Type of Meeting', 'error');
            return false;
        }

        return true;
    }

    validateStep2() {
        if (!this.duration) {
            this.showToast('Error', 'Please select meeting duration', 'error');
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

    validateStep3() {
        if (this.participants.length === 0) {
            this.showToast('Error', 'Please add at least one participant', 'error');
            return false;
        }

        return true;
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

    get participantNamesSummary() {
        const names = this.participants
            .map(participant => (participant.name || participant.email || '').trim())
            .filter(Boolean);
        return names.length ? names.join(', ') : '-';
    }

    get selectedCoursesSummary() {
        return this.selectedCourses.length ? this.selectedCourses.join(', ') : '-';
    }

    get durationSummary() {
        const option = this.durationOptions.find(item => item.value === this.duration);
        return option ? option.label : '-';
    }

    get formattedStartDateTime() {
        return this.formatReviewDateTime(this.startDateTime);
    }

    get formattedEndDateTime() {
        return this.formatReviewDateTime(this.endDateTime);
    }

    get displayParticipants() {
        return this.participants.map(participant => {
            const source = (participant.name || participant.email || '').trim();
            const parts = source.split(/\s+/).filter(Boolean);
            const initials = parts.length > 1
                ? `${parts[0].charAt(0)}${parts[1].charAt(0)}`
                : source.substring(0, 1);

            return {
                ...participant,
                initials: initials.toUpperCase()
            };
        });
    }

    formatReviewDateTime(value) {
        if (!value) {
            return '-';
        }

        const date = new Date(value);
        if (Number.isNaN(date.getTime())) {
            return value;
        }

        return new Intl.DateTimeFormat('en-IN', {
            year: 'numeric',
            month: 'short',
            day: '2-digit',
            hour: '2-digit',
            minute: '2-digit',
            hour12: true
        }).format(date);
    }
}