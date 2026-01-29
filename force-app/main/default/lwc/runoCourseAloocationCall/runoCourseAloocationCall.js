import { api, LightningElement, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import allocateCourseNow from '@salesforce/apex/Webservice_RunoAllocationAPI.allocateCourseNow';
import updateCourseCallFeedback from '@salesforce/apex/Webservice_RunoAllocationAPI.updateCourseCallFeedback';
import getL1L2Values from '@salesforce/apex/Webservice_RunoAllocationAPI.getL1L2Values';
import getIdentity from '@salesforce/apex/RunoCallIdentityService.getIdentity';
import getStageLevelValues from '@salesforce/apex/Webservice_RunoAllocationAPI.getStageLevelValues';

import { CurrentPageReference } from 'lightning/navigation';
import { NavigationMixin } from 'lightning/navigation';
import { subscribe, unsubscribe, onError } from 'lightning/empApi';
import { CloseActionScreenEvent } from 'lightning/actions';


export default class RunoAllocationCall extends NavigationMixin(LightningElement) {
    @api recordId;

    // UI & Loading
    loading = false;
    callButtonDisabled = false;
    callButtonLabel = 'Call Runo';
    showCallPopup = false;
    showFeedback = false;
    errorText;
    feedback = '';


    // Picklists
    l1Value = '';
    l2Value = '';
    l1Options = [];
    l2Options = [];
    fullMap = {};
    isL2Disabled = true;

    stageValue = '';
    levelValue = '';
    stageOptions = [];
    levelOptions = [];
    autoSetFollowUp = true;

    // Identity
    identity = { name:'', email:'', phone:'', city:'', source:'', stage:'' };

    // Auto-call
    autoCall = false;
    hasAutoCalled = false;

    // Follow-up
    nextFollowUpDate = null;

    // Call
    isLive = false;
    callStatus = 'Idle';
    elapsedMs = 0;
    elapsedLabel = '00:00';
    timerId = null;

    canEndCall = false;
    CALL_NO_RESPONSE_MS = 30000;
    noResponseTimer = null;
    lastCallId = null;

    STAGE_FOLLOW_UP_RULES = {
        'M7+':  { maxDays: 3 }, 'M7#-': { maxDays: 3 }, 'M7##': { maxDays: 3 },
        'M8':   { maxDays: 30 }, 'M9': { maxDays: 30 }, 'M9+': { maxDays: 14 },
        'M10':  { maxDays: 1 }, 'M10+': { maxDays: 30 },
        'M11':  { maxDays: 7 }, 'M11+': { maxDays: 1 }, 'M11#': { maxDays: 30 },
        'M12':  { maxDays: null }, 'M13': { maxDays: 30 },
        DEFAULT: { maxDays: 1 }
    };

    // ------------------- WIRE METHODS -------------------
    @wire(getIdentity, { recordId: '$recordId' })
    wiredIdentity({ data, error }) {
        if (data) {
            this.identity = data;
            this.stageValue = data.stage || '';
            this.setDefaultFollowUp();
        } else if (error) {
            this.errorText = error?.body?.message || 'Failed to load identity';
        }
    }

    @wire(CurrentPageReference)
    wiredPageRef(pageRef) {
        this.pageRef = pageRef;
        const state = pageRef?.state || {};
        if (state.c__autoCall === 'true') this.autoCall = true;
        this.resolveRecordIdFromPageRef();
    }

    resolveRecordIdFromPageRef() {
        if (this.recordId) return;
        const state = this.pageRef?.state || {};
        const recId = state.recordId || state.c__recordId || state.id || state.c__id;
        if (recId && (recId.length === 15 || recId.length === 18)) this.recordId = recId;
    }

    connectedCallback() {
        this.resolveRecordIdFromPageRef();
        this.loadPicklists();
        this.loadStageLevel();
        this.subscribeToEvents();
        onError(err => console.warn('EMP API Error:', JSON.stringify(err)));

        if (this.autoCall && this.recordId && !this.hasAutoCalled) {
            setTimeout(() => this.startCall(), 500);
        }
    }

    disconnectedCallback() {
        this.stopTimer();
        this.clearNoResponseTimer();
        if (this.subscription) {
            unsubscribe(this.subscription, () => {});
            this.subscription = null;
        }
    }

    // ------------------- PICKLIST METHODS -------------------
    async loadPicklists() {
        try {
            this.fullMap = await getL1L2Values() || {};
            this.l1Options = Object.keys(this.fullMap).map(k => ({ label: k, value: k })) || [];
        } catch (e) {
            this.toast('Error', 'Failed to load L1/L2 picklists', 'error');
        }
    }

    handleFeedbackChange(event) {
    this.feedback = event.target.value;
}


    handleL1Change(event) {
        const val = event?.detail?.value || '';
        this.l1Value = val;
        this.l2Options = (this.fullMap[val] || []).map(v => ({ label: v, value: v }));
        this.isL2Disabled = this.l2Options.length === 0;
        this.l2Value = this.l2Options.length === 1 ? this.l2Options[0].value : '';
    }

    handleL2Change(event) {
        this.l2Value = event?.detail?.value || '';
    }

    async loadStageLevel() {
        try {
            const mapData = await getStageLevelValues() || {};
            this.stageOptions = (mapData.stage || []).map(v => ({ label: v, value: v }));
            this.levelOptions = (mapData.level || []).map(v => ({ label: v, value: v }));
        } catch (e) {
            this.toast('Error', 'Failed to load stage/level picklists', 'error');
        }
    }

    handleStageChange(event) {
        const val = event?.detail?.value || '';
        if (!val) return;
        this.stageValue = val;
        if (this.autoSetFollowUp) this.setDefaultFollowUp();
    }

    handleLevelChange(event) {
        this.levelValue = event?.detail?.value || '';
    }

    handleAutoSetChange(event) {
        this.autoSetFollowUp = event.target.checked;
        if (this.autoSetFollowUp) this.setDefaultFollowUp();
    }

    // ------------------- CALL METHODS -------------------
    @api startCall() {
        if (!this.recordId || this.isLive) return;
        this.hasAutoCalled = true;
        this.callApi();
    }

    async callApi() {
        this.callButtonDisabled = true;
        this.loading = true;
        this.showCallPopup = true;
        this.callStatus = 'Calling…';

        try {
            const response = await allocateCourseNow({ recordId: this.recordId });
            const parsed = JSON.parse(response || '{}');
            this.lastCallId = parsed?.callId;

            this.callStatus = 'In Call…';
            this.isLive = true;

            this.startTimer();
            this.startNoResponseTimer();

        } catch (e) {
            this.toast('Failed', e?.body?.message || 'Dial failed', 'error');
            this.showCallPopup = false;
            this.callButtonDisabled = false;
        } finally {
            this.loading = false;
        }
    }

    handleEndCall() {
        this.endCallFlow();
    }

    onRunoEvent(msg) {
        const p = msg?.data?.payload || {};
        if (String(p.Course_Enrolled_Id__c) !== String(this.recordId)) return;
        this.endCallFlow();
    }

    endCallFlow() {
        this.callStatus = 'Ended';
        this.isLive = false;
        this.showCallPopup = false;

        this.stopTimer();
        this.clearNoResponseTimer();

        // Open feedback automatically
        this.showFeedback = true;
    }

    startTimer() {
        this.stopTimer();
        this.elapsedMs = 0;
        this.elapsedLabel = '00:00';
        this.timerId = setInterval(() => {
            this.elapsedMs += 1000;
            const totalSec = Math.floor(this.elapsedMs / 1000);
            const min = String(Math.floor(totalSec / 60)).padStart(2, '0');
            const sec = String(totalSec % 60).padStart(2, '0');
            this.elapsedLabel = `${min}:${sec}`;
        }, 1000);
    }

    stopTimer() {
        if (this.timerId) clearInterval(this.timerId);
        this.timerId = null;
    }

    startNoResponseTimer() {
        this.clearNoResponseTimer();
        this.canEndCall = false;
        this.noResponseTimer = setTimeout(() => this.canEndCall = true, this.CALL_NO_RESPONSE_MS);
    }

    clearNoResponseTimer() {
        if (this.noResponseTimer) clearTimeout(this.noResponseTimer);
        this.noResponseTimer = null;
    }

    // ------------------- FEEDBACK METHODS -------------------
    setDefaultFollowUp() {
        const d = new Date();
        d.setHours(d.getHours() + 24);
        this.nextFollowUpDate = d.toISOString().slice(0, 16);
    }

    get minFollowUpDate() {
        const d = new Date();
        d.setHours(d.getHours() + 24);
        return d.toISOString().slice(0, 16);
    }

    get maxFollowUpDate() {
        const rule = this.STAGE_FOLLOW_UP_RULES[this.stageValue] || this.STAGE_FOLLOW_UP_RULES.DEFAULT;
        if (!rule.maxDays) return null;
        const d = new Date();
        d.setDate(d.getDate() + rule.maxDays);
        return d.toISOString().slice(0, 16);
    }

    handleNextFollowUpDateChange(event) {
        const val = event?.target?.value;
        if (!val) return;
        const selected = new Date(val);
        const max = this.maxFollowUpDate ? new Date(this.maxFollowUpDate) : null;
        if (max && selected > max) {
            this.toast('Invalid Follow Up Date', `Maximum follow-up allowed for ${this.stageValue} is ${this.maxFollowUpDate}`, 'error');
            return;
        }
        this.nextFollowUpDate = val;
    }

    async saveFeedback() {
        if (!this.recordId) return;
        try {
            await updateCourseCallFeedback({
                jsonBody: JSON.stringify({
                    recordId: this.recordId,
                    callId: this.lastCallId,
                    feedback: this.feedback || '',
                    nextFollowUpDate: this.nextFollowUpDate || null,
                    l1: this.l1Value || '',
                    l2: this.l2Value || '',
                    stage: this.stageValue || '',
                    notifyMe: false
                })
            });
            this.toast('Saved', 'Feedback saved successfully', 'success');

                    this.dispatchEvent(new CloseActionScreenEvent());
        } catch (e) {
            this.toast('Error', e?.body?.message || 'Save failed', 'error');
        }
    }

    // ------------------- NAVIGATION -------------------
    navigateAfterSave() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: { objectApiName: 'Course_Enrolled__c', actionName: 'list' },
            state: { filterName: 'All' }
        });
    }

    // ------------------- EMP API -------------------
    channelName = '/event/Runo_Call_Completed__e';
    subscription = null;

    subscribeToEvents() {
        subscribe(this.channelName, -1, msg => this.onRunoEvent(msg))
            .then(resp => this.subscription = resp);
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}