import { api, LightningElement, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import allocateLeadNow from '@salesforce/apex/Webservice_RunoAllocationAPI.allocateLeadNow';
import updateCallFeedback from '@salesforce/apex/Webservice_RunoAllocationAPI.updateCallFeedback';
import getL1L2Values from '@salesforce/apex/Webservice_RunoAllocationAPI.getL1L2Values';
import getIdentity from '@salesforce/apex/RunoCallIdentityService.getIdentity';
import getStageLevelValues from '@salesforce/apex/Webservice_RunoAllocationAPI.getStageLevelValues';

import { CloseActionScreenEvent } from 'lightning/actions';
import { subscribe, unsubscribe, onError } from 'lightning/empApi';

export default class RunoAllocationCall extends LightningElement {
    @api recordId;

    // UI / state
    loading = false;
    disableCancel = false;

    callButtonLabel = 'Call Runo';
    callButtonDisabled = false;

    // Call popup overlay (Calling Runo...)
    showCallPopup = false;

    // L1/L2
    l1Value = '';
    l2Value = '';
    l1Options = [];
    l2Options = [];
    fullMap = {};
    isL2Disabled = true;

    // 🔥 NEW: auto-set next follow up date flag (like good LWC)
    autoSetFollowUp = true;

    // Stage / Course
    stageValue = '';
    levelValue = '';
    stageOptions = [];
    levelOptions = [];

    // Toast / error
    showPopup = false;
    errorText;

    // identity info
    identity = {
        name: '',
        email: '',
        phone: '',
        city: '',
        source: '',
        stage: '',
        level: ''
    };

    // call state
    isLive = false;
    callStatus = 'Idle';
    callTitle = 'Calling via Runo';

    elapsedMs = 0;
    elapsedLabel = '00:00';
    timerId = null;

    // feedback
    showFeedback = false;
    savingFeedback = false;
    feedback = '';
    nextFollowUpDate = null;

    lastCallId = null;

    // manual end call if no response in 30s
    canEndCall = false;
    CALL_NO_RESPONSE_MS = 30000;
    noResponseTimer = null;

    // mandatory comment logic
    // comment box always visible; mandatory controlled by isCommentMandatory
    showCommentBox = true;
    isCommentMandatory = false;
    mandatoryCommentRules = {
        'Connected:Discussed': true,
        'Connected:Request Call Back': true,
        'Connected:Not Eligible': true,
        'Connected:Wrong Number': true,
        'Connected:Language Barrier': true,
        'Connected:Visit Confirmed': true,
        'Connected:Visit Completed': true,
        'Connected:Visit Rescheduled': true,
        'Connected:Visit Cancelled': true,
        'Connected:Visit Booked By Mistake': true,
        'Connected:Google Meet Completed': true,
        'Connected:Google Meet Rescheduled': true,
        'Connected:Google Meet Cancelled': true,
        'Connected:Attended And Disconnected': true,
        'Connected:Voice Mail': true,
        'Connected:Not Interested (DND)': true,
        'Connected:Postponed': true,

        'Not-Connected:Not Lifting': false,
        'Not-Connected:Switched Off': false,
        'Not-Connected:Not Reachable': false,
        'Not-Connected:Busy': false,
        'Not-Connected:Invalid Number': true
    };

    // ---------------- WIRE ----------------

    @wire(getIdentity, { recordId: '$recordId' })
    wiredIdentity({ data, error }) {
        if (data) {
            this.identity = data;
            if (data.stage) this.stageValue = data.stage;
            if (data.level) this.levelValue = data.level;
        } else if (error) {
            this.errorText = error?.body?.message || 'Failed to load identity';
        }
    }

    // --------------- LIFECYCLE -------------

    connectedCallback() {
        this.loadPicklists();
        this.loadStageLevel();
        this.subscribeToEvents();
        onError(err => console.warn('EMP API Error:', JSON.stringify(err)));
    }

    disconnectedCallback() {
        this.stopTimer();
        this.clearFeedbackTimers();
        if (this.subscription) {
            unsubscribe(this.subscription, () => {});
            this.subscription = null;
        }
    }

    // -------------- DATA LOAD --------------

    async loadPicklists() {
        try {
            this.fullMap = await getL1L2Values();
            this.l1Options = Object.keys(this.fullMap).map(k => ({
                label: k,
                value: k
            }));
        } catch (e) {
            console.error('Picklist load failed:', e);
        }
    }

    async loadStageLevel() {
        try {
            const mapData = await getStageLevelValues();
            this.stageOptions = (mapData.stage || []).map(v => ({
                label: v,
                value: v
            }));
            this.levelOptions = (mapData.level || []).map(v => ({
                label: v,
                value: v
            }));
        } catch (e) {
            console.error('Stage/Level load failed:', e);
        }
    }

    // -------------- HANDLERS ---------------

    updateCommentVisibility() {
        const key = `${this.l1Value}:${this.l2Value}`;
        this.isCommentMandatory = this.mandatoryCommentRules[key] === true;
    }

    handleL1Change(e) {
        this.l1Value = e.target.value;
        this.l2Options = (this.fullMap[this.l1Value] || []).map(v => ({
            label: v,
            value: v
        }));
        this.isL2Disabled = this.l2Options.length === 0;
        this.l2Value = '';
        this.updateCommentVisibility();
    }

    handleL2Change(e) {
        this.l2Value = e.target.value;
        this.updateCommentVisibility();
    }

    handleStageChange(e) {
        this.stageValue = e.target.value;
    }

    handleLevelChange(e) {
        this.levelValue = e.target.value;
    }

    handleFeedbackChange(e) {
        this.feedback = e.target.value;
    }

    // 🔥 NEW: checkbox handler for "Auto set next follow up"
    handleAutoSetChange(e) {
        this.autoSetFollowUp = e.target.checked;

        if (this.autoSetFollowUp) {
            this.setAutoDate24();
        }
    }

    // 🔥 UPDATED: only allow manual date change when autoSetFollowUp is false
    handleNextFollowUpDateChange(e) {
        if (!this.autoSetFollowUp) {
            this.nextFollowUpDate = e.target.value;
        }
    }

    close() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    @api
    startCall() {
        this.callApi();
    }

    // -------------- CALL API ---------------

    async callApi() {
        this.callButtonDisabled = true;
        this.loading = true;
        this.errorText = null;

        this.callStatus = 'Dialing…';
        this.isLive = false;
        this.showFeedback = false;
        this.showCallPopup = true;
        this.canEndCall = false;

        this.setElapsed(0);
        this.startTimer();
        this.lastCallId = null;
        this.clearFeedbackTimers();

        try {
            const response = await allocateLeadNow({ recordId: this.recordId });

            const parsed =
                typeof response === 'string' ? JSON.parse(response) : response || {};

            this.lastCallId = parsed?.callId || this.lastCallId;
            this.callTitle = parsed?.displayName || 'Calling via Runo';
            this.callStatus = 'In Call…';
            this.isLive = true;

            this.showPopup = true;
            setTimeout(() => (this.showPopup = false), 4200);

            // 30s no-response timer → show End Call option
            this.clearFeedbackTimers();
            this.noResponseTimer = setTimeout(() => {
                if (this.isLive && this.callStatus !== 'Ended') {
                    this.canEndCall = true;
                    this.callStatus = 'No Response';
                }
            }, this.CALL_NO_RESPONSE_MS);
        } catch (e) {
            this.errorText = e?.body?.message || e?.message || 'Failed to dial';
            this.callStatus = 'Failed';
            this.isLive = false;
            this.showCallPopup = false;
            this.stopTimer();

            // still allow feedback when call setup fails
            this.showFeedback = true;
            this.callButtonDisabled = false;

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Failed',
                    message: this.errorText,
                    variant: 'error'
                })
            );
        } finally {
            this.loading = false;
        }
    }

    // manual end call (after 30s no response)
    handleEndCall() {
        if (!this.canEndCall && !this.isLive) {
            return;
        }

        this.callStatus = 'Ended';
        this.isLive = false;
        this.showCallPopup = false;

        this.stopTimer();
        this.clearFeedbackTimers();

        // show feedback when call is manually ended
        this.showFeedbackSection();
        this.callButtonDisabled = false;
    }

    get isSaveDisabled() {
        return this.savingFeedback || !this.showFeedback;
    }

    // 🔥 UPDATED: use autoSetFollowUp + setAutoDate24 (same as good LWC)
    showFeedbackSection() {
        this.showFeedback = true;
        this.disableCancel = false;

        if (this.autoSetFollowUp) {
            this.setAutoDate24();
        }
    }

    // 🔥 NEW: helper to set nextFollowUpDate = now + 24h in ISO format
    setAutoDate24() {
        const now = new Date();
        const next = new Date(now.getTime() + 24 * 60 * 60 * 1000);

        const yyyy = next.getFullYear();
        const mm = String(next.getMonth() + 1).padStart(2, '0');
        const dd = String(next.getDate()).padStart(2, '0');
        const hh = String(next.getHours()).padStart(2, '0');
        const mi = String(next.getMinutes()).padStart(2, '0');
        const ss = String(next.getSeconds()).padStart(2, '0');

        // full ISO-like string without timezone offset
        this.nextFollowUpDate = `${yyyy}-${mm}-${dd}T${hh}:${mi}:${ss}.000Z`;
    }

    // -------------- SAVE FEEDBACK ----------

    async saveFeedback() {
        debugger;
        if (this.isCommentMandatory && !this.feedback?.trim()) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Mandatory',
                    message: 'Feedback comment is required.',
                    variant: 'warning'
                })
            );
            return;
        }

        if (!this.stageValue) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Required',
                    message: 'Stage and Course are required.',
                    variant: 'warning'
                })
            );
            return;
        }

        this.savingFeedback = true;

        try {
            await updateCallFeedback({
                recordId: this.recordId,
                callId: this.lastCallId,
                feedback: this.feedback?.trim(),
                nextFollowUpDate: this.nextFollowUpDate,
                l1: this.l1Value,
                l2: this.l2Value,
                stage: this.stageValue,
                level: this.levelValue
            });

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Saved',
                    message: 'Feedback saved successfully.',
                    variant: 'success'
                })
            );

            this.clearFeedbackTimers();

            this.showFeedback = false;
            this.disableCancel = true;
            this.callStatus = 'Idle';
            this.isLive = false;
            this.showCallPopup = false;
            this.setElapsed(0);

            // reset fields like good LWC
            this.feedback = '';
            this.l1Value = '';
            this.l2Value = '';
            this.updateCommentVisibility();
            this.nextFollowUpDate = null;

            this.dispatchEvent(new CloseActionScreenEvent());
            setTimeout(() => window.location.reload(), 800);
        } catch (e) {
            let message = 'Failed to save feedback.';

            try {
                if (e && e.body) {
                    if (e.body.pageErrors && e.body.pageErrors.length) {
                        message = e.body.pageErrors[0].message;
                    } else if (
                        e.body.fieldErrors &&
                        e.body.fieldErrors.Stage__c &&
                        e.body.fieldErrors.Stage__c.length
                    ) {
                        message = e.body.fieldErrors.Stage__c[0].message;
                    } else if (e.body.message) {
                        message = e.body.message;
                    }
                } else if (e && e.message) {
                    message = e.message;
                }
            } catch (err) {}

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Save Failed',
                    message: message,
                    variant: 'error'
                })
            );
        }
 finally {
            this.savingFeedback = false;
            this.disableCancel = false;
        }
    }

    clearFeedbackTimers() {
        if (this.noResponseTimer) {
            clearTimeout(this.noResponseTimer);
            this.noResponseTimer = null;
        }
        this.canEndCall = false;
    }

    // -------------- TIMER ------------------

    startTimer() {
        if (this.timerId) return;
        const start = Date.now() - this.elapsedMs;
        this.timerId = setInterval(() => {
            this.setElapsed(Date.now() - start);
        }, 500);
    }

    stopTimer() {
        if (this.timerId) {
            clearInterval(this.timerId);
            this.timerId = null;
        }
    }

    setElapsed(ms) {
        this.elapsedMs = ms;
        const totalSec = Math.floor(ms / 1000);
        const mm = String(Math.floor(totalSec / 60)).padStart(2, '0');
        const ss = String(totalSec % 60).padStart(2, '0');
        this.elapsedLabel = `${mm}:${ss}`;
    }

    // -------------- EMP / EVENT ------------

    channelName = '/event/Runo_Call_Completed__e';
    subscription = null;

    subscribeToEvents() {
        if (this.subscription) return;

        subscribe(this.channelName, -1, msg => this.onRunoEvent(msg))
            .then(resp => {
                this.subscription = resp;
            })
            .catch(() => {});
    }

    onRunoEvent(msg) {
        debugger;
        const p = (msg && msg.data && msg.data.payload) || {};

        const evtLeadId =
            p.Lead_Id__c || p.LeadId__c || p.leadId || null;
        const evtCallId =
            p.Call_Id__c || p.CallId__c || p.callId || null;

        if (evtLeadId && String(evtLeadId) !== String(this.recordId)) {
            return;
        }

        if (evtCallId) {
            this.lastCallId = String(evtCallId);
        }

        const s = Number(
            p.Duration_Seconds__c ||
            p.Duration__c ||
            p.durationSeconds
        );

        if (!Number.isNaN(s) && s > 0) {
            const totalSec = Math.floor(s);
            const mm = String(Math.floor(totalSec / 60)).padStart(2, '0');
            const ss = String(totalSec % 60).padStart(2, '0');
            this.elapsedLabel = `${mm}:${ss}`;
        } else {
            this.elapsedLabel = '00:00';
        }

        this.callStatus = 'Ended';
        this.isLive = false;
        this.showCallPopup = false;

        this.stopTimer();
        this.clearFeedbackTimers();

        // show feedback when platform event says call ended
        this.showFeedbackSection();

        this.callButtonDisabled = false;

        console.log('RUNO EVENT => CALL ENDED (UI updated)');
    }

    // -------------- UTIL -------------------

    toast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }
}