import { LightningElement, track, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getQ2Leads from '@salesforce/apex/LeadQ2QueueController.getQ2Leads';
import updateLeadOwner from '@salesforce/apex/LeadQ2QueueController.updateLeadOwner';
import startProcessingLead from '@salesforce/apex/LeadQ2QueueController.startProcessingLead';
import getDispositions from '@salesforce/apex/CallDispositionConfigService.getDispositions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { subscribe, unsubscribe, onError } from 'lightning/empApi';

export default class LeadQ2QueueManagement extends LightningElement {

    @track leads = [];
    wiredResult;

    totalLeads = 0;
    remainingLeads = 0;
    isRefreshing = false;
    showModal = false;
    currentLeadId = null;
    currentIsCallLog = false;
    queueRunning = false;

    channelName = '/event/Queue_Lead_Status__e';
    subscription = {};

    @wire(getDispositions)
    dispositions;

    @wire(getQ2Leads)
    wiredLeads(result) {
        this.wiredResult = result;
        const { data, error } = result;

        if (data) {
            this.leads = data.map((item, i) => ({
                ...item,
                rowNumber: i + 1,
                primaryTagLabel: item.primaryTag || 'NA',
                bucketLabel: item.source || 'NA',
                levelLabel: item.stage || '--',
                courseLabel: item.course || 'NA',
                cityLabel: item.city || 'NA',
                primaryTagClass: this.getPrimaryTagClass(item.primaryTag),
                bucketClass: this.getBucketClass(item.source),
                levelClass: this.getLevelClass(item.stage),
                isProcessing: false,
                buttonLabel: 'Call'
            }));

            this.totalLeads = this.leads.length;
            this.remainingLeads = this.totalLeads;
        }

        if (error) {
            console.error('Lead load failed', error);
        }
    }

    connectedCallback() {
        this.subscribeToEvents();
        onError(error => {
            console.error('empApi error:', JSON.stringify(error));
        });
    }

    disconnectedCallback() {
        if (this.subscription) {
            unsubscribe(this.subscription, () => {
                console.log('Unsubscribed from channel');
            });
        }
    }

    subscribeToEvents() {
        console.log('Subscribing to channel:', this.channelName);
        subscribe(this.channelName, -1, (msg) => this.handleEvent(msg))
            .then(response => {
                console.log('Subscription request sent to:', response.channel);
                this.subscription = response;
            })
            .catch(error => {
                console.error('Subscription error:', JSON.stringify(error));
            });
    }

    handleEvent(msg) {
        console.log('--- New Queue_Lead_Status__e Event Received ---');
        console.log('Payload:', JSON.stringify(msg.data.payload));

        const payload = msg.data.payload;
        const leadId = payload.Lead_Id__c || payload.Lead_Id || payload.LeadId__c || payload.leadId;
        const status = payload.Status__c || payload.Status || payload.status;

        if (!leadId) {
            console.warn('Event received but no Lead ID found in payload');
            return;
        }

        console.log('Processing event for Lead:', leadId, 'Status:', status);

        this.leads = this.leads.map(lead => {
            const isMatch = String(lead.id).substring(0, 15) === String(leadId).substring(0, 15);
            if (isMatch) {
                console.log('UI Match Found! Updating row label to:', status);
                if (status === 'Processing') {
                    return { ...lead, isProcessing: true, buttonLabel: 'In Progress' };
                } else {
                    return { ...lead, isProcessing: false, buttonLabel: 'Call' };
                }
            }
            return lead;
        });
    }

    get hasLeads() {
        return this.leads && this.leads.length > 0;
    }

    async handleRefresh() {
        if (this.isRefreshing) return;
        this.isRefreshing = true;
        try {
            await refreshApex(this.wiredResult);
        } catch (e) {
            console.error('Manual refresh failed', e);
        } finally {
            this.isRefreshing = false;
        }
    }

    getPrimaryTagClass(tag) {
        const t = (tag || '').toLowerCase();
        if (t === 'untracked calls') return 'pill pill-blue';
        if (t === 'ne' || t === 'mhp') return 'pill pill-cyan';
        if (t === 'delays') return 'pill pill-amber';
        return 'pill pill-gray';
    }

    getBucketClass(bucket) {
        if (!bucket || bucket === 'NA') return 'pill pill-gray';
        return 'pill pill-green';
    }

    getLevelClass(level) {
        if (!level || level === 'NA' || level === '--') return 'pill pill-gray';
        return 'pill pill-slate';
    }

    handleCall(event) {
        const leadId = event.getAttribute ? event.getAttribute('data-id') : event.target.dataset.id;
        const lead = this.leads.find(l => l.id === leadId);
        if (lead) {
            if (lead.isProcessing) {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Warning',
                        message: 'This lead is already being processed by another user.',
                        variant: 'warning'
                    })
                );
                return;
            }
            this.currentLeadId = lead.id;
            this.currentIsCallLog = false;
            this.showModal = true;
            // Broadcast processing to others
            startProcessingLead({ leadId: leadId, status: 'Processing' });
        }
    }

    closeModal() {
        if (this.currentLeadId) {
            startProcessingLead({ leadId: this.currentLeadId, status: 'Ended' });
        }
        this.showModal = false;
        this.currentLeadId = null;
    }

    async handleCallComplete(event) {
        const detail = event.detail;
        const leadId = detail.recordId;
        const l1Status = detail.l1;

        // Requirement: Change owner ONLY if call was 'Connected'
        if (l1Status === 'Connected') {
            try {
                await updateLeadOwner({ leadId: leadId });
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Success',
                        message: 'Lead owner updated to you.',
                        variant: 'success'
                    })
                );
            } catch (error) {
                console.error('Failed to update lead owner', error);
            }
        } else {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Info',
                    message: 'Lead owner not updated (Call not connected).',
                    variant: 'info'
                })
            );
        }

        this.closeModal();

        // Refresh list
        await refreshApex(this.wiredResult);
    }

    get refreshIconClass() {
        return this.isRefreshing ? 'refresh-spin' : '';
    }
}