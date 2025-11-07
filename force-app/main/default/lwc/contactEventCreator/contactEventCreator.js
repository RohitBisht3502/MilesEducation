import { LightningElement, api, wire, track } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import createMeetEvent from '@salesforce/apex/GoogleMeetService.createMeetEvent';
import getCurrentUserInfo from '@salesforce/apex/UserController.getCurrentUserInfo';
import getAvailableUsers from '@salesforce/apex/UserController.getAvailableUsers';

const CONTACT_EMAIL_FIELD = 'Contact.Email';

export default class ContactEventCreator extends LightningElement {
    @api recordId;

    // Form fields
    subject = '';
    description = '';
    startDateTime = '';
    endDateTime = '';
    timezone = 'Asia/Kolkata';
    selectedUser = '';
    customEmail = '';
    
    // Data
    @track participants = [];
    contactEmail = '';
    currentUserEmail = '';
    currentUserName = '';
    @track availableUsers = [];
    @track participantOptions = [];
    
    // State
    isLoading = false;
    showSuccess = false;
    error = '';
    meetingResult = '';

    // Timezone options
    timezoneOptions = [
        { label: 'Asia/Kolkata', value: 'Asia/Kolkata' },
        { label: 'America/New_York', value: 'America/New_York' },
        { label: 'America/Los_Angeles', value: 'America/Los_Angeles' },
        { label: 'Europe/London', value: 'Europe/London' },
        { label: 'Europe/Paris', value: 'Europe/Paris' },
        { label: 'Asia/Tokyo', value: 'Asia/Tokyo' },
        { label: 'Australia/Sydney', value: 'Australia/Sydney' }
    ];

    // Getters
    get hasParticipants() {
        return this.participants.length > 0;
    }

    get isUserAddDisabled() {
        return !this.selectedUser;
    }

    get isEmailAddDisabled() {
        return !this.customEmail;
    }

    connectedCallback() {
        this.loadCurrentUserInfo();
        this.loadAvailableUsers();
    }

    @wire(getRecord, { recordId: '$recordId', fields: [CONTACT_EMAIL_FIELD] })
    wiredContact({ error, data }) {
        if (data) {
            this.contactEmail = getFieldValue(data, CONTACT_EMAIL_FIELD) || '';
            // Auto-add contact email as first participant if it's different from current user
            if (this.contactEmail && this.contactEmail !== this.currentUserEmail) {
                this.addParticipantWithData(this.contactEmail, 'Contact', false);
            }
        } else if (error) {
            this.showToast('Error', 'Error loading contact information', 'error');
        }
    }

    // Load current user information
    async loadCurrentUserInfo() {
        try {
            const userInfo = await getCurrentUserInfo();
            this.currentUserEmail = userInfo.Email;
            this.currentUserName = userInfo.Name;
            
            // Auto-add current user as first participant
            this.addParticipantWithData(this.currentUserEmail, this.currentUserName, true);
            
        } catch (error) {
            console.error('Error loading user info:', error);
        }
    }

    // Load available users for dropdown
    async loadAvailableUsers() {
        try {
            this.availableUsers = await getAvailableUsers();
            this.prepareParticipantOptions();
        } catch (error) {
            console.error('Error loading available users:', error);
        }
    }

    // Prepare dropdown options from available users
    prepareParticipantOptions() {
        // Filter out current user and already added participants
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

    // Input handlers
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
    }

    handleEndDateTimeChange(event) {
        this.endDateTime = event.target.value;
        this.clearError();
    }

    handleTimezoneChange(event) {
        this.timezone = event.detail.value;
    }

    handleUserSelection(event) {
        this.selectedUser = event.detail.value;
        this.clearError();
    }

    handleCustomEmailChange(event) {
        this.customEmail = event.target.value;
        this.clearError();
    }

    // Participant management
    addParticipantWithData(email, name = '', isCurrentUser = false) {
        if (!email) return;

        // Check for duplicates
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

        // Refresh participant options to remove added user
        this.prepareParticipantOptions();
    }

