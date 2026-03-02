import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { subscribe, unsubscribe, onError } from 'lightning/empApi';

import allocateLeadNow from '@salesforce/apex/Webservice_RunoAllocationAPI.allocateLeadNow';
import updateCallFeedback from '@salesforce/apex/Webservice_RunoAllocationAPI.updateCallFeedback';
import getDispositions from '@salesforce/apex/CallDispositionConfigService.getDispositions';
import getStageLevelValues from '@salesforce/apex/Webservice_RunoAllocationAPI.getStageLevelValues';
import getIdentity from '@salesforce/apex/RunoCallIdentityService.getIdentity';
import getWebinarMembers from '@salesforce/apex/Webservice_RunoAllocationAPI.getWebinarMembers';
import getLeadEvents from '@salesforce/apex/Webservice_RunoAllocationAPI.getLeadEvents';
import getCallHistory from '@salesforce/apex/Webservice_RunoAllocationAPI.getCallHistory';

const STATUS = {
    IDLE: 'Idle',
    DIALING: 'Dialing…',
    IN_CALL: 'In Call…',
    NO_RESPONSE: 'No Response',
    ENDED: 'Ended',
    FAILED: 'Failed'
};

export default class WebinarCallModal extends LightningElement {
    @api leadId;
    @api leadName;
    @api leadEmail;
    @api leadPhone;

    @track loading = false;
    @track callStatus = STATUS.IDLE;
    @track callTitle = 'Calling via Runo';
    @track elapsedLabel = '00:00';
    @track activeTab = 'lead';

    @track identity = {
        name: '',
        email: '',
        phone: '',
        city: '',
        source: '',
        stage: '',
        level: '',
        canId: '',
        leadOwner: '',
        createdDate: ''
    };

    @track callHistory = [];
    @track webinarMembers = [];
    @track eventHistory = [];

    // Feedback Related
    @track showFeedback = false;
    @track feedback = '';
    @track nextFollowUpDate = null;
    @track expectedPaymentDate = null;
    @track notifyMe = false;
    @track isDnd = false;
    @track isSpam = false;
    @track autoSetFollowUp = true;
    @track hasActualConnection = false;
    @track showPopup = false;
    @track l1Value = '';
    @track l2Value = '';
    @track stageValue = '';
    @track levelValue = '';
    @track isL2Disabled = true;
    @track isStageDisabled = false;
    @track savingFeedback = false;

    @track _allL1Options = [];
    @track fullMap = {};
    @track mandatoryCommentRules = {};
    @track autoStageMap = {};
    @track userChangedStage = false;

    @track stageOptions = [];
    @track levelOptions = [];

    @track callButtonLabel = 'Call Now';
    @track callButtonDisabled = false;

    // State Variables
    isLive = false;
    elapsedMs = 0;
    timerId = null;
    lastCallId = null;
    canEndCall = false;
    CALL_NO_RESPONSE_MS = 30000;
    noResponseTimer = null;
    subscription = null;

    connectedCallback() {
        this.identity.name = this.leadName;
        this.identity.email = this.leadEmail;
        this.identity.phone = this.leadPhone;

        this.loadIdentity();
        this.loadPicklists();
        this.loadStageLevel();
        this.loadHistory();
        this.handleSubscribe();
    }

    disconnectedCallback() {
        this.stopTimer();
        this.clearTimers();
        if (this.subscription && this.subscription.id) {
            unsubscribe(this.subscription, () => { });
        }
    }

    async loadIdentity() {
        try {
            const data = await getIdentity({ recordId: this.leadId });
            if (data) {
                this.identity = data;
                if (data.stage) this.stageValue = data.stage;
                if (data.level) this.levelValue = data.level;
            }
        } catch (error) {
            console.error('Identity load failed:', error);
        }
    }

    async loadPicklists() {
        try {
            const data = await getDispositions();
            if (data && data.length > 0) {
                this.processDispositions(data);
            }
        } catch (error) {
            console.error('Picklist load failed:', error);
        }
    }

    processDispositions(data) {
        const fMap = {};
        const cRules = {};
        const sMap = {};

        data.forEach(item => {
            if (!fMap[item.l1]) fMap[item.l1] = [];
            if (!fMap[item.l1].includes(item.l2)) fMap[item.l1].push(item.l2);

            const key = `${item.l1}:${item.l2}`;
            cRules[key] = item.commentNeeded;
            if (item.tagLevel) sMap[key] = item.tagLevel;
        });

        this.fullMap = fMap;
        this.mandatoryCommentRules = cRules;
        this.autoStageMap = sMap;
        this._allL1Options = Object.keys(fMap).map(k => ({ label: k, value: k }));
    }

