import { LightningElement, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getMembersByWebinar from '@salesforce/apex/WebinarDashboard.getMembersByWebinar';
import getSpocOptions from '@salesforce/apex/WebinarDashboard.getSpocOptions';
import syncLiveWebinarAttendees from '@salesforce/apex/WebinarDashboard.syncLiveWebinarAttendees';
import getWebinarsByNameOnly from '@salesforce/apex/WebinarController.getWebinarsByNameOnly';

const STATUS = {
    ALL: 'All',
    PRESENT: 'Present',
    ABSENT: 'Absent',
    SCHEDULED: 'Scheduled'
};

const STATUS_OPTIONS = [
    { label: 'All',     value: STATUS.ALL     },
    { label: 'Present', value: STATUS.PRESENT },
    { label: 'Absent',  value: STATUS.ABSENT  }
];

const TOAST_VARIANT = {
    SUCCESS: 'success',
    ERROR:   'error',
    WARNING: 'warning',
    INFO:    'info'
};

const STATUS_BADGE_MAP = {
    [STATUS.PRESENT]:   'status-badge status-badge--success',
    [STATUS.ABSENT]:    'status-badge status-badge--error',
    [STATUS.SCHEDULED]: 'status-badge status-badge--info'
};

export default class WebinarAttendedLeads extends LightningElement {
    @track webinarData         = [];
    @track filteredData        = [];
    @track searchTerm          = '';
    @track statusFilter        = STATUS.ALL;
    @track statusFilterForSpoc = null;
    @track selectedSpocId      = null;
    @track managedUsers        = [];
    @track spocSummaryGroups   = [];
    @track spocSummaryData     = [];
    @track expandedGmIds       = [];
    @track isLoading           = false;
    @track isSyncing           = false;
    @track isGM                = false;
    @track selectedWebinarId   = null;
    @track selectedWebinarApiId = null;
    @track selectedWebinarName = null;
    @track activeWebinarId     = null;
    @track liveAttendeeEmails  = new Set();
    @track allWebinarData      = [];
    @track webinarOptions      = [];
    @track showWebinarSelection = true;
    @track hasLiveSyncOccurred  = false;
    @track showCallModal        = false;
    @track selectedLeadForCall  = null;
    @track metrics = {
        totalRegistrations: 0,
        attended:           0,
        attendanceRate:     0,
        pendingFollowups:   0
    };

    statusOptions = STATUS_OPTIONS;

    connectedCallback() {
        this.loadWebinars();
    }

    async loadWebinars() {
        this.isLoading = true;
        try {
            const webinars = await getWebinarsByNameOnly();

            if (webinars && webinars.length > 0) {
                this.webinarOptions = webinars.map(w => ({
                    label: w.webinarId ? `${w.name} (${w.webinarId})` : w.name,
                    value: w.id,
                    webinarId: w.webinarId
                }));
            } else {
                this.showToast('Info', 'No active webinars found', TOAST_VARIANT.INFO);
            }

        } catch (error) {
            this.handleError(error);
        } finally {
            this.isLoading = false;
        }
    }

    handleWebinarChange(event) {
        this.selectedWebinarApiId = event.detail.value;
        const selectedWebinar = this.webinarOptions.find(w => w.value === this.selectedWebinarApiId);

        this.selectedWebinarId   = selectedWebinar?.webinarId || null;
        this.selectedWebinarName = selectedWebinar?.label;
        this.activeWebinarId     = this.selectedWebinarId;
        this.showWebinarSelection = false;
        this.syncAndLoadData();
    }

    async syncAndLoadData() {
        if (!this.selectedWebinarApiId) return;

        this.isLoading = true;
        try {
            await this.handleSyncLiveAttendees();
            const users = await getSpocOptions({ webinarId: this.selectedWebinarApiId });
            this.managedUsers = (users || []).map(user => ({
                Id: user.id,
                Name: user.name,
                ManagerId: user.managerId,
                ManagerName: user.managerName
            }));
            this.isGM = this.managedUsers.length > 0;

            if (this.isGM) {
                await this.loadAllSpocsData();
                this.filteredData = [];
            } else {
                const data = await getMembersByWebinar({ webinarId: this.selectedWebinarApiId });
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
            const allData = await getMembersByWebinar({ webinarId: this.selectedWebinarApiId });
            this.allWebinarData = this.removeDuplicates(allData || []);

            if (this.allWebinarData.length > 0 && this.allWebinarData[0].webinarId) {
                this.activeWebinarId = this.allWebinarData[0].webinarId;
            }

            this.applyLiveAttendeeStatus();
            this.calculateGMMetrics();
            this.buildSpocSummary();
        } catch (error) {
            throw error;
        }
    }

    removeDuplicates(data) {
        const uniqueDataMap = new Map();

        data.forEach(item => {
            const emailKey = item.email
                ? item.email.toLowerCase().trim()
                : `no-email-${item.webinarMemberId}`;

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
        const gmMap = new Map();

        this.managedUsers.forEach(user => {
            const gmId = user.ManagerId || 'no-gm';
            const gmName = user.ManagerName || 'GM';

            if (!gmMap.has(gmId)) {
                gmMap.set(gmId, {
                    gmId,
                    gmName,
                    spocs: []
                });
            }

            gmMap.get(gmId).spocs.push(user);
        });

        this.spocSummaryGroups = Array.from(gmMap.values()).map(group => {
            const gmSpocIds = group.spocs.map(user => user.Id);
            const gmData = this.allWebinarData.filter(item => gmSpocIds.includes(item.spocId));
            const gmPresent = gmData.filter(item => item.status === STATUS.PRESENT).length;
            const gmAbsent = gmData.filter(item => item.status === STATUS.ABSENT).length;
            const gmTotal = gmData.length;

            return {
                gmId: group.gmId,
                gmName: group.gmName,
                totalRegistrations: gmTotal,
                present: gmPresent,
                absent: gmAbsent,
                attendanceRate: this.calculatePercentage(gmPresent, gmTotal),
                spocs: group.spocs.map(user => {
                    const userData = this.allWebinarData.filter(item => item.spocId === user.Id);
                    const present = userData.filter(item => item.status === STATUS.PRESENT).length;
                    const absent = userData.filter(item => item.status === STATUS.ABSENT).length;
                    const total = userData.length;

                    return {
                        spocId: user.Id,
                        managerId: user.ManagerId,
                        spocName: user.Name,
                        totalRegistrations: total,
                        present,
                        absent,
                        attendanceRate: this.calculatePercentage(present, total),
                        isGroupRow: false,
                        canView: true
                    };
                })
            };
        });

        const validExpandedIds = new Set(this.spocSummaryGroups.map(group => group.gmId));
        this.expandedGmIds = this.expandedGmIds.filter(gmId => validExpandedIds.has(gmId));
        if (!this.expandedGmIds.length && this.spocSummaryGroups.length === 1) {
            this.expandedGmIds = [this.spocSummaryGroups[0].gmId];
        }
        this.refreshSpocSummaryRows();
    }

    refreshSpocSummaryRows() {
        const expandedIds = new Set(this.expandedGmIds);
        const summaryRows = [];

        this.spocSummaryGroups.forEach(group => {
            const isExpanded = expandedIds.has(group.gmId);
            summaryRows.push({
                spocId: `gm-${group.gmId}`,
                managerId: group.gmId,
                spocName: group.gmName,
                totalRegistrations: group.totalRegistrations,
                present: group.present,
                absent: group.absent,
                attendanceRate: group.attendanceRate,
                isGroupRow: true,
                canView: false,
                isExpanded,
                toggleIcon: isExpanded ? '-' : '+'
            });

            if (isExpanded) {
                group.spocs.forEach(spoc => {
                    summaryRows.push({
                        ...spoc,
                        spocName: spoc.spocName
                    });
                });
            }
        });

        this.spocSummaryData = summaryRows;
    }

    handleToggleGm(event) {
        const gmId = event.currentTarget.dataset.gmId;
        if (!gmId) {
            return;
        }

        const expandedIds = new Set(this.expandedGmIds);
        if (expandedIds.has(gmId)) {
            expandedIds.delete(gmId);
        } else {
            expandedIds.add(gmId);
        }

        this.expandedGmIds = Array.from(expandedIds);
        this.refreshSpocSummaryRows();
    }

    async handleSyncLiveAttendees() {
        if (!this.activeWebinarId) {
            this.showToast('Error', 'No active webinar found', TOAST_VARIANT.ERROR);
            return;
        }

        this.isSyncing = true;
        try {
            const result = await syncLiveWebinarAttendees({ webinarId: this.activeWebinarId });

            if (result && result.liveEmails && Array.isArray(result.liveEmails)) {
                this.liveAttendeeEmails  = new Set(
                    result.liveEmails.map(email => email.toLowerCase().trim())
                );
                this.hasLiveSyncOccurred = true;
            }

            if (this.isGM) {
                this.applyLiveAttendeeStatus();
                this.calculateGMMetrics();
                this.buildSpocSummary();
            }

            if (this.selectedSpocId) {
                const data = this.allWebinarData.filter(item => item.spocId === this.selectedSpocId);
                this.processWebinarData(data);
            } else if (!this.isGM) {
                const data = this.webinarData.map(item => {
                    const emailLower    = item.email ? item.email.toLowerCase().trim() : '';
                    const isLiveAttendee = this.liveAttendeeEmails.has(emailLower);
                    const normalizedStatus = this.normalizeAttendanceStatus(item.status);

                    let finalStatus;
                    if (isLiveAttendee) {
                        finalStatus = STATUS.PRESENT;
                    } else if (normalizedStatus) {
                        finalStatus = normalizedStatus;
                    } else if (this.hasLiveSyncOccurred) {
                        finalStatus = isLiveAttendee ? STATUS.PRESENT : STATUS.ABSENT;
                    } else {
                        finalStatus = STATUS.SCHEDULED;
                    }

                    return {
                        ...item,
                        status:          finalStatus,
                        statusBadgeClass: this.getStatusBadgeClass(finalStatus),
                        showCallButton:  true
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
        this.showWebinarSelection  = true;
        this.selectedWebinarId     = null;
        this.selectedWebinarApiId  = null;
        this.selectedWebinarName   = null;
        this.activeWebinarId       = null;
        this.selectedSpocId        = null;
        this.statusFilterForSpoc   = null;
        this.webinarData           = [];
        this.filteredData          = [];
        this.allWebinarData        = [];
        this.spocSummaryData       = [];
        this.spocSummaryGroups     = [];
        this.expandedGmIds         = [];
        this.liveAttendeeEmails    = new Set();
        this.hasLiveSyncOccurred   = false;
        this.metrics = {
            totalRegistrations: 0,
            attended:           0,
            attendanceRate:     0,
            pendingFollowups:   0
        };
    }

    applyLiveAttendeeStatus() {
        if (!this.allWebinarData.length || !this.hasLiveSyncOccurred) return;

        this.allWebinarData = this.allWebinarData.map(item => {
            const emailLower     = item.email ? item.email.toLowerCase().trim() : '';
            const isLiveAttendee = this.liveAttendeeEmails.has(emailLower);
            const normalizedStatus = this.normalizeAttendanceStatus(item.status);

            let finalStatus;
            if (isLiveAttendee) {
                finalStatus = STATUS.PRESENT;
            } else if (normalizedStatus) {
                finalStatus = normalizedStatus;
            } else {
                finalStatus = isLiveAttendee ? STATUS.PRESENT : STATUS.SCHEDULED;
            }

            return {
                ...item,
                status:           finalStatus,
                statusBadgeClass: this.getStatusBadgeClass(finalStatus),
                showCallButton:   true
            };
        });
    }

    async handleViewSpocData(event) {
        const spocId             = event.currentTarget ? event.currentTarget.dataset.spocId : event;
        this.selectedSpocId      = spocId;
        this.statusFilterForSpoc = null;
        this.isLoading           = true;

        try {
            let data;
            if (this.isGM) {
                if (String(spocId).startsWith('gm-')) {
                    const managerId = String(spocId).replace('gm-', '');
                    const spocIds = this.managedUsers
                        .filter(user => user.ManagerId === managerId)
                        .map(user => user.Id);
                    data = this.allWebinarData.filter(item => spocIds.includes(item.spocId));
                } else {
                    data = this.allWebinarData.filter(item => item.spocId === spocId);
                }
            } else {
                data = [];
            }
            this.processWebinarData(data);
        } catch (error) {
            this.handleError(error);
        } finally {
            this.isLoading = false;
        }
    }

    handleSpocQuickView(event) {
        const spocId     = event.currentTarget.dataset.spocId;
        const filterType = event.currentTarget.dataset.filterType;

        this.selectedSpocId = spocId;
        this.isLoading      = true;

        try {
            let data;
            if (String(spocId).startsWith('gm-')) {
                const managerId = String(spocId).replace('gm-', '');
                const spocIds = this.managedUsers
                    .filter(user => user.ManagerId === managerId)
                    .map(user => user.Id);
                data = this.allWebinarData.filter(item => spocIds.includes(item.spocId));
            } else {
                data = this.allWebinarData.filter(item => item.spocId === spocId);
            }

            if (filterType === 'present') {
                this.statusFilterForSpoc = STATUS.PRESENT;
                this.statusFilter        = STATUS.PRESENT;
            } else if (filterType === 'absent') {
                this.statusFilterForSpoc = STATUS.ABSENT;
                this.statusFilter        = STATUS.ABSENT;
            } else if (filterType === 'total') {
                this.statusFilterForSpoc = STATUS.ALL;
                this.statusFilter        = STATUS.ALL;
            }

            this.processWebinarData(data);
        } catch (error) {
            this.handleError(error);
        } finally {
            this.isLoading = false;
        }
    }

    handleSearchChange(event) {
        this.searchTerm = event.target.value.toLowerCase();
        this.applyFilters();
    }

    handleStatusFilter(event) {
        const newStatus = event.currentTarget.dataset.value;
        if (this.isValidStatus(newStatus) && newStatus !== this.statusFilter) {
            this.statusFilter        = newStatus;
            this.statusFilterForSpoc = null;
            this.applyFilters();
        }
    }

    handleCall(event) {
        const leadId    = event.currentTarget.dataset.leadid;
        const leadName  = event.currentTarget.dataset.leadname;
        const leadEmail = event.currentTarget.dataset.email;
        const leadPhone = event.currentTarget.dataset.phone;

        this.selectedLeadForCall = { leadId, leadName, leadEmail, leadPhone };
        this.showCallModal       = true;
    }

    handleCloseCallModal() {
        this.showCallModal       = false;
        this.selectedLeadForCall = null;
    }

    handleFeedbackSaved() {
        this.showCallModal       = false;
        this.selectedLeadForCall = null;

        if (this.isGM) {
            this.loadAllSpocsData();
        } else {
            this.syncAndLoadData();
        }

        this.showToast('Success', 'Call feedback saved and data refreshed', 'success');
    }

    processWebinarData(data) {
        try {
            const uniqueData = this.removeDuplicates(data);

            if (uniqueData.length > 0 && uniqueData[0].webinarId) {
                this.activeWebinarId = uniqueData[0].webinarId;
            }

            this.webinarData = uniqueData.map(item => this.enrichWebinarItem(item));
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
        const emailLower     = item.email ? item.email.toLowerCase().trim() : '';
        const isLiveAttendee = this.liveAttendeeEmails.has(emailLower);
        const normalizedStatus = this.normalizeAttendanceStatus(item.status);

        let finalStatus;
        if (isLiveAttendee) {
            finalStatus = STATUS.PRESENT;
        } else if (!normalizedStatus) {
            finalStatus = this.hasLiveSyncOccurred
                ? (isLiveAttendee ? STATUS.PRESENT : STATUS.ABSENT)
                : STATUS.SCHEDULED;
        } else {
            finalStatus = normalizedStatus;
        }

        return {
            ...item,
            studentInitials:  this.generateInitials(item.leadName),
            formattedDate:    this.formatDate(item.createdDate),
            status:           finalStatus,
            statusBadgeClass: this.getStatusBadgeClass(finalStatus),
            spocName:         item.spocName || 'Not Assigned',
            spocId:           item.spocId,
            showCallButton:   true
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
            this.webinarData  = [];
            this.filteredData = [];
        }
    }

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
        if (!this.searchTerm) return true;

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

    calculateMetrics() {
        const dataToUse = this.filteredData;
        const total     = dataToUse.length;
        const attended  = this.countByStatus(dataToUse, STATUS.PRESENT);
        const absent    = this.countByStatus(dataToUse, STATUS.ABSENT);

        this.metrics = {
            totalRegistrations: total,
            attended:           attended,
            attendanceRate:     this.calculatePercentage(attended, total),
            pendingFollowups:   absent
        };
    }

    calculateGMMetrics() {
        const total    = this.allWebinarData.length;
        const attended = this.countByStatus(this.allWebinarData, STATUS.PRESENT);
        const absent   = this.countByStatus(this.allWebinarData, STATUS.ABSENT);

        this.metrics = {
            totalRegistrations: total,
            attended:           attended,
            attendanceRate:     this.calculatePercentage(attended, total),
            pendingFollowups:   absent
        };
    }

    countByStatus(data, status) {
        return data.filter(item => item.status === status).length;
    }

    calculatePercentage(numerator, denominator) {
        if (denominator === 0) return 0;
        return ((numerator / denominator) * 100).toFixed(1);
    }

    get computedStatusOptions() {
        return this.statusOptions.map(status => ({
            ...status,
            buttonClass: this.buildStatusButtonClass(status.value),
            isActive:    status.value === this.statusFilter,
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
        const baseClass   = 'status-filter-btn';
        const activeClass = 'status-filter-btn--active';
        return statusValue === this.statusFilter
            ? `${baseClass} ${activeClass}`
            : baseClass;
    }

    getStatusBadgeClass(status) {
        return STATUS_BADGE_MAP[status] || 'status-badge status-badge--default';
    }

    normalizeAttendanceStatus(status) {
        if (!status) return status;
        return status === 'Registered' ? STATUS.ABSENT : status;
    }

    generateInitials(name) {
        if (!name) return '';
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
        if (!dateString) return '';
        try {
            const date = new Date(dateString);
            if (isNaN(date.getTime())) return '';
            return new Intl.DateTimeFormat('en-IN', {
                year:  'numeric',
                month: 'short',
                day:   'numeric'
            }).format(date);
        } catch (error) {
            this.logError('Date formatting error', error);
            return '';
        }
    }

    extractErrorMessage(error) {
        if (error?.body?.message) return error.body.message;
        if (error?.message)      return error.message;
        return 'An unexpected error occurred. Please try again.';
    }

    isValidStatus(status) {
        return status && Object.values(STATUS).includes(status);
    }

    isValidPhone(phone) {
        return phone && phone.trim().length > 0;
    }

    showToast(title, message, variant) {
        const event = new ShowToastEvent({ title, message, variant });
        this.dispatchEvent(event);
    }

    logError(message, error) {
        console.error(`${message}:`, error);
        if (error && error.stack) {
            console.error('Stack trace:', error.stack);
        }
    }
}
