import { api, LightningElement, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import allocateLeadNow from '@salesforce/apex/Webservice_RunoAllocationAPI.allocateLeadNow';
import updateCallFeedback from '@salesforce/apex/Webservice_RunoAllocationAPI.updateCallFeedback';
import getL1L2Values from '@salesforce/apex/Webservice_RunoAllocationAPI.getL1L2Values';
import getIdentity from '@salesforce/apex/RunoCallIdentityService.getIdentity';
import getStageLevelValues from '@salesforce/apex/Webservice_RunoAllocationAPI.getStageLevelValues';

import { CloseActionScreenEvent } from 'lightning/actions';
import { subscribe, unsubscribe, onError } from 'lightning/empApi';

export default class RunoAllocationCalls extends LightningElement {
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
            console.error('wiredIdentity error', error);
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
            try {
                unsubscribe(this.subscription, () => {});
            } catch (e) {
                console.warn('unsubscribe failed', e);
            }
            this.subscription = null;
        }
    }

    // -------------- DATA LOAD --------------
    async loadPicklists() {
        try {
            const map = await getL1L2Values();
            this.fullMap = map || {};
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

    handleNextFollowUpDateChange(e) {
        this.nextFollowUpDate = e.target.value;
    }

    close() {
        try {
            this.dispatchEvent(new CloseActionScreenEvent());
        } catch (err) {
            // not always running in quick-action context - safe to ignore
            console.warn('CloseActionScreenEvent dispatch failed (ignored):', err);
        }
    }

    @api
    startCall() {
        if (!this.recordId) {
            console.warn('startCall: missing recordId');
            return;
        }
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
            const response = await allocateLeadNow({ leadId: this.recordId });

            let parsed = {};
            try {
                parsed = typeof response === 'string' ? JSON.parse(response) : (response || {});
            } catch (parseErr) {
                parsed = response || {};
                console.warn('Non-JSON allocateLeadNow response', parseErr, response);
            }

            this.lastCallId = parsed?.callId || this.lastCallId;
            this.callTitle = parsed?.displayName || 'Calling via Runo';
            this.callStatus = 'In Call…';
            this.isLive = true;

            this.showPopup = true;
            setTimeout(() => (this.showPopup = false), 4200);

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

            this.showFeedback = true;
            this.callButtonDisabled = false;

            try {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Failed',
                        message: this.errorText,
                        variant: 'error'
                    })
                );
            } catch (toastErr) {
                console.error('toast dispatch failed', toastErr);
            }

            console.error('callApi error', e);
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

        this.showFeedbackSection();
        this.callButtonDisabled = false;
    }

    get isSaveDisabled() {
        return this.savingFeedback || !this.showFeedback;
    }

    showFeedbackSection() {
        this.showFeedback = true;
        this.disableCancel = false;

        if (!this.nextFollowUpDate) {
            const now = new Date();
            const nextDay = new Date(now.getTime() + 24 * 60 * 60 * 1000);

            const yyyy = nextDay.getFullYear();
            const mm = String(nextDay.getMonth() + 1).padStart(2, '0');
            const dd = String(nextDay.getDate()).padStart(2, '0');
            const hh = String(nextDay.getHours()).padStart(2, '0');
            const min = String(nextDay.getMinutes()).padStart(2, '0');

            this.nextFollowUpDate = `${yyyy}-${mm}-${dd}T${hh}:${min}`;
        }
    }

    // -------------- SAVE FEEDBACK ----------
    async saveFeedback() {
        debugger;
        if (this.isCommentMandatory && !this.feedback?.trim()) {
            this.toast('Mandatory', 'Feedback comment is required.', 'warning');
            return;
        }

        if (!this.stageValue) {
            this.toast('Required', 'Stage and Course are required.', 'warning');
            return;
        }

        this.savingFeedback = true;

        try {
            await updateCallFeedback({
                leadId: this.recordId,
                callId: this.lastCallId,
                feedback: this.feedback?.trim(),
                nextFollowUpDate: this.nextFollowUpDate,
                l1: this.l1Value,
                l2: this.l2Value,
                stage: this.stageValue,
                level: this.levelValue
            });

            this.toast('Saved', 'Feedback saved successfully.', 'success');

            const eventDetail = {
                recordId: this.recordId,
                callId: this.lastCallId,
                feedback: this.feedback?.trim() || '',
                nextFollowUpDate: this.nextFollowUpDate || null,
                l1: this.l1Value || '',
                l2: this.l2Value || '',
                stage: this.stageValue || '',
                level: this.levelValue || ''
            };

            this.clearFeedbackTimers();
            this.showFeedback = false;
            this.callStatus = 'Idle';
            this.isLive = false;
            this.showCallPopup = false;
            this.setElapsed(0);

            // reset fields after we captured eventDetail
            this.feedback = '';
            this.l1Value = '';
            this.l2Value = '';
            this.updateCommentVisibility();
            this.nextFollowUpDate = null;

            try {
                this.dispatchEvent(
                    new CustomEvent('callcomplete', {
                        detail: eventDetail,
                        bubbles: true,
                        composed: true
                    })
                );
            } catch (evErr) {
                console.error('callcomplete dispatch failed (non-fatal):', evErr);
            }

        } catch (e) {
            this.toast(
                'Save Failed',
                e?.body?.message || e?.message || 'Failed to save feedback.',
                'error'
            );
            console.error('saveFeedback error', e);
        } finally {
            this.savingFeedback = false;
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
            .catch(err => {
                console.warn('subscribe failed', err);
            });
    }

    onRunoEvent(msg) {
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

        try {
            this.showFeedbackSection();
        } catch (e) {
            console.error('showFeedbackSection failed', e);
        }

        this.callButtonDisabled = false;

        console.log('RUNO EVENT => CALL ENDED (UI updated)');
    }

    // -------------- UTIL -------------------
    toast(title, message, variant) {
        try {
            this.dispatchEvent(
                new ShowToastEvent({
                    title,
                    message,
                    variant
                })
            );
        } catch (e) {
            console.error('toast dispatch failed', e);
        }
    }
}