    async loadStageLevel() {
        try {
            const mapData = await getStageLevelValues();
            this.stageOptions = (mapData.stage || []).map(v => ({ label: v, value: v }));
            this.levelOptions = (mapData.level || []).map(v => ({ label: v, value: v }));
        } catch (error) {
            console.error('Stage/Level load failed:', error);
        }
    }

    async loadHistory() {
        try {
            const [calls, webinars, events] = await Promise.all([
                getCallHistory({ candidateId: this.leadId }),
                getWebinarMembers({ candidateId: this.leadId }),
                getLeadEvents({ recordId: this.leadId })
            ]);
            this.callHistory = this.formatCallHistory(calls);
            this.webinarMembers = this.formatWebinarHistory(webinars);
            this.eventHistory = events;
        } catch (error) {
            console.error('History load failed:', error);
        }
    }

    formatCallHistory(data) {
        return (data || []).map(cl => {
            const dt = new Date(cl.createdDate);
            return {
                ...cl,
                dateLabel: dt.toLocaleDateString(),
                timeLabel: dt.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }),
                durationLabel: `${Math.floor(cl.durationInSec / 60)}:${String(cl.durationInSec % 60).padStart(2, '0')}`
            };
        });
    }

    formatWebinarHistory(data) {
        return (data || []).map(wm => {
            const dt = new Date(wm.createdDate);
            return {
                id: wm.id,
                webinar: wm.webinar,
                date: dt.toLocaleDateString(),
                attendance: wm.attendanceStatus
            };
        });
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

    get isSaveDisabled() {
        return this.savingFeedback || !this.showFeedback;
    }

    get isCommentMandatory() {
        const key = `${this.l1Value}:${this.l2Value}`;
        return this.mandatoryCommentRules[key] === true;
    }

    get formattedCreatedDate() {
        if (!this.identity.createdDate) return 'N/A';
        const d = new Date(this.identity.createdDate);
        return d.toLocaleDateString();
    }

    get isLeadTab() { return this.activeTab === 'lead'; }
    get isHistoryTab() { return this.activeTab === 'history'; }
    get isWebinarTab() { return this.activeTab === 'webinar'; }
    get isEventTab() { return this.activeTab === 'event'; }

    get leadTabClass() { return `tab-item ${this.activeTab === 'lead' ? 'active' : ''}`; }
    get historyTabClass() { return `tab-item ${this.activeTab === 'history' ? 'active' : ''}`; }
    get webinarTabClass() { return `tab-item ${this.activeTab === 'webinar' ? 'active' : ''}`; }
    get eventTabClass() { return `tab-item ${this.activeTab === 'event' ? 'active' : ''}`; }

    get hasCallHistory() { return this.callHistory && this.callHistory.length > 0; }
    get hasEvents() { return this.eventHistory && this.eventHistory.length > 0; }

    get isDndSpamDisabled() { return this.l1Value !== 'Connected'; }

    handleTabClick(event) {
        this.activeTab = event.currentTarget.dataset.tab;
    }

    handleL1Change(event) {
        this.updateL1(event.target.value);
    }

    updateL1(val) {
        this.l1Value = val;
        this.l2Value = '';
        this.isL2Disabled = !this.l1Value || (this.fullMap && !this.fullMap[this.l1Value]);
        this.isStageDisabled = this.l1Value === 'Not-Connected';
        this.userChangedStage = false;
    }

    handleL2Change(event) {
        this.l2Value = event.target.value;
        this.applyAutoStageLogic();
    }

    applyAutoStageLogic() {
        if (this.userChangedStage) return;
        const key = `${this.l1Value}:${this.l2Value}`;
        if (this.autoStageMap && this.autoStageMap[key]) {
            this.stageValue = this.autoStageMap[key];
        }
    }

    handleStageChange(event) {
        this.stageValue = event.target.value;
        this.userChangedStage = true;
    }

    handleExpectedDateChange(event) { this.expectedPaymentDate = event.target.value; }
    handleNotifyChange(event) { this.notifyMe = event.target.checked; }
    handleDndChange(event) { this.isDnd = event.target.checked; }
    handleSpamChange(event) { this.isSpam = event.target.checked; }
    handleAutoSetChange(event) {
        this.autoSetFollowUp = event.target.checked;
        if (this.autoSetFollowUp) this.setAutoDate24();
    }
    handleFeedbackChange(event) { this.feedback = event.target.value; }

    setAutoDate24() {
        const next = new Date(Date.now() + 24 * 60 * 60 * 1000);
        const yyyy = next.getFullYear();
        const mm = String(next.getMonth() + 1).padStart(2, '0');
        const dd = String(next.getDate()).padStart(2, '0');
        const hh = String(next.getHours()).padStart(2, '0');
        const mi = String(next.getMinutes()).padStart(2, '0');
        this.nextFollowUpDate = `${yyyy}-${mm}-${dd}T${hh}:${mi}`;
    }

    handleCall() {
        if (this.callButtonDisabled) return;
        this.callButtonDisabled = true;
        this.loading = true;
        this.errorText = null;
        this.callStatus = STATUS.DIALING;
        this.elapsedMs = 0;
        this.elapsedLabel = '00:00';
        this.showFeedback = false;
        this.canEndCall = false;
        this.lastCallId = null;
        this.hasActualConnection = false;

        allocateLeadNow({ recordId: this.leadId })
            .then(res => {
                const parsed = typeof res === 'string' ? JSON.parse(res) : res || {};
                this.lastCallId = parsed.callId;
                this.callTitle = parsed.displayName || 'Calling via Runo';
                this.callStatus = STATUS.IN_CALL;
                this.isLive = true;
                this.showPopup = true;
                setTimeout(() => { this.showPopup = false; }, 4200);

                this.startTimer();
                this.noResponseTimer = setTimeout(() => {
                    if (this.isLive && this.callStatus !== STATUS.ENDED) {
                        this.canEndCall = true;
                        this.callStatus = STATUS.NO_RESPONSE;
                        this.showFeedbackSection();
                        this.callButtonDisabled = true;
                    }
                }, this.CALL_NO_RESPONSE_MS);
            })
            .catch(error => {
                this.callStatus = STATUS.FAILED;
                this.callButtonDisabled = false;
                this.showToast('Error', error?.body?.message || 'Call failed', 'error');
            })
            .finally(() => {
                this.loading = false;
            });
    }

    handleEndCall() {
        this.callStatus = STATUS.ENDED;
        this.isLive = false;
        this.stopTimer();
        this.clearTimers();
        this.showFeedbackSection();
        this.callButtonDisabled = true;
    }

    showFeedbackSection() {
        if (!this.l1Value) {
            this.updateL1('Not-Connected');
        }
        this.showFeedback = true;
        if (this.autoSetFollowUp) {
            this.setAutoDate24();
        }
    }

    async handleSaveFeedback() {
        if (this.isCommentMandatory && !this.feedback?.trim()) {
            this.showToast('Warning', 'Comment is mandatory', 'warning');
            return;
        }

        if (this.l1Value === 'Connected' && !this.stageValue) {
            this.showToast('Warning', 'Stage is required', 'warning');
            return;
        }

        this.savingFeedback = true;
        try {
            const payload = {
                recordId: this.leadId,
                callId: this.lastCallId,
                feedback: this.feedback?.trim(),
                nextFollowUpDate: this.nextFollowUpDate,
                l1: this.l1Value,
                l2: this.l2Value,
                stage: this.l1Value === 'Connected' ? this.stageValue : null,
                level: this.levelValue,
                notifyMe: this.notifyMe,
                isDnd: this.isDnd,
                isSpam: this.isSpam,
                expectedPaymentDate: this.expectedPaymentDate
            };
            await updateCallFeedback({ jsonBody: JSON.stringify(payload) });
            this.showToast('Success', 'Feedback saved', 'success');
            this.dispatchEvent(new CustomEvent('feedbacksaved'));
            this.handleClose();
        } catch (error) {
            this.showToast('Error', error?.body?.message || 'Save failed', 'error');
        } finally {
            this.savingFeedback = false;
        }
    }

    startTimer() {
        const start = Date.now();
        this.timerId = setInterval(() => {
            this.elapsedMs = Date.now() - start;
            const totalSec = Math.floor(this.elapsedMs / 1000);
            const mm = String(Math.floor(totalSec / 60)).padStart(2, '0');
            const ss = String(totalSec % 60).padStart(2, '0');
            this.elapsedLabel = `${mm}:${ss}`;
        }, 1000);
    }

    stopTimer() {
        if (this.timerId) clearInterval(this.timerId);
        this.timerId = null;
    }

    clearTimers() {
        if (this.noResponseTimer) clearTimeout(this.noResponseTimer);
        this.noResponseTimer = null;
    }

    handleSubscribe() {
        if (this.subscription) return;
        const messageCallback = (msg) => {
            const p = (msg && msg.data && msg.data.payload) || {};
            // Match by Call ID if available
            const evtCallId = p.Call_Id__c || p.CallId__c || p.callId || null;
            if (evtCallId && String(evtCallId) !== String(this.lastCallId)) return;

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

            this.callStatus = STATUS.ENDED;
            this.isLive = false;
            this.showPopup = false;
            this.stopTimer();
            this.clearTimers();
            this.showFeedbackSection();
            this.callButtonDisabled = true;
        };

        subscribe('/event/Runo_Call_Completed__e', -1, messageCallback)
            .then(sub => {
                this.subscription = sub;
            })
            .catch(error => {
                console.error('Subscription error:', error);
            });
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}