    // Add selected user from dropdown
    addSelectedUser() {
        if (!this.selectedUser) {
            this.error = 'Please select a user from the dropdown';
            return;
        }

        // Find the selected user
        const selectedUserObj = this.availableUsers.find(user => user.Email === this.selectedUser);
        
        if (selectedUserObj) {
            this.addParticipantWithData(selectedUserObj.Email, selectedUserObj.Name, false);
            this.selectedUser = '';
            this.showToast('Success', `${selectedUserObj.Name} added to participants`, 'success');
        }
    }

    // Add custom email
    addCustomEmail() {
        if (!this.customEmail) {
            this.error = 'Please enter an email address';
            return;
        }

        // Basic email validation
        const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
        if (!emailRegex.test(this.customEmail)) {
            this.error = 'Please enter a valid email address';
            return;
        }

        // Check if custom email matches any existing user
        const existingUser = this.availableUsers.find(user => user.Email === this.customEmail);
        
        if (existingUser) {
            this.error = 'This email belongs to an existing user. Please select them from the dropdown instead.';
            return;
        }

        // Add custom email
        this.addParticipantWithData(this.customEmail, '', false);
        this.customEmail = '';
        this.showToast('Success', 'Custom email added to participants', 'success');
        this.clearError();
    }

    removeParticipant(event) {
        const index = event.target.dataset.index;
        const participant = this.participants[index];
        
        // Don't allow removing current user
        if (participant.isCurrentUser) {
            this.showToast('Info', 'You cannot remove yourself as the organizer', 'info');
            return;
        }

        this.participants = this.participants.filter((_, i) => i != index);
        // Refresh participant options as removed user is now available again
        this.prepareParticipantOptions();
    }

    clearAllParticipants() {
        // Keep current user and contact if they exist
        this.participants = this.participants.filter(p => p.isCurrentUser || p.email === this.contactEmail);
        this.prepareParticipantOptions();
    }

    // Main function to create meeting
    async createMeeting() {
        // Validation
        if (!this.validateForm()) {
            return;
        }

        this.isLoading = true;
        this.error = '';
        this.showSuccess = false;

        try {
            // Prepare attendee emails (excluding current user from attendees if they're the organizer)
            const attendeeEmails = this.participants
                .filter(p => !p.isCurrentUser)
                .map(p => p.email);
            
            // Convert local datetime to UTC
            const startUtc = this.convertToUtc(this.startDateTime);
            const endUtc = this.convertToUtc(this.endDateTime);

            // Call Apex method
            const result = await createMeetEvent({
                subject: this.subject,
                description: this.description,
                startUtc: startUtc,
                endUtc: endUtc,
                timeZoneId: this.timezone,
                attendeeEmails: attendeeEmails
            });

            this.meetingResult = result;
            this.showSuccess = true;
            this.showToast('Success', 'Meeting created successfully!', 'success');
            this.clearForm();

        } catch (error) {
            this.error = this.extractErrorMessage(error);
            this.showToast('Error', this.error, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // Utility methods
    validateForm() {
        if (!this.subject) {
            this.error = 'Please enter a meeting subject';
            return false;
        }
        if (!this.startDateTime) {
            this.error = 'Please select start date/time';
            return false;
        }
        if (!this.endDateTime) {
            this.error = 'Please select end date/time';
            return false;
        }
        if (this.participants.length === 0) {
            this.error = 'Please add at least one participant';
            return false;
        }

        // Validate date logic
        const start = new Date(this.startDateTime);
        const end = new Date(this.endDateTime);
        
        if (end <= start) {
            this.error = 'End date/time must be after start date/time';
            return false;
        }

        return true;
    }

    convertToUtc(localDateTimeString) {
        if (!localDateTimeString) return null;
        
        const localDate = new Date(localDateTimeString);
        return new Date(localDate.getTime() - localDate.getTimezoneOffset() * 60000);
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
        // Keep current user and contact
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
}