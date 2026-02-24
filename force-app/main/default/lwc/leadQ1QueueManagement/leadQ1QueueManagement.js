import { LightningElement, track, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getQ1Leads from '@salesforce/apex/LeadQ1QueueController.getQ1Leads';
import updateLeadOwner from '@salesforce/apex/LeadQ1QueueController.updateLeadOwner';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class LeadQ1QueueManagement extends LightningElement {

    @track leads = [];
    wiredResult;

    totalLeads = 0;
    remainingLeads = 0;
    isRefreshing = false;
    showModal = false;
    currentLeadId = null;
    currentIsCallLog = false;
    queueRunning = false; // Always false as we don't have start/resume

    @wire(getQ1Leads)
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
                levelClass: this.getLevelClass(item.stage)
            }));

            this.totalLeads = this.leads.length;
            this.remainingLeads = this.totalLeads;
        }

        if (error) {
            console.error('Lead load failed', error);
        }
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
        const leadId = event.target.dataset.id;
        const lead = this.leads.find(l => l.id === leadId);
        if (lead) {
            this.currentLeadId = lead.id;
            this.currentIsCallLog = false;
            this.showModal = true;
        }
    }

    closeModal() {
        this.showModal = false;
        this.currentLeadId = null;
    }

    async handleCallComplete(event) {
        const detail = event.detail;
        const leadId = detail.recordId;

        // Requirement: Change owner to current user after call disposition
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

        this.showModal = false;
        this.currentLeadId = null;

        // Refresh list
        await refreshApex(this.wiredResult);
    }
}