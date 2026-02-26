import { api, LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import allocateLeadNow from '@salesforce/apex/Webservice_RunoAllocationAPI.allocateLeadNow';
import updateCallFeedback from '@salesforce/apex/Webservice_RunoAllocationAPI.updateCallFeedback';
import getL1L2Values from '@salesforce/apex/Webservice_RunoAllocationAPI.getL1L2Values';
import getCallHistory from '@salesforce/apex/Webservice_RunoAllocationAPI.getCallHistory';
import getIdentity from '@salesforce/apex/RunoCallIdentityService.getIdentity';
import getStageLevelValues from '@salesforce/apex/Webservice_RunoAllocationAPI.getStageLevelValues';
import getDispositions from '@salesforce/apex/CallDispositionConfigService.getDispositions';
import { CurrentPageReference } from 'lightning/navigation';
import { NavigationMixin } from 'lightning/navigation';
import { CloseActionScreenEvent } from 'lightning/actions';
import { subscribe, unsubscribe, onError } from 'lightning/empApi';
import { getRecord } from 'lightning/uiRecordApi';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import LEAD_OBJECT from '@salesforce/schema/Lead__c';
import LEAD_RECORDTYPE_FIELD from '@salesforce/schema/Lead__c.RecordTypeId';
import getWebinarMembers from '@salesforce/apex/Webservice_RunoAllocationAPI.getWebinarMembers';
import getLeadEvents from '@salesforce/apex/Webservice_RunoAllocationAPI.getLeadEvents';

export default class RunoAllocationCallQ1 extends NavigationMixin(LightningElement) {

    @api recordId;
    _dispositions;
    @api
    get dispositions() {
        return this._dispositions;
    }
    set dispositions(value) {
        this._dispositions = value;
        if (value && Array.isArray(value)) {
            this.processDispositions(value);
        }
    }

    loading = false;
    disableCancel = false;
    callButtonLabel = 'Call Runo';
    callButtonDisabled = false;
    showCallPopup = false;
    isStageDisabled = false;
    activeTab = 'lead';
    expectedPaymentDate;
    notifyMe = false;

    l1Value = '';
    l2Value = '';
    @track _allL1Options = [];
    @track fullMap = {};
    isL2Disabled = true;

    autoSetFollowUp = true;
    userChangedStage = false;

    stageValue = '';
    levelValue = '';
    stageOptions = [];
    levelOptions = [];
    leadRecordTypeId = null;
    @track hasActualConnection = false;

    @api autoCall = false;
    hasAutoCalled = false;

    showPopup = false;
    errorText;

    identity = {
        name: '',
        email: '',
        phone: '',
        city: '',
        source: '',
        stage: '',
        level: '',
        canId: '',
        createdDate: '',
        mhpTag: '',
        leadOwner: ''
    };

    callHistory = [];
    eventHistory = [];
    eventLoaded = false;
    isDnd = false;
    isSpam = false;

    isLive = false;
    callStatus = 'Idle';
    callTitle = 'Calling via Runo';
    elapsedMs = 0;
    elapsedLabel = '00:00';
    timerId = null;
    webinarHistory = [];
    webinarLoaded = false;

    showFeedback = false;
    savingFeedback = false;
    feedback = '';
    nextFollowUpDate = null;
    lastCallId = null;

    canEndCall = false;
    CALL_NO_RESPONSE_MS = 30000;
    noResponseTimer = null;

    mandatoryCommentRules = {};

    @wire(getIdentity, { recordId: '$recordId' })
    wiredIdentity({ data, error }) {
        if (data) {
            this.identity = data;
            if (data.stage) this.stageValue = data.stage;
            if (data.level) this.courseValue = data.level;
        } else if (error) {
            this.errorText = error?.body?.message || 'Failed to load identity';
        }
    }

    @wire(getObjectInfo, { objectApiName: LEAD_OBJECT })
    objectInfo;

    get recordTypeId() {
        return this.leadRecordTypeId || this.objectInfo?.data?.defaultRecordTypeId;
    }

    @wire(getRecord, { recordId: '$recordId', fields: [LEAD_RECORDTYPE_FIELD] })
    wiredLeadRecordType({ data }) {
        if (data) {
            this.leadRecordTypeId = data.fields.RecordTypeId?.value;
        }
    }

    @wire(CurrentPageReference)
    wiredPageRef(pageRef) {
        this.pageRef = pageRef;
        const state = pageRef?.state;
        if (!state) return;
        this.resolveRecordIdFromPageRef();
        if (state.c__autoCall === 'true') {
            this.autoCall = true;
        }
    }

    get showFeedbackInLeadTab() {
        return this.isLeadTab && this.showFeedback;
    }

    get isLeadTab() {
        return this.activeTab === 'lead';
    }

    get isHistoryTab() {
        return this.activeTab === 'history';
    }

    get l1Options() {
        const options = (this._allL1Options || []);
        if (this.hasActualConnection) {
            return options.filter(opt => opt.value === 'Connected');
        }
        return options.filter(opt => opt.value === 'Not-Connected');
    }

    get l2Options() {
        if (!this.l1Value || !this.fullMap) return [];
        return (this.fullMap[this.l1Value] || []).map(v => ({ label: v, value: v }));
    }

    handleTabClick(event) {
        this.activeTab = event.target.dataset.tab;
        if (this.activeTab === 'webinar' && !this.webinarLoaded) {
            this.loadWebinarHistory();
        }
        if (this.activeTab === 'event' && !this.eventLoaded) {
            this.loadEventHistory();
        }
    }

    get leadTabClass() {
        return `tab-item ${this.activeTab === 'lead' ? 'active' : ''}`;
    }

    get historyTabClass() {
        return `tab-item ${this.activeTab === 'history' ? 'active' : ''}`;
    }

    get isWebinarTab() {
        return this.activeTab === 'webinar';
    }

    get hasWebinarHistory() {
        return (this.webinarHistory || []).length > 0;
    }

    get webinarTabClass() {
        return `tab-item ${this.activeTab === 'webinar' ? 'active' : ''}`;
    }

    get eventTabClass() {
        return `tab-item ${this.activeTab === 'event' ? 'active' : ''}`;
    }

    get isEventTab() {
        return this.activeTab === 'event';
    }

    get isDndSpamDisabled() {
        return this.l1Value !== 'Connected';
    }

    get hasEvents() {
        return (this.eventHistory || []).length > 0;
    }

    handleViewMoreLead() {
        if (!this.recordId) return;
        this[NavigationMixin.GenerateUrl]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this.recordId,
                objectApiName: 'Lead',
                actionName: 'view'
            }
        }).then(url => {
            window.open(url, '_blank');
        });
    }

    handleDndChange(e) {
        this.isDnd = e.target.checked;
    }

    handleSpamChange(e) {
        this.isSpam = e.target.checked;
    }

    handleExpectedDateChange(event) {
        this.expectedPaymentDate = event.target.value;
    }

    get formattedCreatedDate() {
        if (!this.identity.createdDate) return '';
        const date = new Date(this.identity.createdDate);
        return new Intl.DateTimeFormat('en-IN', {
            year: 'numeric',
            month: 'short',
            day: '2-digit',
            hour: '2-digit',
            minute: '2-digit'
        }).format(date);
    }

    resolveRecordIdFromPageRef() {
        if (this.recordId) return;
        const state = this.pageRef?.state;
        if (!state) return;
        const recId = state.recordId || state.c__recordId || state.id || state.c__id;
        if (recId && (recId.length === 15 || recId.length === 18)) {
            this.recordId = recId;
            this.loadCallHistory();
        }
    }

    connectedCallback() {
        this.resolveRecordIdFromPageRef();
        this.loadPicklists();
        this.loadStageAndCourse();
        this.loadCallHistory();
        this.subscribeToEvents();
        onError(err => console.warn('EMP API Error:', JSON.stringify(err)));
        setTimeout(() => {
            if (this.autoCall && this.recordId && !this.hasAutoCalled) {
                this.hasAutoCalled = true;
                this.startCall();
            }
        }, 500);
    }

    async loadStageAndCourse() {
        try {
            const data = await getStageLevelValues({ recordId: this.recordId });
            if (data.stage) {
                this.stageOptions = data.stage.map(v => ({ label: v, value: v }));
            }
            if (data.level) {
                this.courseOptions = data.level.map(v => ({ label: v, value: v }));
            }
        } catch (e) {
            console.error('Stage/Course load failed:', e);
        }
    }

    processDispositions(data) {
        if (!data || !Array.isArray(data)) return;

        const fMap = {};
        const cRules = {};
        const stageMap = {};

        data.forEach(item => {
            if (!fMap[item.l1]) fMap[item.l1] = [];
            if (!fMap[item.l1].includes(item.l2)) {
                fMap[item.l1].push(item.l2);
            }

            const key = `${item.l1}:${item.l2}`;
            cRules[key] = item.commentNeeded;
            if (item.tagLevel) {
                stageMap[key] = item.tagLevel;
            }
        });

        this.fullMap = fMap;
        this.mandatoryCommentRules = cRules;
        this.autoStageMap = stageMap;
        this._allL1Options = Object.keys(fMap).map(k => ({ label: k, value: k }));
    }

    handleCourseChange(e) {
        this.courseValue = e.target.value;
    }

    disconnectedCallback() {
        this.stopTimer();
        this.clearFeedbackTimers();
        if (this.subscription) {
            unsubscribe(this.subscription, () => { });
            this.subscription = null;
        }
    }

    async loadPicklists() {
        if (this.dispositions && Array.isArray(this.dispositions)) {
            this.processDispositions(this.dispositions);
            return;
        }
        try {
            // Fallback to fetch dispositions if not passed via props
            const data = await getDispositions();
            if (data && data.length > 0) {
                this.processDispositions(data);
            } else {
                // Legacy fallback just in case
                this.fullMap = await getL1L2Values();
                this._allL1Options = Object.keys(this.fullMap).map(k => ({ label: k, value: k }));
            }
        } catch (e) {
            console.error('Picklist load failed:', e);
        }
    }

    async loadEventHistory() {
        if (!this.recordId) return;
        try {
            const rows = await getLeadEvents({ recordId: this.recordId });
            this.eventHistory = (rows || []).map(r => ({
                id: r.id,
                subject: r.subject,
                attendance: r.attendance || 'NA'
            }));
            this.eventLoaded = true;
        } catch (e) {
            console.error('Event load failed:', e);
        }
    }

    async loadCallHistory() {
        if (!this.recordId) return;
        try {
            const rows = await getCallHistory({ recordId: this.recordId });
            const dateFmt = new Intl.DateTimeFormat('en-US', { month: 'short', day: '2-digit', year: 'numeric' });
            const timeFmt = new Intl.DateTimeFormat('en-US', { hour: '2-digit', minute: '2-digit' });
            this.callHistory = (rows || []).map(r => {
                const dt = r.startTime || r.createdDate;
                const d = dt ? new Date(dt) : null;
                const totalSec = Number(r.durationSeconds || 0);
                const mm = String(Math.floor(totalSec / 60)).padStart(2, '0');
                const ss = String(totalSec % 60).padStart(2, '0');
                return {
                    id: r.id,
                    dateLabel: d ? dateFmt.format(d) : 'NA',
                    timeLabel: d ? timeFmt.format(d) : '',
                    durationLabel: `${mm}:${ss}`,
                    status: r.status || 'NA',
                    l1: r.l1 || '',
                    l2: r.l2 || '',
                    stage: r.stage || ''
                };
            });
        } catch (e) {
            console.error('Call history load failed:', e);
        }
    }

    get hasCallHistory() {
        return (this.callHistory || []).length > 0;
    }

    async loadWebinarHistory() {
        if (!this.identity.canId) return;
        try {
            const rows = await getWebinarMembers({ candidateId: this.identity.canId });
            const dateFmt = new Intl.DateTimeFormat('en-IN', { day: '2-digit', month: 'short', year: 'numeric' });
            this.webinarHistory = (rows || []).map(r => ({
                id: r.id,
                webinar: r.webinarName,
                status: r.attendanceStatus || 'NA',
                createdDate: r.createdDate ? dateFmt.format(new Date(r.createdDate)) : 'NA'
            }));
            this.webinarLoaded = true;
        } catch (e) {
            console.error('Webinar history load failed:', e);
        }
    }

    updateCommentVisibility() {
        const key = `${this.l1Value}:${this.l2Value}`;
        this.isCommentMandatory = this.mandatoryCommentRules[key] === true;
    }

    handleL1Change(e) {
        this.updateL1(e.target.value);
    }

    updateL1(val) {
        this.l1Value = val;
        this.userChangedStage = false;
        this.l2Value = '';
        this.isL2Disabled = !this.l1Value || (this.fullMap && !this.fullMap[this.l1Value]);
        this.isStageDisabled = this.l1Value === 'Not-Connected';
        this.updateCommentVisibility();
    }

    handleL2Change(e) {
        this.l2Value = e.target.value;
        this.updateCommentVisibility();
        if (this.l2Value) {
            this.applyAutoStageLogic();
        }
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

    handleNotifyChange(event) {
        this.notifyMe = event.target.checked;
    }

    handleAutoSetChange(e) {
        this.autoSetFollowUp = e.target.checked;
        if (this.autoSetFollowUp) {
            this.setAutoDate24();
        }
    }

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

    async callApi() {
        this.callButtonDisabled = true;
        this.loading = true;
        this.errorText = null;
        this.callStatus = 'Dialing\u2026';
        this.isLive = false;
        this.showFeedback = false;
        this.showCallPopup = true;
        this.canEndCall = false;
        this.setElapsed(0);
        this.startTimer();
        this.lastCallId = null;
        this.hasActualConnection = false;
        this.clearFeedbackTimers();
        try {
            const response = await allocateLeadNow({ recordId: this.recordId });
            const parsed = typeof response === 'string' ? JSON.parse(response) : response || {};
            this.lastCallId = parsed?.callId || this.lastCallId;
            this.callTitle = parsed?.displayName || 'Calling via Runo';
            this.callStatus = 'In Call\u2026';
            this.isLive = true;
            this.showPopup = true;
            setTimeout(() => (this.showPopup = false), 4200);
            this.clearFeedbackTimers();
            this.noResponseTimer = setTimeout(() => {
                if (this.isLive && this.callStatus !== 'Ended') {
                    this.canEndCall = true;
                    this.callStatus = 'No Response';
                    this.showFeedbackSection();
                    this.callButtonDisabled = true;
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
            this.toast('Failed', this.errorText, 'error');
        } finally {
            this.loading = false;
        }
    }

    handleEndCall() {
        if (!this.canEndCall && !this.isLive) return;
        this.callStatus = 'Ended';
        this.isLive = false;
        this.showCallPopup = false;
        this.stopTimer();
        this.clearFeedbackTimers();
        this.showFeedbackSection();
        this.callButtonDisabled = true;
    }

    get isSaveDisabled() {
        return this.savingFeedback || !this.showFeedback;
    }

    showFeedbackSection() {
        if (!this.l1Value) {
            this.updateL1('Not-Connected');
        }
        this.showFeedback = true;
        this.disableCancel = false;
        if (this.autoSetFollowUp) {
            this.setAutoDate24();
        }
    }

    setAutoDate24() {
        const next = new Date(Date.now() + 24 * 60 * 60 * 1000);
        const yyyy = next.getFullYear();
        const mm = String(next.getMonth() + 1).padStart(2, '0');
        const dd = String(next.getDate()).padStart(2, '0');
        const hh = String(next.getHours()).padStart(2, '0');
        const mi = String(next.getMinutes()).padStart(2, '0');
        this.nextFollowUpDate = `${yyyy}-${mm}-${dd}T${hh}:${mi}`;
    }

    applyAutoStageLogic() {
        if (this.userChangedStage) return;
        const key = `${this.l1Value}:${this.l2Value}`;

        // Use the map built from dispositions if available
        if (this.autoStageMap && this.autoStageMap[key]) {
            this.stageValue = this.autoStageMap[key];
            return;
        }

        // Fallback to existing logic if no dispositions provided
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

    async saveFeedback() {
        if (this.isCommentMandatory && !this.feedback?.trim()) {
            this.toast('Mandatory', 'Feedback comment is required.', 'warning');
            return;
        }
        if (this.l1Value && !this.l2Value) {
            this.toast('Mandatory', 'Sub Status (L2) is required.', 'warning');
            return;
        }
        if (this.l1Value === 'Connected' && !this.stageValue) {
            this.toast('Required', 'Stage is required when call is connected.', 'warning');
            return;
        }
        if (this.l1Value === 'Not-Connected') {
            this.stageValue = null;
        }
        this.savingFeedback = true;
        try {
            const payload = {
                recordId: this.recordId,
                callId: this.lastCallId,
                feedback: this.feedback?.trim(),
                nextFollowUpDate: this.nextFollowUpDate,
                l1: this.l1Value,
                l2: this.l2Value,
                notifyMe: this.notifyMe,
                isDnd: this.isDnd,
                isSpam: this.isSpam,
                expectedPaymentDate: this.expectedPaymentDate
            };
            if (this.stageValue && String(this.stageValue).trim()) {
                payload.stage = this.stageValue;
            }
            await updateCallFeedback({ jsonBody: JSON.stringify(payload) });
            this.toast('Saved', 'Feedback saved successfully.', 'success');

            // 🔥 DISPATCH CUSTOM EVENT
            this.dispatchEvent(new CustomEvent('callcomplete', {
                detail: { recordId: this.recordId, callId: this.lastCallId, feedback: this.feedback, l1: this.l1Value },
                bubbles: true,
                composed: true
            }));

            this.clearFeedbackTimers();
            this.showFeedback = false;
            this.disableCancel = true;
            this.callStatus = 'Idle';
            this.isLive = false;
            this.showCallPopup = false;
            this.setElapsed(0);
            this.feedback = '';
            this.l1Value = '';
            this.l2Value = '';
            this.updateCommentVisibility();
            this.nextFollowUpDate = null;
        } catch (e) {
            let message = 'Failed to save feedback.';
            if (e && e.body) {
                if (e.body.pageErrors && e.body.pageErrors.length) {
                    message = e.body.pageErrors[0].message;
                } else if (e.body.fieldErrors && e.body.fieldErrors.Stage__c && e.body.fieldErrors.Stage__c.length) {
                    message = e.body.fieldErrors.Stage__c[0].message;
                } else if (e.body.message) {
                    message = e.body.message;
                }
            } else if (e && e.message) {
                message = e.message;
            }
            this.toast('Save Failed', message, 'error');
        } finally {
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

    startTimer() {
        if (this.timerId) return;
        const start = Date.now() - this.elapsedMs;
        this.timerId = setInterval(() => { this.setElapsed(Date.now() - start); }, 500);
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

    channelName = '/event/Runo_Call_Completed__e';
    subscription = null;

    subscribeToEvents() {
        if (this.subscription) return;
        subscribe(this.channelName, -1, msg => this.onRunoEvent(msg))
            .then(resp => { this.subscription = resp; })
            .catch(() => { });
    }

    onRunoEvent(msg) {
        const p = (msg && msg.data && msg.data.payload) || {};
        const evtLeadId = p.Lead_Id__c || p.LeadId__c || p.leadId || null;
        const evtCallId = p.Call_Id__c || p.CallId__c || p.callId || null;
        if (evtLeadId && String(evtLeadId) !== String(this.recordId)) return;
        if (evtCallId) this.lastCallId = String(evtCallId);
        const s = Number(p.Duration_Seconds__c || p.Duration__c || p.durationSeconds);
        if (!Number.isNaN(s) && s > 0) {
            const totalSec = Math.floor(s);
            const mm = String(Math.floor(totalSec / 60)).padStart(2, '0');
            const ss = String(totalSec % 60).padStart(2, '0');
            this.elapsedLabel = `${mm}:${ss}`;
            this.hasActualConnection = true;
            this.updateL1('Connected');
        } else {
            this.elapsedLabel = '00:00';
            this.hasActualConnection = false;
            this.updateL1('Not-Connected');
        }
        this.callStatus = 'Ended';
        this.isLive = false;
        this.showCallPopup = false;
        this.stopTimer();
        this.clearFeedbackTimers();
        this.showFeedbackSection();
        this.callButtonDisabled = true;
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}