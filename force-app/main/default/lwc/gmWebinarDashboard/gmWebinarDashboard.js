/**
 * @File Name          : gmWebinarAttendedLeads.js
 * @Description        : Enterprise LWC for GM Webinar Attendee Dashboard with SPOC Filter
 * @Author             : Dheeraj Kumar
 * @Group              : Webinar Management
 * @Last Modified On   : November 2025
 **/

import { LightningElement, api, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getMembersByWebinar from '@salesforce/apex/WebinarController.getMembersByWebinar';
import getSpocOptions from '@salesforce/apex/WebinarController.getSpocOptions';

// Constants
const STATUS = {
    ALL: 'All',
    PRESENT: 'Present',
    ABSENT: 'Absent'
};

const SPOC_FILTER = {
    ALL: 'All SPOCs',
    NONE: 'No SPOC Assigned'
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

export default class GmWebinarDashboard extends LightningElement {
    // Public API
    @api recordId;

    // Tracked Properties
    @track webinarData = [];
    @track filteredData = [];
    @track searchTerm = '';
    @track statusFilter = STATUS.ALL;
    @track spocFilter = SPOC_FILTER.ALL;
    @track spocOptions = [];
    @track isLoading = true;
    @track isSpocLoading = false;
    @track metrics = {
        totalRegistrations: 0,
        attended: 0,
        attendanceRate: 0,
        pendingFollowups: 0,
        totalSpocs: 0
    };

    // Static Properties
    statusOptions = STATUS_OPTIONS;

    // -------------------------
    // LIFECYCLE HOOKS
    // -------------------------

    connectedCallback() {
        // Any initialization logic can go here
    }

    // -------------------------
    // COMPUTED PROPERTIES
    // -------------------------

    get computedStatusOptions() {
        return this.statusOptions.map(status => ({
            ...status,
            buttonClass: this.buildStatusButtonClass(status.value),
            isActive: status.value === this.statusFilter,
            ariaPressed: String(status.value === this.statusFilter)
        }));
    }

    get computedSpocOptions() {
        const baseOptions = [
            { label: SPOC_FILTER.ALL, value: SPOC_FILTER.ALL },
            { label: SPOC_FILTER.NONE, value: SPOC_FILTER.NONE }
        ];
        
        const spocOptions = this.spocOptions.map(spoc => ({
            label: spoc.name,
            value: spoc.id
        }));

        return [...baseOptions, ...spocOptions];
    }

    get isNoData() {
        return !this.isLoading && this.filteredData.length === 0;
    }

    get hasData() {
        return this.filteredData.length > 0;
    }

    // -------------------------
    // WIRE SERVICE
    // -------------------------

    @wire(getMembersByWebinar, { webinarId: '$recordId' })
    wiredWebinarData({ error, data }) {
        this.isLoading = false;

        if (data) {
            this.processWebinarData(data);
        } else if (error) {
            this.handleError(error);
        }
    }

    @wire(getSpocOptions, { webinarId: '$recordId' })
    wiredSpocOptions({ error, data }) {
        this.isSpocLoading = false;

        if (data) {
            this.spocOptions = data;
            this.calculateMetrics(); // Recalculate metrics with SPOC data
        } else if (error) {
            console.error('Error fetching SPOC options:', error);
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

    handleSpocFilter(event) {
        const newSpoc = event.detail.value;
        
        if (newSpoc !== this.spocFilter) {
            this.spocFilter = newSpoc;
            this.applyFilters();
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
            this.matchesStatusFilter(item) &&
            this.matchesSpocFilter(item)
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

    matchesSpocFilter(item) {
        if (this.spocFilter === SPOC_FILTER.ALL) {
            return true;
        }
        
        if (this.spocFilter === SPOC_FILTER.NONE) {
            return !item.spocId || item.spocName === 'Not Assigned';
        }
        
        return item.spocId === this.spocFilter;
    }

    // -------------------------
    // METRICS CALCULATION
    // -------------------------

    calculateMetrics() {
        const total = this.webinarData.length;
        const attended = this.countByStatus(STATUS.PRESENT);
        const absent = this.countByStatus(STATUS.ABSENT);
        const uniqueSpocs = this.getUniqueSpocsCount();

        this.metrics = {
            totalRegistrations: total,
            attended,
            attendanceRate: this.calculatePercentage(attended, total),
            pendingFollowups: absent,
            totalSpocs: uniqueSpocs
        };
    }

    countByStatus(status) {
        return this.webinarData.filter(item => item.status === status).length;
    }

    getUniqueSpocsCount() {
        const spocSet = new Set();
        this.webinarData.forEach(item => {
            if (item.spocId && item.spocName !== 'Not Assigned') {
                spocSet.add(item.spocId);
            }
        });
        return spocSet.size;
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
    // UTILITY METHODS
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

    // -------------------------
    // VALIDATION METHODS
    // -------------------------

    isValidStatus(status) {
        return status && Object.values(STATUS).includes(status);
    }

    isValidPhone(phone) {
        return phone && phone.trim().length > 0;
    }

    // -------------------------
    // PHONE CALL
    // -------------------------

    initiateCall(phone) {
        try {
            window.open(`tel:${phone}`, '_self');
        } catch (error) {
            this.logError('Failed to initiate call', error);
            this.showToast('Error', 'Unable to initiate call', TOAST_VARIANT.ERROR);
        }
    }

    // -------------------------
    // TOAST NOTIFICATIONS
    // -------------------------

    showToast(title, message, variant) {
        const event = new ShowToastEvent({
            title,
            message,
            variant
        });
        this.dispatchEvent(event);
    }

    // -------------------------
    // ERROR LOGGING
    // -------------------------

    logError(message, error) {
        console.error(`${message}:`, error);
        if (error.stack) {
            console.error('Stack trace:', error.stack);
        }
    }
}