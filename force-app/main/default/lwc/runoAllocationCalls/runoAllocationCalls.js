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
    @api isCallLog; 
    @api isQueuePaused;
    @api isQueueRunning;

    // ---------------------------------------------
    // 🔥 ADDED: flag for renderedCallback
    // ---------------------------------------------
    hasRendered = false;
isStageDisabled = false;
 
    // UI / state
    loading = false;
    disableCancel = false;

    callButtonLabel = 'Call Runo';
    callButtonDisabled = false;


    // Call popup overlay (Calling Runo...)
    showCallPopup = false;


userChangedStage = false;

    // L1/L2
    l1Value = '';
    l2Value = '';
    l1Options = [];
    l2Options = [];
    fullMap = {};
    isL2Disabled = true;
   
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
    notifyMe = false; 

handleNotifyChange(event) {
    this.notifyMe = event.target.checked;
}


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



    // ---------------------------------------------
    // 🔥 ADDED: renderedCallback to notify parent
    // ---------------------------------------------
    renderedCallback() {
        if (!this.hasRendered) {
            this.hasRendered = true;
            try {
                this.dispatchEvent(
                    new CustomEvent('componentready', {
                        bubbles: true,
                        composed: true
                    })
                );
            } catch (e) {
                console.error('componentready dispatch failed', e);
            }
        }
    }
  handleAutoSetChange(e) {
    this.autoSetFollowUp = e.target.checked;

    if (this.autoSetFollowUp) {
        this.setAutoDate24();
    } else {
        // ✅ Allow manual entry without override
        this.nextFollowUpDate = null;
    }
}


    // ---------------------------------------------

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
    this.userChangedStage = false; // 👈 reset

    this.l2Options = (this.fullMap[this.l1Value] || []).map(v => ({
        label: v,
        value: v
    }));
    this.isL2Disabled = this.l2Options.length === 0;
    this.l2Value = '';

    if (this.l1Value === 'Not-Connected') {
        this.isStageDisabled = true;
        this.stageValue = null;
    } else {
        this.isStageDisabled = false;
    }

    this.updateCommentVisibility();
}

    handleL2Change(e) {
        this.l2Value = e.target.value;
        this.updateCommentVisibility();
        this.applyAutoStageLogic();
    }

    handleStageChange(e) {
        this.stageValue = e.target.value;
          this.userChangedStage = true;
    }

    handleLevelChange(e) {
        this.levelValue = e.target.value;
    }

    handleFeedbackChange(e) {
        this.feedback = e.target.value;
    }

 handleNextFollowUpDateChange(e) {
    if (!this.autoSetFollowUp) {
        this.nextFollowUpDate = e.target.value;
    }
}



    close() {
        try {
            this.dispatchEvent(new CloseActionScreenEvent());
        } catch (err) {
            console.warn('CloseActionScreenEvent dispatch failed (ignored):', err);
        }
    }

    // ----------------------------
    // API call from PARENT
    // ----------------------------
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
            const response = await allocateLeadNow({ recordId: this.recordId });

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

    // manual end call…
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
applyAutoStageLogic() {
    // Do nothing if user already selected stage.
    if (this.userChangedStage) {
        return;
    }

    if (this.l1Value === 'Connected') {
        const connectedStageMap = {
            'Not Eligible': 'M1',
            'Wrong Number': 'M1',
            'Not Interested (DND)': 'M1',
            'Language Barrier': 'M1',
            'Visit Confirmed': 'M3+',
            'Google Meet Completed': 'M3+',
            'Gmeet Confirmed': 'M3+',
            'Postponed': 'M4'
        };

        const autoStage = connectedStageMap[this.l2Value];
        if (autoStage) {
            this.stageValue = autoStage;
        }
        return;
    }

    if (this.l1Value === 'Not-Connected') {
        this.stageValue = this.l2Value === 'Invalid Number' ? 'M1' : null;
    }
}






    // get isSaveDisabled() {
    //     return this.savingFeedback || !this.showFeedback;
    // }

  showFeedbackSection() {
    this.showFeedback = true;
    this.disableCancel = false;

    // ✅ Only auto-set if:
    // 1) autoSetFollowUp is true
    // 2) user has NOT already selected a date
    if (this.autoSetFollowUp && !this.nextFollowUpDate) {
        this.setAutoDate24();
    }
}



