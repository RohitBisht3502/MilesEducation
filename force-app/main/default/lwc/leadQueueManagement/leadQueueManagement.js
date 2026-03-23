import { LightningElement, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import getUserLeads from '@salesforce/apex/LeadQueueManagementController.getUserLeads';
//import saveLeadFeedback from '@salesforce/apex/LeadQueueManagementController.saveLeadFeedbackAuto';

export default class LeadQueueManagement extends NavigationMixin(LightningElement) {

    @track leads = [];
    @track selectedQueue = 'All';
    @track queueList = [];

    queueRunning = false;
    currentLeadId = null;
    currentIsCallLog = false;

    // Pause / Resume variables
    pausedLeadId = null;

    countdown = 0;
    remainingCountdown = 0;
    countdownTimerId = null;
    isWaiting = false;
    isQueuePaused = false;


    showModal = false;

    totalLeads = 0;
    callsCompleted = 0;
    remainingLeads = 0;
    isRefreshing = false;

    wiredResult;

    // -------------------------------------------------------------------
    // LOAD LEADS
    // -------------------------------------------------------------------
    @wire(getUserLeads)
    wiredLeads(result) {
        this.wiredResult = result;
        const { data, error } = result;

        if (data) {
            const seenCallLogPhones = new Set();
            const filtered = data.filter(item => {
                if (!item.iscallLog) return true;

                const raw = item.phone || '';
                const normalized = raw.replace(/\D/g, '');
                const key = normalized || item.id;

                if (seenCallLogPhones.has(key)) return false;
                seenCallLogPhones.add(key);
                return true;
            });

            this.leads = filtered.map((item, i) => ({
                ...item,
                rowNumber: i + 1,
                primaryTagLabel: item.primaryTag || 'NA',
                bucketLabel: item.bucketTag || item.source || 'NA',
                levelLabel: item.stage || '--',
                courseLabel: item.course || 'NA',
                cityLabel: item.city || 'NA',
                candidateIdDisplay: item.candidateCode || 'N/A',
                queueName: item.queueName || item.primaryTag || 'NA',
                queueLabel: item.queueName || item.primaryTag || 'NA',
                recordObjectApiName: item.iscallLog ? 'Call_Log__c' : 'Lead__c',
                queueDotClass: this.getQueueDotClass(item.primaryTag),
                bucketBadgeClass: this.getBucketBadgeClass(item.bucketTag || item.source),
                inQueueSince: this.computeInQueueSince(item.createdDate),
                inQueueClass: this.isInQueueUrgent(item.createdDate) ? 'in-queue urgent' : 'in-queue',
                primaryTagClass: this.getPrimaryTagClass(item.primaryTag),
                bucketClass: this.getBucketClass(item.source),
                levelClass: this.getLevelClass(item.stage)
            }));

            this.totalLeads = this.leads.length;
            this.remainingLeads = this.totalLeads;
            this.callsCompleted = 0;
            this.buildQueueList();
        }

        if (error) {
            console.error('Lead load failed', error);
        }
    }

    get hasLeads() {
        return this.leads && this.leads.length > 0;
    }

    get filteredLeads() {
        if (this.selectedQueue === 'All') {
            return this.leads;
        }
        return this.leads.filter(lead => lead.queueLabel === this.selectedQueue);
    }

    get hasFilteredLeads() {
        return this.filteredLeads && this.filteredLeads.length > 0;
    }

    get showingCount() {
        return this.filteredLeads.length;
    }

    get disableStart() {
        return this.queueRunning || !this.hasLeads;
    }

    get disableEnd() {
        return !this.queueRunning;
    }

    async handleRefresh() {
        if (this.isRefreshing) return;
        this.isRefreshing = true;
        try {
            await refreshApex(this.wiredResult);
            this.remainingLeads = this.leads.length;
            this.buildQueueList();
        } catch (e) {
            console.error('Manual refresh failed', e);
        } finally {
            this.isRefreshing = false;
        }
    }

    handleQueueSelect(event) {
        this.selectedQueue = event.currentTarget.dataset.queue;
        this.buildQueueList();
    }

    async handleLeadClick(event) {
        const recordId = event.currentTarget.dataset.id;
        const objectApiName = event.currentTarget.dataset.object;
        if (!recordId || !objectApiName) {
            return;
        }

        const url = await this[NavigationMixin.GenerateUrl]({
            type: 'standard__recordPage',
            attributes: {
                recordId,
                objectApiName,
                actionName: 'view'
            }
        });

        if (url) {
            window.open(url, '_blank');
        }
    }

    buildQueueList() {
        const tagCounts = {};
        this.leads.forEach(lead => {
            const tag = lead.queueLabel || 'NA';
            tagCounts[tag] = (tagCounts[tag] || 0) + 1;
        });

        if (this.selectedQueue !== 'All' && !tagCounts[this.selectedQueue]) {
            this.selectedQueue = 'All';
        }

        const list = [{
            name: 'All',
            dotClass: 'queue-dot all-q',
            count: this.leads.length,
            itemClass: 'queue-item' + (this.selectedQueue === 'All' ? ' active' : ''),
            countClass: 'queue-item-count' + (this.selectedQueue === 'All' ? ' active' : '')
        }];

        Object.keys(tagCounts).forEach(tag => {
            list.push({
                name: tag,
                dotClass: this.getQueueDotClass(tag),
                count: tagCounts[tag],
                itemClass: 'queue-item' + (this.selectedQueue === tag ? ' active' : ''),
                countClass: 'queue-item-count' + (this.selectedQueue === tag ? ' active' : '')
            });
        });

        this.queueList = list;
    }

    getQueueDotClass(tag) {
        const value = (tag || '').toLowerCase();
        if (value === 'missed calls') return 'queue-dot missed';
        if (value === 'untracked calls') return 'queue-dot untracked';
        if (value === 'todays') return 'queue-dot todays';
        if (value === 'delays') return 'queue-dot delays';
        if (value === 'mhp') return 'queue-dot mhp';
        if (value === 'ne') return 'queue-dot ne';
        return 'queue-dot default-q';
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

    // -------------------------------------------------------------------
    // QUEUE CONTROL
    // -------------------------------------------------------------------
    handleStart() {
        if (!this.hasLeads) return;
        if (this.queueRunning) return;

        // Fresh start should not inherit paused state.
        this.isQueuePaused = false;
        this.pausedLeadId = null;
        this.isWaiting = false;
        this.remainingCountdown = 0;
        this.clearCountdown();

        this.queueRunning = true;
        this.pickNextLead();
    }
handleEnd() {
    this.queueRunning = false;
    this.isQueuePaused = false;

    this.clearCountdown();
    this.showModal = false;
    this.currentLeadId = null;
    this.currentIsCallLog = false;
    this.remainingCountdown = 0;
    this.pausedLeadId = null;
}

handlePause() {
    if (!this.queueRunning) return;

    this.queueRunning = false;
    this.isQueuePaused = true;

    this.clearCountdown();
    this.remainingCountdown = this.countdown;
    this.pausedLeadId = this.currentLeadId;

    console.log('Queue paused at', this.remainingCountdown);
}




    handlePauseFromChild(){
        console.log(' pause request from child model ');
        this.handlePause();
         this.showModal = false;
        this.currentLeadId = null;
        this.currentIsCallLog = false;

    }

    get disablePause() {
    return !this.queueRunning;
}

handleResumeFromChild(){
    console.log('resume request from call model ');
    this.handleResume();
}

get disableResume() {
    return this.queueRunning || !this.isQueuePaused;
}




   handleResume() {
    if (this.queueRunning || this.leads.length === 0) return;

    this.queueRunning = true;
    this.isQueuePaused = false;

    // Resume paused lead first
    if (this.pausedLeadId) {
        const row = this.leads.find(l => l.id === this.pausedLeadId);

        if (row) {
            this.currentLeadId = row.id;
            this.currentIsCallLog = row.iscallLog ? true : false;
            this.pausedLeadId = null;

            this.showModal = true;

            setTimeout(() => {
                const cmp = this.template.querySelector('c-runo-allocation-calls');
                if (cmp) cmp.startCall();
            }, 0);

            return;
        }

        this.pausedLeadId = null;
    }

    if (this.remainingCountdown > 0) {
        this.startCountdown(this.remainingCountdown);
    } else {
        this.pickNextLead();
    }
}

    closeModal() {
        this.showModal = false;
    }

    // -------------------------------------------------------------------
    // START CURRENT CALL
    // -------------------------------------------------------------------
    startCurrentCall() {
        const cmp = this.template.querySelector('c-runo-allocation-calls');
        if (cmp && typeof cmp.startCall === 'function') {
            console.log('Starting call from parent...');
            cmp.startCall();
        } else {
            console.error('startCall not found in child component.');
        }
    }

    // -------------------------------------------------------------------
    // HANDLE FEEDBACK FROM CHILD (UPDATED WITH refreshApex)
    // -------------------------------------------------------------------
    async handleCallComplete(event) {
        const detail = event.detail;

        // try {
        //     await saveLeadFeedback({
        //         leadId: detail.recordId,
        //         callId: detail.callId,
        //         feedback: detail.feedback,
        //         nextFollowUpDate: detail.nextFollowUpDate,
        //         l1: detail.l1,
        //         l2: detail.l2,
        //         stage: detail.stage,
        //         level: detail.level
        //     });
        // } catch (e) {
        //     console.error('Feedback save error:', e);
        // }

        this.callsCompleted++;

        if (this.pausedLeadId === detail.recordId) {
            this.pausedLeadId = null;
        }

        // Remove from UI instantly
        this.leads = this.leads.filter(l => l.id !== detail.recordId);

        // Refresh lead list from Apex
        try {
            await refreshApex(this.wiredResult);
        } catch (e) {
            console.error('Apex refresh failed:', e);
        }

        this.remainingLeads = this.leads.length;
        this.buildQueueList();

        this.showModal = false;
        this.currentLeadId = null;
        this.currentIsCallLog = false;

        // Save & Pause flow should stop queue progression.
        if (detail?.stopQueue) {
            this.queueRunning = false;
            this.isQueuePaused = true;
            this.clearCountdown();
            this.remainingCountdown = 0;
            return;
        }

        // Continue only if queue is still running
        if (this.queueRunning && !this.isQueuePaused) {
            this.remainingCountdown = 1;
            this.startCountdown(this.remainingCountdown);
        }
    }

    // -------------------------------------------------------------------
    // COUNTDOWN
    // -------------------------------------------------------------------
    startCountdown(sec) {
        this.isWaiting = true;
        this.countdown = sec;

        this.clearCountdown();

        this.countdownTimerId = setInterval(() => {
            this.countdown--;
            this.remainingCountdown = this.countdown;

            if (this.countdown <= 0) {
                this.clearCountdown();
                this.isWaiting = false;
                this.remainingCountdown = 0;

                this.pickNextLead();
            }

        }, 1000);
    }

    clearCountdown() {
        if (this.countdownTimerId) {
            clearInterval(this.countdownTimerId);
            this.countdownTimerId = null;
        }
    }

    // -------------------------------------------------------------------
    // PICK NEXT LEAD
    // -------------------------------------------------------------------
    pickNextLead() {
        if (!this.queueRunning) return;

        if (this.leads.length === 0) {
            this.queueRunning = false;
            this.currentLeadId = null;
            this.currentIsCallLog = false;
            return;
        }

        // If paused, do nothing (resume will handle it)
        if (this.pausedLeadId) {
            console.log('Not picking next lead because paused lead exists:', this.pausedLeadId);
            return;
        }

        if (!this.showModal) {
            const queueLeads = this.filteredLeads;
            if (!queueLeads.length) {
                this.queueRunning = false;
                return;
            }
            this.currentLeadId = queueLeads[0].id;
            this.currentIsCallLog = queueLeads[0].iscallLog ? true : false;
            this.showModal = true;
        }

        const handler = () => {
            console.log('Child ready. Starting call...');
            this.startCurrentCall();
            this.template.removeEventListener('componentready', handler);
        };

        this.template.addEventListener('componentready', handler);
    }
}