import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { subscribe, unsubscribe, onError } from 'lightning/empApi';

import allocateLeadNow from '@salesforce/apex/Webservice_RunoAllocationAPI.allocateLeadNow';
import updateCallFeedback from '@salesforce/apex/Webservice_RunoAllocationAPI.updateCallFeedback';
import getL1L2Values from '@salesforce/apex/Webservice_RunoAllocationAPI.getL1L2Values';
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

    // UI State
    @track loading = false;
    @track showCallPopup = false;
    @track showFeedback = false;
    @track savingFeedback = false;
    @track errorText = null;

    // L1/L2 Picklists
    @track l1Value = '';
    @track l2Value = '';
    @track l1Options = [];
    @track l2Options = [];
    @track fullMap = {};
    @track isL2Disabled = true;



    @track callHistory = [];
@track webinarMembers = [];
@track eventHistory = [];

@track historyLoaded = false;
@track webinarLoaded = false;
@track eventLoaded = false;


    // Stage/Level Picklists
    @track stageValue = '';
    @track levelValue = '';
    @track stageOptions = [];
    @track levelOptions = [];

    // Identity
    @track identity = {
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

    @track activeTab = 'lead';

    // Call State
    @track isLive = false;
    @track callStatus = STATUS.IDLE;
    @track callTitle = 'Calling via Runo';
    @track elapsedMs = 0;
    @track elapsedLabel = '00:00';
    @track lastCallId = null;

    // Timers
    timerId = null;
    noResponseTimer = null;
    canEndCall = false;
    CALL_NO_RESPONSE_MS = 30000;

    // Feedback
    @track feedback = '';
    @track nextFollowUpDate = null;

    // Comment Mandatory Rules
    @track isCommentMandatory = false;
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

    // Platform Event
    channelName = '/event/Runo_Call_Completed__e';
    subscription = null;

    // -------------------------
    // LIFECYCLE
    // -------------------------
    connectedCallback() {
        this.loadIdentity();
        this.loadPicklists();
        this.loadStageLevel();
        this.subscribeToEvents();
        onError(err => console.warn('EMP API Error:', JSON.stringify(err)));
    }
    handleCall() {
        this.showCallPopup = true;
    }


    disconnectedCallback() {
        this.stopTimer();
        this.clearTimers();
        if (this.subscription) {
            unsubscribe(this.subscription, () => { });
            this.subscription = null;
        }
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
 
    async loadIdentity() {
        try {
            const data = await getIdentity({ recordId: this.leadId });
            if (data) {
                this.identity = data;
                if (data.stage) this.stageValue = data.stage;
                if (data.level) this.levelValue = data.level;
            }
        } catch (error) {
            console.error('Failed to load identity:', error);
        }
    }

    async loadPicklists() {
        try {
            this.fullMap = await getL1L2Values();
            this.l1Options = Object.keys(this.fullMap).map(k => ({
                label: k,
                value: k
            }));
        } catch (error) {
            console.error('Picklist load failed:', error);
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
        } catch (error) {
            console.error('Stage/Level load failed:', error);
        }
    }

    updateCommentVisibility() {
        const key = `${this.l1Value}:${this.l2Value}`;
        this.isCommentMandatory = this.mandatoryCommentRules[key] === true;
    }

    handleL1Change(event) {
        this.l1Value = event.target.value;
        this.l2Options = (this.fullMap[this.l1Value] || []).map(v => ({
            label: v,
            value: v
        }));
        this.isL2Disabled = this.l2Options.length === 0;
        this.l2Value = '';
        this.updateCommentVisibility();
    }

    handleL2Change(event) {
        this.l2Value = event.target.value;
        this.updateCommentVisibility();
    }

    handleStageChange(event) {
        this.stageValue = event.target.value;
    }

    handleLevelChange(event) {
        this.levelValue = event.target.value;
    }

    handleFeedbackChange(event) {
        this.feedback = event.target.value;
    }

    handleNextFollowUpDateChange(event) {
        this.nextFollowUpDate = event.target.value;
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    
 get isLeadTab() {
    return this.activeTab === 'lead';
}
get isHistoryTab() {
    return this.activeTab === 'history';
}
get isWebinarTab() {
    return this.activeTab === 'webinar';
}
get isEventTab() {
    return this.activeTab === 'event';
}

get leadTabClass() {
    return `tab ${this.activeTab === 'lead' ? 'active' : ''}`;
}

get historyTabClass() {
    return `tab ${this.activeTab === 'history' ? 'active' : ''}`;
}

get webinarTabClass() {
    return `tab ${this.activeTab === 'webinar' ? 'active' : ''}`;
}

get eventTabClass() {
    return `tab ${this.activeTab === 'event' ? 'active' : ''}`;
}


get hasEvents() {
    return this.eventHistory.length > 0;
}

get hasCallHistory() {
    return this.callHistory.length > 0;
}



async handleTabClick(event) {
    const tab = event.currentTarget.dataset.tab;
    this.activeTab = tab;

    if (tab === 'history' && !this.historyLoaded) {
        await this.loadCallHistory();
    }

    if (tab === 'webinar' && !this.webinarLoaded) {
        await this.loadWebinars();
    }

    if (tab === 'event' && !this.eventLoaded) {
        await this.loadEventHistory();
    }
}

async loadCallHistory() {
    try {
        const rows = await getCallHistory({ recordId: this.leadId });

        this.callHistory = (rows || []).map(r => {
            const dt = new Date(r.startTime || r.createdDate);

            return {
                id: r.id,
                dateLabel: dt.toLocaleDateString('en-IN'),
                timeLabel: dt.toLocaleTimeString('en-IN', { hour: '2-digit', minute: '2-digit' }),
                durationLabel: `${Math.floor((r.durationSeconds || 0) / 60)}m ${(r.durationSeconds || 0) % 60}s`,
                status: r.status,
                l1: r.l1,
                l2: r.l2,
                stage: r.stage
            };
        });

        this.historyLoaded = true;
    } catch (e) {
        console.error('History load failed', e);
    }
}



async loadWebinars() {
    try {
        const rows = await getWebinarMembers({ recordId: this.leadId });

        this.webinarMembers = (rows || []).map(r => ({
            id: r.id,
            webinar: r.webinarName,
            attendance: r.attendanceStatus,
            date: r.createdDate
        }));

        this.webinarLoaded = true;
    } catch (e) {
        console.error('Webinar load failed', e);
    }
}


async loadEventHistory() {
    try {
        const rows = await getLeadEvents({ recordId: this.leadId });

        this.eventHistory = (rows || []).map(r => ({
            id: r.id,
            subject: r.subject,
            attendance: r.attendance || 'NA'
        }));

        this.eventLoaded = true;
    } catch (e) {
        console.error('Event load failed', e);
    }
}










handleViewMoreLead() {
    window.open('/' + this.leadId, '_blank');
}


    async handleCall() {
        this.loading = true;
        this.errorText = null;
        this.callStatus = STATUS.DIALING;
        this.isLive = false;
        this.showFeedback = false;
        this.showCallPopup = true;
        this.canEndCall = false;

        this.setElapsed(0);
        this.startTimer();
        this.lastCallId = null;
        this.clearTimers();

        try {
            const response = await allocateLeadNow({ recordId: this.leadId });
            const parsed = typeof response === 'string' ? JSON.parse(response) : response || {};

            this.lastCallId = parsed?.callId || this.lastCallId;
            this.callTitle = parsed?.displayName || 'Calling via Runo';
            this.callStatus = STATUS.IN_CALL;
            this.isLive = true;

            this.showToast('Success', 'Call initiated successfully', 'success');

            // Start no-response timer
            this.noResponseTimer = setTimeout(() => {
                if (this.isLive && this.callStatus !== STATUS.ENDED) {
                    this.canEndCall = true;
                    this.callStatus = STATUS.NO_RESPONSE;
                }
            }, this.CALL_NO_RESPONSE_MS);

        } catch (error) {
            this.errorText = error?.body?.message || error?.message || 'Failed to dial';
            this.callStatus = STATUS.FAILED;
            this.isLive = false;
            this.showCallPopup = false;
            this.stopTimer();
            this.showFeedback = true;

            this.showToast('Error', this.errorText, 'error');
        } finally {
            this.loading = false;
        }
    }

    handleEndCall() {
        if (!this.canEndCall && !this.isLive) return;

        this.callStatus = STATUS.ENDED;
        this.isLive = false;
        this.showCallPopup = false;
        this.stopTimer();
        this.clearTimers();
        this.showFeedbackSection();
    }

    // -------------------------
    // FEEDBACK
    // -------------------------
    showFeedbackSection() {
        this.showFeedback = true;

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

    async handleSaveFeedback() {
        if (this.isCommentMandatory && !this.feedback?.trim()) {
            this.showToast('Required', 'Feedback comment is required.', 'warning');
            return;
        }

        if (!this.stageValue) {
            this.showToast('Required', 'Stage is required.', 'warning');
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
                stage: this.stageValue,
                level: this.levelValue,
                notifyMe: false
            };

            await updateCallFeedback({
                jsonBody: JSON.stringify(payload)
            });

            this.showToast('Success', 'Feedback saved successfully.', 'success');

            // Notify parent to refresh data
            this.dispatchEvent(new CustomEvent('feedbacksaved'));

            // Close modal
            this.handleClose();

        } catch (error) {
            this.showToast('Error', error?.body?.message || 'Failed to save feedback.', 'error');
        } finally {
            this.savingFeedback = false;
        }
    }

 
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

    clearTimers() {
        if (this.noResponseTimer) {
            clearTimeout(this.noResponseTimer);
            this.noResponseTimer = null;
        }
        this.canEndCall = false;
    }

    // -------------------------
    // PLATFORM EVENT
    // -------------------------
    subscribeToEvents() {
        if (this.subscription) return;

        subscribe(this.channelName, -1, msg => this.onRunoEvent(msg))
            .then(resp => {
                this.subscription = resp;
            })
            .catch(error => {
                console.error('Failed to subscribe:', error);
            });
    }

    onRunoEvent(msg) {
        const p = (msg && msg.data && msg.data.payload) || {};
        const evtLeadId = p.Lead_Id__c || p.LeadId__c || p.leadId || null;
        const evtCallId = p.Call_Id__c || p.CallId__c || p.callId || null;

        if (evtLeadId && String(evtLeadId) !== String(this.leadId)) {
            return;
        }

        if (evtCallId) {
            this.lastCallId = String(evtCallId);
        }

        const s = Number(p.Duration_Seconds__c || p.Duration__c || p.durationSeconds);
        if (!Number.isNaN(s) && s > 0) {
            const totalSec = Math.floor(s);
            const mm = String(Math.floor(totalSec / 60)).padStart(2, '0');
            const ss = String(totalSec % 60).padStart(2, '0');
            this.elapsedLabel = `${mm}:${ss}`;
        } else {
            this.elapsedLabel = '00:00';
        }

        this.callStatus = STATUS.ENDED;
        this.isLive = false;
        this.showCallPopup = false;
        this.stopTimer();
        this.clearTimers();
        this.showFeedbackSection();

        console.log('RUNO EVENT => CALL ENDED');
    }

    // -------------------------
    // UTILITIES
    // -------------------------
    get isSaveDisabled() {
        return this.savingFeedback || !this.showFeedback;
    }

    get showCallButton() {
        return !this.isLive && this.callStatus !== STATUS.IN_CALL;
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}