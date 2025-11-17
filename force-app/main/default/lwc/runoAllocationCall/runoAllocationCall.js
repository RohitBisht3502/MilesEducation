import { api, LightningElement, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import allocateLeadNow from '@salesforce/apex/Webservice_RunoAllocationAPI.allocateLeadNow';
import updateCallFeedback from '@salesforce/apex/Webservice_RunoAllocationAPI.updateCallFeedback';
import getL1L2Values from '@salesforce/apex/Webservice_RunoAllocationAPI.getL1L2Values';
import getIdentity from '@salesforce/apex/RunoCallIdentityService.getIdentity';

import { CloseActionScreenEvent } from 'lightning/actions';
import { subscribe, unsubscribe, onError } from 'lightning/empApi';

export default class RunoAllocationCall extends LightningElement {
    @api recordId;

    loading = false;
    disableCancel = false;

    l1Value = '';
    l2Value = '';
    l1Options = [];
    l2Options = [];
    fullMap = {};
    isL2Disabled = true;

    showPopup = false; // <-- popup for success

    showCallPopup = false; // existing UI
    resultText;
    errorText;
    channelName = '/event/Runo_Call_Completed__e';
    subscription;

    identity = { name: '', email: '', phone: '', city: '', source: '' };

    // CALL UI STATES
    isLive = false;
    callStatus = 'Idle';
    callTitle = 'Calling via Runo';

    elapsedMs = 0;
    elapsedLabel = '00:00';
    timerId = null;

    // FEEDBACK UI
    showFeedback = false;
    showCallBanner = false;
    feedback = '';
    nextFollowUpDate = null;
    savingFeedback = false;

    lastCallId = null;

    /* LOAD IDENTITY */
    @wire(getIdentity, { recordId: '$recordId' })
    wiredIdentity({ data, error }) {
        if (data) {
            this.identity = data;
        } else if (error) {
            this.errorText = error?.body?.message || 'Failed to load identity';
        }
    }

    /* INIT */
    connectedCallback() {
        this.loadPicklists();
        this.subscribeToEvents();

        onError((err) => {
            console.warn('EMP API Error:', JSON.stringify(err));
        });
    }

    disconnectedCallback() {
        this.stopTimer();
        if (this.subscription) {
            unsubscribe(this.subscription, () => {});
            this.subscription = null;
        }
    }

    /* PICKLIST LOAD */
    async loadPicklists() {
        try {
            this.fullMap = await getL1L2Values();
            this.l1Options = Object.keys(this.fullMap).map(k => ({ label: k, value: k }));
        } catch (e) {
            console.error('Picklist load failed:', e);
        }
    }

    /* UI HANDLERS */
    handleL1Change(e) {
        this.l1Value = e.target.value;
        const list = this.fullMap[this.l1Value] || [];

        this.l2Options = list.map(i => ({ label: i, value: i }));
        this.l2Value = '';
        this.isL2Disabled = this.l2Options.length === 0;
    }

    handleL2Change(e) {
        this.l2Value = e.target.value;
    }

    handleFeedbackChange(e) {
        this.feedback = e.target.value;
    }

    handleNextFollowUpDateChange(e) {
        this.nextFollowUpDate = e.target.value;
    }

    /* CLOSE */
    close() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    /* POPUP TRIGGER */
    triggerCallSuccessPopup() {
        this.showPopup = true;
        setTimeout(() => { this.showPopup = false; }, 4200);
    }

    /* RUNO CALL */
    async callApi() {
        this.disableCancel = true;
        this.loading = true;
        this.errorText = null;
        this.resultText = null;
        this.showFeedback = false;

        this.callStatus = 'Dialing…';
        this.isLive = false;
        this.lastCallId = null;

        this.setElapsed(0);
        this.startTimer();

        this.showCallBanner = true;
        this._toggleCallPulse(true);

        try {
            const response = await allocateLeadNow({ leadId: this.recordId });

            let parsed;
            try {
                parsed = JSON.parse(response);
            } catch {
                parsed = {};
            }

            this.lastCallId = parsed?.callId || parsed?.data?.callId || null;
            this.callTitle = parsed?.displayName || 'Calling via Runo';
            this.callStatus = 'In Call…';

            this.isLive = true;

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Runo Allocation',
                    message: 'Call sent successfully.',
                    variant: 'success'
                })
            );

            /* 🔥 SHOW SUCCESS POPUP HERE */
            this.triggerCallSuccessPopup();

        } catch (e) {
            this.errorText = e?.body?.message || e?.message || 'Failed to dial';
            this.callStatus = 'Failed';
            this.isLive = false;
            this.showCallBanner = false;

            this._toggleCallPulse(false);
            this.stopTimer();
        } finally {
            this.loading = false;
        }
    }

    /* SAVE FEEDBACK */
    async saveFeedback() {
        if (!this.feedback?.trim()) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Feedback Required',
                    message: 'Please enter call feedback.',
                    variant: 'warning'
                })
            );
            return;
        }

        this.savingFeedback = true;

        try {
            await updateCallFeedback({
                leadId: this.recordId,
                callId: this.lastCallId,
                feedback: this.feedback.trim(),
                nextFollowUpDate: this.nextFollowUpDate,
                l1: this.l1Value,
                l2: this.l2Value
            });

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Saved',
                    message: 'Feedback saved successfully.',
                    variant: 'success'
                })
            );

            setTimeout(() => this.close(), 600);
        } catch (e) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Save Failed',
                    message: e?.body?.message || e?.message || 'Failed to save feedback.',
                    variant: 'error'
                })
            );
        } finally {
            this.savingFeedback = false;
            this.disableCancel = false;
        }
    }

    /* EVENT SUB */
    subscribeToEvents() {
        if (this.subscription) return;

        subscribe(this.channelName, -1, (payload) => this.onRunoEvent(payload))
            .then(res => {
                this.subscription = res;
            })
            .catch(err => console.error('Subscribe failed:', err));
    }

    /* HANDLE RUNO EVENT */
    onRunoEvent(msg) {
        const p = msg?.data?.payload || {};
        const evtCallId = p.Call_Id__c;
        const evtLeadId = p.Lead_Id__c;

        if (evtLeadId !== this.recordId && evtCallId !== this.lastCallId) return;

        this.callStatus = 'Ended';
        this.isLive = false;
        this.stopTimer();

        this.showFeedback = true;
        this.disableCancel = false;
        this.showCallBanner = false;

        this._toggleCallPulse(false);

        const sec = Number(p.Duration_Seconds__c);
        if (!isNaN(sec)) {
            this.setElapsed(sec * 1000);
        }
    }

    /* FORCE END UI ONLY */
    forceEndCall() {
        this.callStatus = 'Ended';
        this.isLive = false;
        this.stopTimer();
        this.showFeedback = true;
        this.showCallBanner = false;
        this._toggleCallPulse(false);
        this.disableCancel = false;
    }

    /* TIMER */
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

        const s = Math.floor(ms / 1000);
        const mm = String(Math.floor(s / 60)).padStart(2, '0');
        const ss = String(s % 60).padStart(2, '0');

        this.elapsedLabel = `${mm}:${ss}`;
    }

    /* BUTTON ANIMATION */
    _toggleCallPulse(on) {
        const btn = this.template.querySelector('[data-id="callBtn"]');
        if (!btn) return;

        if (on) btn.classList.add('live-pulse');
        else btn.classList.remove('live-pulse');
    }
}