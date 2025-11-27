/**
 * @File Name          : webinarAttendedLeads.js
 * @Description        : Enterprise LWC for Webinar Attendee Dashboard with SPOC Filter
 * @Author             : Dheeraj Kumar
 * @Group              : Webinar Management
 * @Last Modified On   : Nov 25, 2025
 **/

import { LightningElement, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getActiveWebinarAttendees from '@salesforce/apex/WebinarController.getActiveWebinarAttendees';
import getActiveWebinarAttendeesForUser from '@salesforce/apex/WebinarController.getActiveWebinarAttendeesForUser';
import getManagedUsers from '@salesforce/apex/WebinarController.getManagedUsers';

// Constants
const STATUS = {
    ALL: 'All',
    PRESENT: 'Present',
    ABSENT: 'Absent'
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
    [STATUS.ABSENT]: 'status-badge status-badge--error'
};

export default class WebinarAttendedLeads extends LightningElement {
    // Tracked Properties
    @track webinarData = [];
    @track filteredData = [];
    @track searchTerm = '';
    @track statusFilter = STATUS.ALL;
    @track spocFilter = 'all';
    @track managedUsers = [];
    @track isLoading = true;
    @track isGM = false;
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
        this.loadInitialData();
    }

    async loadInitialData() {
        this.isLoading = true;
        try {
            // First check if user is GM
            const users = await getManagedUsers();
            if (users && users.length > 0) {
                this.isGM = true;
                this.managedUsers = users;
                // If GM, load data for all managed users
                await this.loadAllSpocsData();
            } else {
                // If not GM, load only current user's data
                const data = await getActiveWebinarAttendees();
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
            // Fetch data for current user
            const currentUserData = await getActiveWebinarAttendees();
            let allData = [...currentUserData];

            // Fetch data for each managed user
            for (const user of this.managedUsers) {
                try {
                    const userData = await getActiveWebinarAttendeesForUser({ userId: user.Id });
                    allData = [...allData, ...userData];
                } catch (error) {
                    console.log(`Error fetching data for user ${user.Name}:`, error);
                }
            }

            this.processWebinarData(allData);
        } catch (error) {
            throw error;
        }
    }

    // -------------------------
    // EVENT HANDLERS
    // -------------------------
    handleSearchChange(event) {
        this.searchTerm = event.target.value.toLowerCase().trim();
        this.applyFilters();
    }

    handleStatusFilter(event) {
        const newStatus = event.currentTarget.dataset.value;
        if (this.isValidStatus(newStatus) && newStatus !== this.statusFilter) {
            this.statusFilter = newStatus;
            this.applyFilters();
        }
    }

    async handleSpocFilter(event) {
        const selectedSpocId = event.target.value;
        this.spocFilter = selectedSpocId;
        this.isLoading = true;

        try {
            let data;
            if (selectedSpocId === 'all') {
                // Load all SPOCs data
                await this.loadAllSpocsData();
            } else {
                // Fetch selected SPOC's data
                data = await getActiveWebinarAttendeesForUser({ userId: selectedSpocId });
                this.processWebinarData(data);
            }
        } catch (error) {
            this.handleError(error);
        } finally {
            this.isLoading = false;
        }
    }

    handleCall(event) {
        const phone = event.currentTarget.dataset.phone;
        if (this.isValidPhone(phone)) {
            this.initiateCall(phone);
        } else {
            this.showToast('Error', 'Phone number not available', TOAST_VARIANT.ERROR);
        }
    }

    // -------------------------
    // GM & SPOC MANAGEMENT
    // -------------------------
    get computedSpocOptions() {
        const options = [
            { label: 'All SPOCs', value: 'all' }
        ];

        if (this.isGM && this.managedUsers.length > 0) {
            this.managedUsers.forEach(user => {
                options.push({
                    label: user.Name,
                    value: user.Id
                });
            });
        }

        return options;
    }

    get showSpocFilter() {
        return this.isGM && this.managedUsers.length > 0;
    }

    // -------------------------
    // DATA PROCESSING
    // -------------------------
    processWebinarData(data) {
        try {
            this.webinarData = data.map(item => this.enrichWebinarItem(item));
            this.filteredData = [...this.webinarData];
            this.calculateMetrics();
        } catch (error) {
            this.logError('Error processing webinar data', error);
            this.showToast('Error', 'Failed to process webinar data', TOAST_VARIANT.ERROR);
        }
    }

    enrichWebinarItem(item) {
        return {
            ...item,
            studentInitials: this.generateInitials(item.leadName),
            studentName: item.leadName,
            email: item.email,
            phone: item.phone,
            formattedDate: this.formatDate(item.createdDate),
            registrationDate: item.createdDate,
            statusBadgeClass: this.getStatusBadgeClass(item.status),
            spocName: item.spocName || 'Not Assigned',
            spocId: item.spocId
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
        this.webinarData = [];
        this.filteredData = [];
    }

    // -------------------------
    // FILTERING
    // -------------------------
    applyFilters() {
        this.filteredData = this.webinarData.filter(item =>
            this.matchesSearchCriteria(item) && 
            this.matchesStatusFilter(item)
        );
        this.calculateMetrics();
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
        return !this.isLoading && this.filteredData.length === 0;
    }

    get hasData() {
        return this.filteredData.length > 0;
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
            return new Intl.DateTimeFormat('en-US', {
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

    initiateCall(phone) {
        try {
            window.open(`tel:${phone}`, '_self');
        } catch (error) {
            this.logError('Failed to initiate call', error);
            this.showToast('Error', 'Unable to initiate call', TOAST_VARIANT.ERROR);
        }
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