setAutoDate24() {
    const next = new Date();
    next.setHours(next.getHours() + 24);

    const yyyy = next.getFullYear();
    const mm = String(next.getMonth() + 1).padStart(2, '0');
    const dd = String(next.getDate()).padStart(2, '0');
    const hh = String(next.getHours()).padStart(2, '0');
    const mi = String(next.getMinutes()).padStart(2, '0');

    // datetime-local format (NO timezone issues)
    this.nextFollowUpDate = `${yyyy}-${mm}-${dd}T${hh}:${mi}`;
}



    

    // -------------- SAVE FEEDBACK ----------
    async saveFeedback() {
        if (this.isCommentMandatory && !this.feedback?.trim()) {
            this.toast('Mandatory', 'Feedback comment is required.', 'warning');
            return false;
        }

        if (this.l1Value === 'Connected' && !this.stageValue) {
            this.toast('Required', 'Stage and Course are required.', 'warning');
            return false;
        }
         if (!this.l1Value) {
            this.toast('Required', 'L1 is required.', 'warning');
            return false;
        }
         if (!this.l2Value) {
            this.toast('Required', 'l2 is required.', 'warning');
            return false;
        }
        if(this.l1Value === 'Not-Connected'){
            this.stageValue = null;
        }

        this.savingFeedback = true;
        console.log('Saving feedback, callId = ', this.lastCallId);


        try {
            
            const payload ={
                
                recordId: this.recordId,
                callId: this.lastCallId,
                feedback: this.feedback?.trim(),
                nextFollowUpDate: this.nextFollowUpDate,
                l1: this.l1Value,
                l2: this.l2Value,
                level: this.levelValue,
                notifyMe: this.notifyMe
            };
            if (this.stageValue && String(this.stageValue).trim()) {
                payload.stage = this.stageValue;
            }
             await updateCallFeedback({
                jsonBody: JSON.stringify(payload)
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

            // Reset fields AFTER building eventDetail
            this.feedback = '';
            this.l1Value = '';
            this.l2Value = '';
            this.updateCommentVisibility();
            this.nextFollowUpDate = null;

            // ---------------------------------------------
            // 🔥 callcomplete event (already exists)
            // ---------------------------------------------
            this.dispatchEvent(
                new CustomEvent('callcomplete', {
                    detail: eventDetail,
                    bubbles: true,
                    composed: true
                })
            );
            return true;

       } catch (e) {
    console.error('FEEDBACK SAVE ERROR RAW:', JSON.stringify(e));

    const err =
        e?.body?.message ||
        e?.body?.exceptionMessage ||
        e?.message ||
        'Unknown error';

    this.toast('Save Failed', err, 'error');
    return false;
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

    async handlePauseQueue(){
        const saved = await this.saveFeedback();
        if (!saved) {
            return;
        }
        this.dispatchEvent(
            new CustomEvent('pausequeue', {
                bubbles : true,
                composed :true

            })
        );
    }
    async handleResumeQueue(){
        const saved = await this.saveFeedback();
        if (!saved) {
            return;
        }
        this.dispatchEvent(
            new CustomEvent('resumequeue',{
                detail: { stopQueue: true },
                bubbles :true,
                composed :true
            })
        );
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
        debugger;
        const p = (msg && msg.data && msg.data.payload) || {};

        const evtLeadId = p.Lead_Id__c || p.LeadId__c || p.leadId || null;
        const evtCallId = p.Call_Id__c || p.CallId__c || p.callId || null;
        // added by rohit for also work for call logs
        if (this.isCallLog) {
            if (this.lastCallId && evtCallId && String(evtCallId) !== String(this.lastCallId)) return;
        } else {
            if (evtLeadId && String(evtLeadId) !== String(this.recordId)) return;
        }

        // if (evtLeadId && String(evtLeadId) !== String(this.recordId)) return;

        // if (evtCallId) {
        //     this.lastCallId = String(evtCallId);
        // }

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
//// disable pause button 

get disablePauseBtn(){
    return !this.isLive;
}

get disableSaveDispositionBtn() {
    return this.savingFeedback || !this.showFeedback;
}

get panelHeader() {
    return `Calling via Runo | ${this.callStatus} | ${this.elapsedLabel}`;
}

get statusPillClass() {
    const status = (this.callStatus || '').toLowerCase();
    if (status.includes('in call') || status.includes('dialing')) return 'status-pill live';
    if (status.includes('failed') || status.includes('no response')) return 'status-pill warn';
    return 'status-pill ended';
}

get leadNameDisplay() {
    return this.identity?.name || 'NA';
}

get cityDisplay() {
    return this.identity?.city || 'NA';
}

get companyDisplay() {
    return this.identity?.source || 'NA';
}

get stageDisplay() {
    return this.identity?.stage || 'NA';
}




}
