import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getLeadActivityData from '@salesforce/apex/LeadActivityTimelineController.getLeadActivityData';

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
    error;
    loading = true;
    wiredResult; // Store the wire result for refresh

    @wire(getLeadActivityData, { leadId: '$recordId' })
    wiredData(result) {
        this.wiredResult = result; // Store for refresh capability
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
                createdByName: data.createdByName
            };

            this.activities = (data.logs || []).map((log) => {
                const isCall = log.activityType === 'Call';
                const isLevelChange = log.activityType === 'Level Change';
                const isMergeLead = log.activityType === 'Lead Merge';
                const isViewedPhoneNumber = log.activityType === 'View Phone Number';
                const isGmeet = (log.activityType || '').toLowerCase() === 'gmeet';
                const isCreated = log.name?.includes('Created') || false;
                const isUpdated = log.name?.includes('Updated') || false;
                const isOther = !isCall && !isLevelChange && !isMergeLead && !isViewedPhoneNumber && !isGmeet;

                const formattedChangedDateTime = log.changedDateTime
                    ? new Date(log.changedDateTime).toLocaleString()
                    : '';

                const formattedDuration = formatDuration(log.callDurationSeconds);

                // Call type mapping
                const rawType = (log.callLogType || '').toLowerCase();
                let callTypeLabel = '';
                let callIconClass = 'call-icon';

                if (rawType === 'incoming') {
                    callTypeLabel = 'Incoming';
                    callIconClass += ' call-icon--incoming';
                } else if (rawType === 'outgoing') {
                    callTypeLabel = 'Outgoing';
                    callIconClass += ' call-icon--outgoing';
                } else if (rawType === 'missed') {
                    callTypeLabel = 'Missed';
                    callIconClass += ' call-icon--missed';
                }

                return {
                    ...log,
                    isCall,
                    isLevelChange,
                    isMergeLead,
                    isViewedPhoneNumber,
                    isGmeet,
                    isCreated,
                    isUpdated,
                    isOther,
                    formattedChangedDateTime,
                    formattedDuration,
                    callTypeLabel,
                    callIconClass
                };
            });

            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.activities = [];
            this.lead = undefined;
        }
    }

    get hasActivities() {
        return this.activities.length > 0;
    }

    // Method to manually refresh data
    @api
    async refresh() {
        this.loading = true;
        await refreshApex(this.wiredResult);
    }
}
