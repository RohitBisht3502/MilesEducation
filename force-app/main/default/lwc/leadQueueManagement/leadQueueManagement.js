import { LightningElement, track, wire } from 'lwc';
import getUserLeads from '@salesforce/apex/LeadQueueManagementController.getUserLeads';
import saveLeadFeedback from '@salesforce/apex/LeadQueueManagementController.saveLeadFeedbackAuto';

export default class LeadQueueManagement extends LightningElement {

    @track leads = [];

    queueRunning = false;
    currentLeadId = null;

    countdown = 0;
    countdownTimerId = null;
    isWaiting = false;

    showModal = false;

    totalLeads = 0;
    callsCompleted = 0;
    remainingLeads = 0;

    wiredResult;

    // -------------------------------------------------------------------
    // LOAD LEADS ON INIT
    // -------------------------------------------------------------------
    @wire(getUserLeads)
    wiredLeads(result) {
        this.wiredResult = result;
        const { data, error } = result;

        if (data) {
            this.leads = data.map((item, i) => ({
                ...item,
                rowNumber: i + 1
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

    // -------------------------------------------------------------------
    // START AUTO QUEUE
    // -------------------------------------------------------------------
    handleStart() {
        this.queueRunning = true;
        this.pickNextLead();
    }

    // -------------------------------------------------------------------
    // STOP QUEUE
    // -------------------------------------------------------------------
    handleEnd() {
        this.queueRunning = false;
        this.clearCountdown();
        this.showModal = false;
        this.currentLeadId = null;
    }

    closeModal() {
        this.showModal = false;
    }

    // -------------------------------------------------------------------
    // SAFE CHILD CALL STARTER WITH RETRY
    // -------------------------------------------------------------------
    startCurrentCall(retryCount = 0) {

        // MAX 10 retries → 50ms each → 500ms max wait
        if (retryCount > 10) {
            console.error('Child call start failed after retries');
            return;
        }

        const cmp = this.template.querySelector('c-runo-allocation-calls');

        if (cmp && typeof cmp.startCall === 'function') {
            console.log('Child found. Starting call...');
            cmp.startCall();
        } else {
            console.warn(`Child not ready yet. Retrying (${retryCount})`);
            setTimeout(() => this.startCurrentCall(retryCount + 1), 50);
        }
    }

    // -------------------------------------------------------------------
    // FEEDBACK RECEIVED FROM CHILD
    // -------------------------------------------------------------------
    async handleCallComplete(event) {

        const detail = event.detail;

        try {
            await saveLeadFeedback({
                leadId: detail.recordId,
                callId: detail.callId,
                feedback: detail.feedback,
                nextFollowUpDate: detail.nextFollowUpDate,
                l1: detail.l1,
                l2: detail.l2,
                stage: detail.stage,
                level: detail.level
            });
        } catch (e) {
            console.error('Feedback save error:', e);
        }

        // Remove completed lead from queue
        this.callsCompleted++;
        this.leads = this.leads.filter(l => l.id !== detail.recordId);
        this.remainingLeads = this.leads.length;

        this.showModal = false;

        // Start countdown for next call
        this.startCountdown(1);
    }

    // -------------------------------------------------------------------
    // COUNTDOWN FOR NEXT CALL
    // -------------------------------------------------------------------
    startCountdown(sec) {

        this.isWaiting = true;
        this.countdown = sec;

        this.clearCountdown();

        this.countdownTimerId = setInterval(() => {

            this.countdown--;

            if (this.countdown <= 0) {
                this.clearCountdown();
                this.isWaiting = false;

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
    // PICK NEXT LEAD AUTOMATICALLY
    // -------------------------------------------------------------------
    pickNextLead() {
      debugger;

        if (!this.queueRunning) return;

        if (this.leads.length === 0) {
            this.queueRunning = false;
            this.currentLeadId = null;
            return;
        }

        // Pick first lead
        this.currentLeadId = this.leads[0].id;

        // Open child modal
        this.showModal = true;

        // Wait for child to render
        setTimeout(() => this.startCurrentCall(0), 150);
    }
}