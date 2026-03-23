import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getLeadActivityData from '@salesforce/apex/LeadActivityTimelineController.getLeadActivityData';

const FILTER_ORDER = ['All', 'Call', 'Eligibility', 'Email', 'Enrolment Form', 'Gmeet', 'Lead Conversion', 'Lead Downgraded', 'Lead Merge', 'Level Change', 'Loan', 'Meeting', 'Owner Change', 'Payment', 'View Phone Number', 'Webinar'];

function formatDuration(seconds) {
    if (!seconds || seconds <= 0) return '0s';
    const total = Math.floor(seconds);
    const mins = Math.floor(total / 60);
    const secs = total % 60;
    return mins > 0 ? `${mins}m ${secs}s` : `${secs}s`;
}

export default class LeadActivityTimeline extends LightningElement {
    @api recordId;

    lead;
    activities = [];
    selectedFilter = 'All';
    error;
    loading = true;
    wiredResult;

    @wire(getLeadActivityData, { leadId: '$recordId' })
    wiredData(result) {
        this.wiredResult = result;
        const { data, error } = result;
        this.loading = false;

        if (data) {
            this.lead = {
                name: data.name,
                phone: data.phone,
                email: data.email,
                city: data.city,
                course: data.course,
                source: data.source,
                createdByName: data.createdByName,
                currentOwnerName: data.currentOwnerName,
                currentHighestLevel: data.currentHighestLevel,
                currentGm: data.currentGm
            };

            this.activities = (data.logs || []).map((log) => {
                const activityType = log.activityType || 'Other';
                const formattedChangedDateTime = log.changedDateTime ? new Date(log.changedDateTime).toLocaleString() : '';
                const formattedDuration = formatDuration(log.callDurationSeconds);
                return {
                    ...log,
                    activityType,
                    categoryLabel: activityType === 'Payment' && (log.loanStatus || log.loanAmount || log.loanProvider || log.milesLoanCode) ? 'Loan' : activityType,
                    formattedChangedDateTime,
                    formattedDuration,
                    iconName: this.getIconName(activityType, log),
                    iconClass: this.getIconClass(activityType, log),
                    isCall: activityType === 'Call',
                    isLevelChange: activityType === 'Level Change',
                    isOwnerChange: activityType === 'Owner Change',
                    isLoan: activityType === 'Payment' && (log.loanStatus || log.loanAmount || log.loanProvider || log.milesLoanCode),
                    isPayment: activityType === 'Payment' && !(log.loanStatus || log.loanAmount || log.loanProvider || log.milesLoanCode),
                    hasOwnerFields: !!(log.previousOwnerName || log.newOwnerName),
                    hasLevelFields: !!(log.previousLevel || log.newLevel),
                    hasDispositionFields: !!(log.l1 || log.l2),
                    actionByDisplay: log.actionByName || log.createdByText || 'System'
                };
            });

            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.activities = [];
            this.lead = undefined;
        }
    }

    get summaryCards() {
        if (!this.lead) return [];
        return [
            { key: 'owner', label: 'Current Owner', value: this.lead.currentOwnerName || '--', icon: 'utility:user', className: 'summary-icon summary-icon-owner' },
            { key: 'highest', label: 'Highest Level', value: this.lead.currentHighestLevel || '--', icon: 'utility:trend', className: 'summary-icon summary-icon-level' },
            { key: 'gm', label: 'Current GM', value: this.lead.currentGm || '--', icon: 'utility:shield', className: 'summary-icon summary-icon-gm' }
        ];
    }

    get filterOptions() {
        const counts = {};
        this.activities.forEach((activity) => {
            const key = activity.categoryLabel || 'Other';
            counts[key] = (counts[key] || 0) + 1;
        });

        return FILTER_ORDER.filter((label) => label === 'All' || counts[label]).map((label) => ({
            label,
            count: label === 'All' ? this.activities.length : counts[label],
            className: `filter-chip${this.selectedFilter === label ? ' active' : ''}`
        }));
    }

    get filteredActivities() {
        if (this.selectedFilter === 'All') {
            return this.activities;
        }
        return this.activities.filter((activity) => activity.categoryLabel === this.selectedFilter);
    }

    get hasActivities() {
        return this.filteredActivities.length > 0;
    }

    handleFilterClick(event) {
        this.selectedFilter = event.currentTarget.dataset.filter;
    }

    getIconName(activityType, log) {
        if (activityType === 'Call') return 'utility:call';
        if (activityType === 'Eligibility') return 'utility:check';
        if (activityType === 'Email') return 'utility:email';
        if (activityType === 'Enrolment Form') return 'utility:note';
        if (activityType === 'Gmeet') return 'utility:video';
        if (activityType === 'Lead Conversion') return 'utility:replace';
        if (activityType === 'Lead Downgraded') return 'utility:arrowdown';
        if (activityType === 'Lead Merge') return 'utility:merge';
        if (activityType === 'Level Change') return 'utility:chart';
        if (activityType === 'Meeting') return 'utility:event';
        if (activityType === 'Owner Change') return 'utility:user';
        if (activityType === 'View Phone Number') return 'utility:phone_portrait';
        if (activityType === 'Webinar') return 'utility:display_rich_text';
        if (activityType === 'Payment' && (log.loanStatus || log.loanAmount || log.loanProvider || log.milesLoanCode)) return 'utility:moneybag';
        if (activityType === 'Payment') return 'utility:money';
        return 'utility:info';
    }

    getIconClass(activityType, log) {
        if (activityType === 'Owner Change') return 'activity-icon activity-icon-owner';
        if (activityType === 'Level Change') return 'activity-icon activity-icon-level';
        if (activityType === 'Payment' && (log.loanStatus || log.loanAmount || log.loanProvider || log.milesLoanCode)) return 'activity-icon activity-icon-money';
        if (activityType === 'Call') return 'activity-icon activity-icon-call';
        return 'activity-icon activity-icon-default';
    }

    @api
    async refresh() {
        this.loading = true;
        await refreshApex(this.wiredResult);
    }
}