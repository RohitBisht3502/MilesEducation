function formatDuration(seconds) {
    if (!seconds || seconds <= 0) return '0s';
    const total = Math.floor(seconds);
    const mins = Math.floor(total / 60);
    const secs = total % 60;
    return mins > 0 ? `${mins}m ${secs}s` : `${secs}s`;
}

import { LightningElement, api, wire } from 'lwc';
import getLeadActivityData from '@salesforce/apex/LeadActivityTimelineController.getLeadActivityData';

export default class LeadActivityTimeline extends LightningElement {
    @api recordId;

    lead;
    activities = [];
    error;
    loading = true;

    @wire(getLeadActivityData, { leadId: '$recordId' })
    wiredData({ data, error }) {
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
                const isCreated = log.name?.includes('Created') || false;
                const isUpdated = log.name?.includes('Updated') || false;

                const formattedChangedDateTime = log.changedDateTime
                    ? new Date(log.changedDateTime).toLocaleString()
                    : '';

                const formattedDuration = formatDuration(log.callDurationSeconds);

                // New: Call type mapping
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
                    isCreated,
                    isUpdated,
                    formattedChangedDateTime,
                    formattedDuration,
                    callTypeLabel,
                    callIconClass
                };
            });

            this.error = undefined;
        } else {
            this.error = error;
            this.activities = [];
            this.lead = undefined;
        }
    }

    get hasActivities() {
        return this.activities.length > 0;
    }
}