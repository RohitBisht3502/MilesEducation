import { LightningElement, track, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getUserLeads from '@salesforce/apex/LeadQueueManagementController.getUserLeads';
//import saveLeadFeedback from '@salesforce/apex/LeadQueueManagementController.saveLeadFeedbackAuto';

export default class LeadQueueManagement extends LightningElement {

    @track leads = [];

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
            this.callsCompleted = 0;
        }

        if (error) {
            console.error('Lead load failed', error);
        }
    }

    get hasLeads() {
        return this.leads && this.leads.length > 0;
    }

    get disableStart() {
        return this.queueRunning || !this.hasLeads;
    }

    get disableEnd() {
        return !this.queueRunning;
    }

    async handleRefresh() {
        try {
            await refreshApex(this.wiredResult);
            this.remainingLeads = this.leads.length;
        } catch (e) {
            console.error('Manual refresh failed', e);
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

    // -------------------------------------------------------------------
    // QUEUE CONTROL
    // -------------------------------------------------------------------
    handleStart() {
        debugger;
        if (!this.queueRunning) {
            this.queueRunning = true;
            this.pickNextLead();
        }
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

        this.showModal = false;
        this.currentLeadId = null;
        this.currentIsCallLog = false;

        // Continue only if queue is still running
        if (this.queueRunning) {
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
            this.currentLeadId = this.leads[0].id;
            this.currentIsCallLog = this.leads[0].iscallLog ? true : false;
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
