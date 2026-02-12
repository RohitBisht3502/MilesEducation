/**
 * @File Name          : webinarAttendedLeads.js
 * @Description        : Fixed LWC for Webinar Dashboard - Live sync marks absent, live GM metrics with attendance rate
 * @Author             : Dheeraj Kumar
 * @Last Modified On   : Nov 27, 2025
 * @Fixed Issues       : 1. Emails not in live sync are marked as Absent (frontend only)
 *                       2. All metrics update live after sync
 *                       3. GM SPOC table includes live Attendance Rate column
 **/

import { LightningElement, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getActiveWebinarAttendees from '@salesforce/apex/WebinarController.getActiveWebinarAttendees';
import getActiveWebinarAttendeesForUser from '@salesforce/apex/WebinarController.getActiveWebinarAttendeesForUser';
import getManagedUsers from '@salesforce/apex/WebinarController.getManagedUsers';
import syncLiveWebinarAttendees from '@salesforce/apex/WebinarController.syncLiveWebinarAttendees';
import getWebinarsByNameOnly from '@salesforce/apex/WebinarController.getWebinarsByNameOnly';

// Constants
const STATUS = {
    ALL: 'All',
    PRESENT: 'Present',
    ABSENT: 'Absent',
     SCHEDULED: 'Scheduled'
};

const STATUS_OPTIONS = [
    { label: 'All', value: STATUS.ALL },
    { label: 'Present', value: STATUS.PRESENT },
    { label: 'Absent', value: STATUS.ABSENT }
];

const TOAST_VARIANT = {
    SUCCESS: 'success',
    ERROR: 'error',
    WARNING: 'warning',
    INFO: 'info'
};

const STATUS_BADGE_MAP = {
    [STATUS.PRESENT]: 'status-badge status-badge--success',
    [STATUS.ABSENT]: 'status-badge status-badge--error',
   [STATUS.SCHEDULED]: 'status-badge status-badge--info'

};

export default class WebinarAttendedLeads extends LightningElement {
    // Tracked Properties
    @track webinarData = [];
    @track filteredData = [];
    @track searchTerm = '';
    @track statusFilter = STATUS.ALL;
    @track statusFilterForSpoc = null; // New: Filter for SPOC quick view
    @track selectedSpocId = null;
    @track managedUsers = [];
    @track spocSummaryData = [];
    @track isLoading = false;
    @track isSyncing = false;
    @track isGM = false;
    @track selectedWebinarId = null;
    @track selectedWebinarName = null;
    @track activeWebinarId = null;
    @track liveAttendeeEmails = new Set();
    @track allWebinarData = [];
    @track webinarOptions = [];
    @track showWebinarSelection = true;
    @track hasLiveSyncOccurred = false;
    @track showCallModal = false;
    @track selectedLeadForCall = null;
    @track metrics = {
        totalRegistrations: 0,
        attended: 0,
        attendanceRate: 0,
        pendingFollowups: 0
    };

    // Static Properties
    statusOptions = STATUS_OPTIONS;

    // -------------------------
    // LIFECYCLE HOOKS
    // -------------------------
    connectedCallback() {
        this.loadWebinars();
    }

    // -------------------------
    // LOAD WEBINARS
    // -------------------------
    async loadWebinars() {
        this.isLoading = true;
        try {
            const webinars = await getWebinarsByNameOnly();

            if (webinars && webinars.length > 0) {
                this.webinarOptions = webinars.map(w => ({
                    label: w.name,
                    value: w.webinarId
                }));
            } else {
                this.showToast('Info', 'No active webinars found', TOAST_VARIANT.INFO);
            }

            // Check if user is GM
            const users = await getManagedUsers();
            if (users && users.length > 0) {
                this.isGM = true;
                this.managedUsers = users;
            }
        } catch (error) {
            this.handleError(error);
        } finally {
            this.isLoading = false;
        }
    }

    // -------------------------
    // WEBINAR SELECTION HANDLER
    // -------------------------
    handleWebinarChange(event) {
        this.selectedWebinarId = event.detail.value;
        this.selectedWebinarName = this.webinarOptions.find(w => w.value === this.selectedWebinarId)?.label;
        this.activeWebinarId = this.selectedWebinarId;
        this.showWebinarSelection = false;

        // Sync live data immediately after webinar selection
        this.syncAndLoadData();
    }

    async syncAndLoadData() {
        if (!this.selectedWebinarId) {
            return;
        }

        this.isLoading = true;
        try {
            // First, sync live attendees to get live emails
            await this.handleSyncLiveAttendees();

            // Then load the data with webinarId filter
            if (this.isGM) {
                await this.loadAllSpocsData();
                this.filteredData = [];
            } else {
                const data = await getActiveWebinarAttendees({ webinarId: this.selectedWebinarId });
                this.processWebinarData(data);
            }
        } catch (error) {
            this.handleError(error);
        } finally {
            this.isLoading = false;
        }
    }

    async loadAllSpocsData() {
        try {
            // Fetch data for current user (GM) with webinarId filter
            const currentUserData = await getActiveWebinarAttendees({ webinarId: this.selectedWebinarId });
            let allData = [...currentUserData];

            // Fetch data for each managed user with webinarId filter
            for (const user of this.managedUsers) {
                try {
                    const userData = await getActiveWebinarAttendeesForUser({
                        userId: user.Id,
                        webinarId: this.selectedWebinarId
                    });
                    allData = [...allData, ...userData];
                } catch (error) {
                    console.log(`Error fetching data for user ${user.Name}:`, error);
                }
            }

            // Store all data for GM metrics
            this.allWebinarData = this.removeDuplicates(allData);

            // Extract active webinar ID
            if (this.allWebinarData.length > 0 && this.allWebinarData[0].webinarId) {
                this.activeWebinarId = this.allWebinarData[0].webinarId;
            }

            // Apply live attendee status BEFORE calculating metrics
            this.applyLiveAttendeeStatus();

            // Calculate metrics and build summary AFTER applying live status
            this.calculateGMMetrics();
            this.buildSpocSummary();
        } catch (error) {
            throw error;
        }
    }

    removeDuplicates(data) {
        const uniqueDataMap = new Map();

        data.forEach(item => {
            const emailKey = item.email ? item.email.toLowerCase().trim() : `no-email-${item.webinarMemberId}`;

            if (!uniqueDataMap.has(emailKey)) {
                uniqueDataMap.set(emailKey, item);
            } else {
                const existing = uniqueDataMap.get(emailKey);
                if (existing.status === 'Absent' && item.status === 'Present') {
                    uniqueDataMap.set(emailKey, item);
                }
            }
        });

        return Array.from(uniqueDataMap.values());
    }

    buildSpocSummary() {
        const spocMap = new Map();

        // Add current user (GM)
        const currentUserId = this.managedUsers.length > 0 ? this.managedUsers[0].ManagerId : null;
        const gmData = this.allWebinarData.filter(item => item.spocId === currentUserId);

        if (gmData.length > 0 && currentUserId) {
            const present = gmData.filter(item => item.status === STATUS.PRESENT).length;
            const absent = gmData.filter(item => item.status === STATUS.ABSENT).length;
            const total = gmData.length;
            const attendanceRate = this.calculatePercentage(present, total);

            spocMap.set(currentUserId, {
                spocId: currentUserId,
                spocName: gmData[0].spocName || 'GM (Self)',
                totalRegistrations: total,
                present: present,
                absent: absent,
                attendanceRate: attendanceRate
            });
        }

        // Add managed users
        this.managedUsers.forEach(user => {
            const userData = this.allWebinarData.filter(item => item.spocId === user.Id);
            const present = userData.filter(item => item.status === STATUS.PRESENT).length;
            const absent = userData.filter(item => item.status === STATUS.ABSENT).length;
            const total = userData.length;
            const attendanceRate = this.calculatePercentage(present, total);

            spocMap.set(user.Id, {
                spocId: user.Id,
                spocName: user.Name,
                totalRegistrations: total,
                present: present,
                absent: absent,
                attendanceRate: attendanceRate
            });
        });

        this.spocSummaryData = Array.from(spocMap.values());
    }

    // -------------------------
    // LIVE SYNC HANDLER
    // -------------------------
    async handleSyncLiveAttendees() {
        if (!this.activeWebinarId) {
            this.showToast('Error', 'No active webinar found', TOAST_VARIANT.ERROR);
            return;
        }

        this.isSyncing = true;
        try {
            const result = await syncLiveWebinarAttendees({ webinarId: this.activeWebinarId });

            // Store live attendee emails from the API response
            if (result && result.liveEmails && Array.isArray(result.liveEmails)) {
                this.liveAttendeeEmails = new Set(
                    result.liveEmails.map(email => email.toLowerCase().trim())
                );
                this.hasLiveSyncOccurred = true;
            }

            // Apply live status to allWebinarData for GM
            if (this.isGM) {
                this.applyLiveAttendeeStatus();
                this.calculateGMMetrics();
                this.buildSpocSummary();
            }

            // Reload current view with updated live status
            if (this.selectedSpocId) {
                const data = this.allWebinarData.filter(item => item.spocId === this.selectedSpocId);
                this.processWebinarData(data);
            } else if (!this.isGM) {
    // For non-GM users — SAFE status handling (keeps Scheduled)

    const data = this.webinarData.map(item => {
        const emailLower = item.email ? item.email.toLowerCase().trim() : '';
        const isLiveAttendee = this.liveAttendeeEmails.has(emailLower);

        let finalStatus;

        if (item.status) {
            finalStatus = item.status;   // Present/Absent from DB
        } 
        else if (this.hasLiveSyncOccurred) {
            finalStatus = isLiveAttendee ? STATUS.PRESENT : STATUS.ABSENT;
        } 
        else {
            finalStatus = STATUS.SCHEDULED;   
        }

        return {
            ...item,
            status: finalStatus,
            statusBadgeClass: this.getStatusBadgeClass(finalStatus),
            showCallButton: true
        };
    });

    this.webinarData = data;
    this.applyFilters();
}

            this.showToast(
                'Success',
                `Synced successfully! Found ${result.liveAttendeesCount} live attendees.`,
                TOAST_VARIANT.SUCCESS
            );
        } catch (error) {
            this.handleError(error);
        } finally {
            this.isSyncing = false;
        }
    }

    handleBackToWebinarSelection() {
        this.showWebinarSelection = true;
        this.selectedWebinarId = null;
        this.selectedWebinarName = null;
        this.activeWebinarId = null;
        this.selectedSpocId = null;
        this.statusFilterForSpoc = null;
        this.webinarData = [];
        this.filteredData = [];
        this.allWebinarData = [];
        this.spocSummaryData = [];
        this.liveAttendeeEmails = new Set();
        this.hasLiveSyncOccurred = false;
        this.metrics = {
            totalRegistrations: 0,
            attended: 0,
            attendanceRate: 0,
            pendingFollowups: 0
        };
    }

    // -------------------------
    // APPLY LIVE ATTENDEE STATUS
    // -------------------------
applyLiveAttendeeStatus() {
    if (!this.allWebinarData.length || !this.hasLiveSyncOccurred) return;

    this.allWebinarData = this.allWebinarData.map(item => {
        const emailLower = item.email ? item.email.toLowerCase().trim() : '';
        const isLiveAttendee = this.liveAttendeeEmails.has(emailLower);

        let finalStatus;

        if (item.status) {
            finalStatus = item.status;   // from DB only
        } else {
            finalStatus = isLiveAttendee 
                ? STATUS.PRESENT 
                : STATUS.SCHEDULED;   
        }
        if (webinarEnded) {
   finalStatus = STATUS.ABSENT;
}


        return {
            ...item,
            status: finalStatus,
            statusBadgeClass: this.getStatusBadgeClass(finalStatus),
            showCallButton: true
        };
    });
}


    // -------------------------
    // SPOC TABLE HANDLERS
    // -------------------------
    async handleViewSpocData(event) {
        const spocId = event.currentTarget ? event.currentTarget.dataset.spocId : event;
        this.selectedSpocId = spocId;
        this.statusFilterForSpoc = null; // Reset status filter when clicking View
        this.isLoading = true;

        try {
            let data;
            if (this.isGM) {
                // Filter from already loaded data (already has live status applied)
                data = this.allWebinarData.filter(item => item.spocId === spocId);
            } else {
                data = await getActiveWebinarAttendeesForUser({
                    userId: spocId,
                    webinarId: this.selectedWebinarId
                });
            }

            this.processWebinarData(data);
        } catch (error) {
            this.handleError(error);
        } finally {
            this.isLoading = false;
        }
    }

    // NEW: Handle quick view by clicking on numbers in SPOC table
    handleSpocQuickView(event) {
        const spocId = event.currentTarget.dataset.spocId;
        const filterType = event.currentTarget.dataset.filterType;

        this.selectedSpocId = spocId;
        this.isLoading = true;

        try {
            // Filter data for this SPOC
            const data = this.allWebinarData.filter(item => item.spocId === spocId);

            // Set the status filter based on which number was clicked
            if (filterType === 'present') {
                this.statusFilterForSpoc = STATUS.PRESENT;
                this.statusFilter = STATUS.PRESENT; // Sync with main filter
            } else if (filterType === 'absent') {
                this.statusFilterForSpoc = STATUS.ABSENT;
                this.statusFilter = STATUS.ABSENT; // Sync with main filter
            } else if (filterType === 'total') {
                this.statusFilterForSpoc = STATUS.ALL;
                this.statusFilter = STATUS.ALL; // Sync with main filter
            }

            // Process the data (filtering will happen in processWebinarData)
            this.processWebinarData(data);
        } catch (error) {
            this.handleError(error);
        } finally {
            this.isLoading = false;
        }
    }

    // -------------------------
    // EVENT HANDLERS
    // -------------------------
    handleSearchChange(event) {
        this.searchTerm = event.target.value.toLowerCase();
        this.applyFilters();
    }

    handleStatusFilter(event) {
        const newStatus = event.currentTarget.dataset.value;
        if (this.isValidStatus(newStatus) && newStatus !== this.statusFilter) {
            this.statusFilter = newStatus;
            this.statusFilterForSpoc = null; // Clear SPOC filter when manually changing filter
            this.applyFilters();
        }
    }

    handleCall(event) {
        const leadId = event.currentTarget.dataset.leadid;
        const leadName = event.currentTarget.dataset.leadname;
        const leadEmail = event.currentTarget.dataset.email;
        const leadPhone = event.currentTarget.dataset.phone;

        this.selectedLeadForCall = {
            leadId,
            leadName,
            leadEmail,
            leadPhone
        };

        this.showCallModal = true;
    }

    handleCloseCallModal() {
        this.showCallModal = false;
        this.selectedLeadForCall = null;
    }

    handleFeedbackSaved() {
        this.showCallModal = false;
        this.selectedLeadForCall = null;

        // Reload data after feedback is saved
        if (this.isGM) {
            this.loadAllSpocsData();
        } else {
            this.syncAndLoadData();
        }

        this.showToast('Success', 'Call feedback saved and data refreshed', 'success');
    }

    // -------------------------
    // DATA PROCESSING
    // -------------------------
    processWebinarData(data) {
        try {
            const uniqueData = this.removeDuplicates(data);

            // Extract active webinar ID
            if (uniqueData.length > 0 && uniqueData[0].webinarId) {
                this.activeWebinarId = uniqueData[0].webinarId;
            }

            this.webinarData = uniqueData.map(item => this.enrichWebinarItem(item));

            // Apply the current status filter
            this.applyFilters();

            if (!this.isGM) {
                this.calculateMetrics();
            }
        } catch (error) {
            this.logError('Error processing webinar data', error);
            this.showToast('Error', 'Failed to process webinar data', TOAST_VARIANT.ERROR);
        }
    }

   enrichWebinarItem(item) {
    const emailLower = item.email ? item.email.toLowerCase().trim() : '';
    const isLiveAttendee = this.liveAttendeeEmails.has(emailLower);

    let finalStatus;

    // If attendance not marked yet
    if (!item.status) {
        if (this.hasLiveSyncOccurred) {
            finalStatus = isLiveAttendee ? STATUS.PRESENT : STATUS.ABSENT;
        } else {
            finalStatus = STATUS.SCHEDULED;   // ✅ THIS IS YOUR REQUIREMENT
        }
    } else {
        finalStatus = item.status; // Present or Absent from DB
    }

    return {
        ...item,
        studentInitials: this.generateInitials(item.leadName),
        formattedDate: this.formatDate(item.createdDate),
        status: finalStatus,
        statusBadgeClass: this.getStatusBadgeClass(finalStatus),
        spocName: item.spocName || 'Not Assigned',
        spocId: item.spocId,
        showCallButton: true
    };
}

    handleError(error) {
        this.logError('Error fetching webinar data', error);
        const errorMessage = this.extractErrorMessage(error);
        this.showToast('Error', errorMessage, TOAST_VARIANT.ERROR);
        this.resetData();
        this.isLoading = false;
    }

    resetData() {
        if (!this.isGM) {
            this.webinarData = [];
            this.filteredData = [];
        }
    }

    // -------------------------
    // FILTERING
    // -------------------------
    applyFilters() {
        this.filteredData = this.webinarData.filter(item =>
            this.matchesSearchCriteria(item) &&
            this.matchesStatusFilter(item)
        );

        if (!this.isGM) {
            this.calculateMetrics();
        }
    }

    matchesSearchCriteria(item) {
        if (!this.searchTerm) {
            return true;
        }

        const searchableFields = [
            item.studentName,
            item.email,
            item.phone,
            item.spocName
        ].filter(field => field);

        return searchableFields.some(field =>
            field.toLowerCase().includes(this.searchTerm)
        );
    }

    matchesStatusFilter(item) {
        return this.statusFilter === STATUS.ALL || item.status === this.statusFilter;
    }

    // -------------------------
    // METRICS CALCULATION
    // -------------------------
    calculateMetrics() {
        const dataToUse = this.filteredData;
        const total = dataToUse.length;
        const attended = this.countByStatus(dataToUse, STATUS.PRESENT);
        const absent = this.countByStatus(dataToUse, STATUS.ABSENT);

        this.metrics = {
            totalRegistrations: total,
            attended,
            attendanceRate: this.calculatePercentage(attended, total),
            pendingFollowups: absent
        };
    }

    calculateGMMetrics() {
        const total = this.allWebinarData.length;
        const attended = this.countByStatus(this.allWebinarData, STATUS.PRESENT);
        const absent = this.countByStatus(this.allWebinarData, STATUS.ABSENT);

        this.metrics = {
            totalRegistrations: total,
            attended,
            attendanceRate: this.calculatePercentage(attended, total),
            pendingFollowups: absent
        };
    }

    countByStatus(data, status) {
        return data.filter(item => item.status === status).length;
    }

    calculatePercentage(numerator, denominator) {
        if (denominator === 0) {
            return 0;
        }
        return ((numerator / denominator) * 100).toFixed(1);
    }

    // -------------------------
    // UI HELPERS
    // -------------------------
    get computedStatusOptions() {
        return this.statusOptions.map(status => ({
            ...status,
            buttonClass: this.buildStatusButtonClass(status.value),
            isActive: status.value === this.statusFilter,
            ariaPressed: String(status.value === this.statusFilter)
        }));
    }

    get isNoData() {
        return !this.isLoading && this.filteredData.length === 0 && this.selectedSpocId;
    }

    get hasData() {
        return this.filteredData.length > 0;
    }

    get showSpocTable() {
        return this.isGM && this.spocSummaryData.length > 0 && !this.showWebinarSelection;
    }

    get showAttendeeTable() {
        return (!this.isGM || (this.isGM && this.selectedSpocId)) && !this.showWebinarSelection;
    }

    get showSyncButton() {
        return this.activeWebinarId && !this.isLoading && !this.showWebinarSelection;
    }

    get showMetrics() {
        return !this.showWebinarSelection;
    }

    get showFilters() {
        return !this.showWebinarSelection && this.showAttendeeTable;
    }

    buildStatusButtonClass(statusValue) {
        const baseClass = 'status-filter-btn';
        const activeClass = 'status-filter-btn--active';
        return statusValue === this.statusFilter
            ? `${baseClass} ${activeClass}`
            : baseClass;
    }

    getStatusBadgeClass(status) {
        return STATUS_BADGE_MAP[status] || 'status-badge status-badge--default';
    }

    // -------------------------
    // UTILITIES
    // -------------------------
    generateInitials(name) {
        if (!name) {
            return '';
        }
        return name
            .trim()
            .split(/\s+/)
            .filter(word => word.length > 0)
            .map(word => word[0])
            .join('')
            .toUpperCase()
            .substring(0, 2);
    }

    formatDate(dateString) {
        if (!dateString) {
            return '';
        }
        try {
            const date = new Date(dateString);
            if (isNaN(date.getTime())) {
                return '';
            }
            return new Intl.DateTimeFormat('en-IN', {
                year: 'numeric',
                month: 'short',
                day: 'numeric'
            }).format(date);
        } catch (error) {
            this.logError('Date formatting error', error);
            return '';
        }
    }

    extractErrorMessage(error) {
        if (error?.body?.message) {
            return error.body.message;
        }
        if (error?.message) {
            return error.message;
        }
        return 'An unexpected error occurred. Please try again.';
    }

    isValidStatus(status) {
        return status && Object.values(STATUS).includes(status);
    }

    isValidPhone(phone) {
        return phone && phone.trim().length > 0;
    }

    showToast(title, message, variant) {
        const event = new ShowToastEvent({
            title,
            message,
            variant
        });
        this.dispatchEvent(event);
    }

    logError(message, error) {
        console.error(`${message}:`, error);
        if (error && error.stack) {
            console.error('Stack trace:', error.stack);
        }
    }
}