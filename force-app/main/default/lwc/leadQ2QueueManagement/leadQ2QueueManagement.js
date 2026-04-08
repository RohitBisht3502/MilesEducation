import { LightningElement, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import getQ2Leads from '@salesforce/apex/LeadQ2QueueController.getQ2Leads';
import updateLeadOwner from '@salesforce/apex/LeadQ2QueueController.updateLeadOwner';
import startProcessingLead from '@salesforce/apex/LeadQ2QueueController.startProcessingLead';
import getDispositions from '@salesforce/apex/CallDispositionConfigService.getDispositions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { subscribe, unsubscribe, onError } from 'lightning/empApi';

export default class LeadQ2QueueManagement extends NavigationMixin(LightningElement) {
    @track leads = [];
    @track groupedLeads = [];
    @track selectedBucket = 'All';
    @track bucketList = [];

    wiredResult;

    totalLeads = 0;
    isRefreshing = false;
    showModal = false;
    currentLeadId = null;

    channelName = '/event/Queue_Lead_Status__e';
    subscription = {};

    @wire(getDispositions)
    dispositions;

    @wire(getQ2Leads)
    wiredLeads(result) {
        this.wiredResult = result;
        const { data, error } = result;

        if (data) {
            this.leads = data.map((item, index) => ({
                ...item,
                rowNumber: index + 1,
                candidateIdDisplay: item.candidateCode || 'N/A',
                candidateNameDisplay: item.candidateName || item.name || 'N/A',
                bucketLabel: item.bucketTag || item.source || 'NA',
                levelLabel: item.stage || '--',
                courseLabel: item.course || 'NA',
                inQueueSince: this.computeInQueueSince(item.createdDate),
                inQueueClass: this.isInQueueUrgent(item.createdDate) ? 'in-queue urgent' : 'in-queue',
                bucketBadgeClass: this.getBucketBadgeClass(item.bucketTag || item.source),
                isProcessing: false,
                buttonLabel: 'Call'
            }));

            this.groupedLeads = this.buildGroupedLeads(this.leads);
            this.totalLeads = this.leads.length;
            this.buildBucketList();
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
        subscribe(this.channelName, -1, msg => this.handleEvent(msg))
            .then(response => {
                this.subscription = response;
            })
            .catch(error => {
                console.error('Subscription error:', JSON.stringify(error));
            });
    }

    handleEvent(msg) {
        const payload = msg.data.payload;
        const leadId = payload.Lead_Id__c || payload.Lead_Id || payload.LeadId__c || payload.leadId;
        const status = payload.Status__c || payload.Status || payload.status;

        if (!leadId) {
            return;
        }

        this.leads = this.leads.map(lead => {
            const isMatch = String(lead.id).substring(0, 15) === String(leadId).substring(0, 15);
            if (!isMatch) {
                return lead;
            }
            return {
                ...lead,
                isProcessing: status === 'Processing',
                buttonLabel: status === 'Processing' ? 'In Progress' : 'Call'
            };
        });
        this.groupedLeads = this.buildGroupedLeads(this.leads);
    }

    get filteredLeadGroups() {
        const leadsToGroup = this.selectedBucket === 'All'
            ? this.leads
            : this.leads.filter(lead => lead.bucketLabel === this.selectedBucket);

        return this.buildGroupedLeads(leadsToGroup);
    }

    get filteredLeads() {
        if (this.selectedBucket === 'All') {
            return this.leads;
        }
        return this.leads.filter(lead => lead.bucketLabel === this.selectedBucket);
    }

    get hasFilteredLeads() {
        return this.filteredLeadGroups.length > 0;
    }

    get showingCount() {
        return this.filteredLeads.length;
    }

    async handleRefresh() {
        if (this.isRefreshing) return;
        this.isRefreshing = true;
        try {
            await refreshApex(this.wiredResult);
            this.groupedLeads = this.buildGroupedLeads(this.leads);
            this.buildBucketList();
        } catch (e) {
            console.error('Manual refresh failed', e);
        } finally {
            this.isRefreshing = false;
        }
    }

    handleBucketSelect(event) {
        this.selectedBucket = event.currentTarget.dataset.bucket;
        this.buildBucketList();
    }

    async handleCandidateClick(event) {
        const recordId = event.currentTarget.dataset.id;
        if (!recordId) {
            return;
        }

        const url = await this[NavigationMixin.GenerateUrl]({
            type: 'standard__recordPage',
            attributes: {
                recordId,
                objectApiName: 'Candidate__c',
                actionName: 'view'
            }
        });

        if (url) {
            window.open(url, '_blank');
        }
    }

    buildBucketList() {
        const bucketCounts = {};
        this.leads.forEach(lead => {
            const bucket = lead.bucketLabel || 'NA';
            bucketCounts[bucket] = (bucketCounts[bucket] || 0) + 1;
        });

        if (this.selectedBucket !== 'All' && !bucketCounts[this.selectedBucket]) {
            this.selectedBucket = 'All';
        }

        const list = [{
            name: 'All',
            count: this.leads.length,
            itemClass: 'bucket-item' + (this.selectedBucket === 'All' ? ' active' : ''),
            countClass: 'bucket-item-count' + (this.selectedBucket === 'All' ? ' active' : '')
        }];

        Object.keys(bucketCounts).sort().forEach(bucket => {
            list.push({
                name: bucket,
                count: bucketCounts[bucket],
                itemClass: 'bucket-item' + (this.selectedBucket === bucket ? ' active' : ''),
                countClass: 'bucket-item-count' + (this.selectedBucket === bucket ? ' active' : '')
            });
        });

        this.bucketList = list;
    }

    buildGroupedLeads(leads = []) {
        const groups = new Map();

        leads.forEach(lead => {
            const key = lead.candidateId || `lead-${lead.id}`;
            if (!groups.has(key)) {
                groups.set(key, {
                    key,
                    candidateId: lead.candidateId,
                    candidateIdDisplay: lead.candidateIdDisplay,
                    candidateNameDisplay: lead.candidateNameDisplay,
                    candidateCount: 0,
                    leads: [],
                    primaryLeadId: lead.id,
                    oldestCreatedDate: lead.createdDate,
                    isProcessing: false,
                    buttonLabel: 'Call',
                    inQueueSince: lead.inQueueSince,
                    inQueueClass: lead.inQueueClass
                });
            }

            const group = groups.get(key);
            group.leads.push(lead);
            group.candidateCount += 1;
            group.isProcessing = group.isProcessing || lead.isProcessing;
            group.buttonLabel = group.isProcessing ? 'In Progress' : 'Call';

            if (new Date(lead.createdDate) < new Date(group.oldestCreatedDate)) {
                group.primaryLeadId = lead.id;
                group.oldestCreatedDate = lead.createdDate;
                group.inQueueSince = lead.inQueueSince;
                group.inQueueClass = lead.inQueueClass;
            }
        });

        return Array.from(groups.values()).map(group => {
            const buckets = [...new Set(group.leads.map(lead => lead.bucketLabel).filter(Boolean))];
            const levels = [...new Set(group.leads.map(lead => lead.levelLabel).filter(Boolean))];
            const courses = [...new Set(group.leads.map(lead => lead.courseLabel).filter(Boolean))];

            return {
                ...group,
                bucketDisplay: this.formatGroupSummary(buckets),
                levelDisplay: this.formatGroupSummary(levels),
                courseDisplay: this.formatGroupSummary(courses),
                bucketBadgeClass: buckets.length === 1
                    ? this.getBucketBadgeClass(buckets[0])
                    : 'badge badge-bucket-na'
            };
        });
    }

    formatGroupSummary(values = []) {
        if (values.length === 0) {
            return 'NA';
        }
        if (values.length === 1) {
            return values[0];
        }
        return `Multiple (${values.length})`;
    }

    getBucketBadgeClass(bucket) {
        if (!bucket || bucket === 'NA' || bucket === 'ALL') return 'badge badge-bucket-na';
        const normalized = bucket.toLowerCase().replace(/[\s_]+/g, '');
        if (normalized.includes('bucket1') || normalized === '1') return 'badge badge-bucket-1';
        if (normalized.includes('bucket2') || normalized === '2') return 'badge badge-bucket-2';
        if (normalized.includes('bucket3') || normalized === '3') return 'badge badge-bucket-3';
        if (normalized.includes('bucket4') || normalized === '4') return 'badge badge-bucket-4';
        if (normalized.includes('bucket5') || normalized === '5') return 'badge badge-bucket-5';
        return 'badge badge-bucket-na';
    }

    computeInQueueSince(createdDate) {
        if (!createdDate) return '--';
        const now = new Date();
        const created = new Date(createdDate);
        const diffMs = Math.max(now - created, 0);
        const totalMinutes = Math.floor(diffMs / 60000);
        const d = Math.floor(totalMinutes / 1440);
        const h = Math.floor((totalMinutes % 1440) / 60);
        const m = totalMinutes % 60;
        return `${d}d ${h}h ${m}m`;
    }

    isInQueueUrgent(createdDate) {
        if (!createdDate) return false;
        return (new Date() - new Date(createdDate)) > (2 * 24 * 60 * 60 * 1000);
    }

    async handleCall(event) {
        const leadId = event.currentTarget.dataset.id;
        const lead = this.leads.find(item => item.id === leadId);
        if (!lead) {
            return;
        }

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

        try {
            await updateLeadOwner({ leadId, candidateId: lead.candidateId });
            this.currentLeadId = lead.id;
            this.showModal = true;
            startProcessingLead({ leadId, status: 'Processing' });
        } catch (error) {
            console.error('Failed to assign lead/candidate owner', error);
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: 'Failed to assign lead and candidate to you.',
                    variant: 'error'
                })
            );
        }
    }

    closeModal() {
        if (this.currentLeadId) {
            startProcessingLead({ leadId: this.currentLeadId, status: 'Ended' });
        }
        this.showModal = false;
        this.currentLeadId = null;
    }

    async handleCallComplete() {
        this.closeModal();
        await refreshApex(this.wiredResult);
        this.groupedLeads = this.buildGroupedLeads(this.leads);
        this.buildBucketList();
    }
}