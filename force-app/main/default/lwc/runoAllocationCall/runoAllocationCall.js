import { api, LightningElement, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import allocateLeadNow from '@salesforce/apex/Webservice_RunoAllocationAPI.allocateLeadNow';
import updateCallFeedback from '@salesforce/apex/Webservice_RunoAllocationAPI.updateCallFeedback';
import getL1L2Values from '@salesforce/apex/Webservice_RunoAllocationAPI.getL1L2Values';
import getCallHistory from '@salesforce/apex/Webservice_RunoAllocationAPI.getCallHistory';
import getIdentity from '@salesforce/apex/RunoCallIdentityService.getIdentity';
import getStageLevelValues from '@salesforce/apex/Webservice_RunoAllocationAPI.getStageLevelValues';
import { CurrentPageReference } from 'lightning/navigation';
import { NavigationMixin } from 'lightning/navigation';
import { CloseActionScreenEvent } from 'lightning/actions';
import { subscribe, unsubscribe, onError } from 'lightning/empApi';
import { getRecord } from 'lightning/uiRecordApi';
import { getObjectInfo, getPicklistValuesByRecordType } from 'lightning/uiObjectInfoApi';
import LEAD_OBJECT from '@salesforce/schema/Lead__c';
import LEAD_RECORDTYPE_FIELD from '@salesforce/schema/Lead__c.RecordTypeId';
import getWebinarMembers from '@salesforce/apex/Webservice_RunoAllocationAPI.getWebinarMembers';
import getLeadEvents from '@salesforce/apex/Webservice_RunoAllocationAPI.getLeadEvents';




export default class RunoAllocationCall extends NavigationMixin(LightningElement) {

    @api recordId;

    // UI / state
    loading = false;
    disableCancel = false;

    callButtonLabel = 'Call Runo';
    callButtonDisabled = false;

    // Call popup overlay (Calling Runo...)
    showCallPopup = false;
    isStageDisabled = false;

    activeTab = 'lead';

    // L1/L2
    l1Value = '';
    l2Value = '';
    l1Options = [];
    l2Options = [];
    fullMap = {};
    isL2Disabled = true;

    // 🔥 NEW: auto-set next follow up date flag (like good LWC)
    autoSetFollowUp = true;
    userChangedStage = false;

    // Stage / Course
    stageValue = '';
    levelValue = '';
    stageOptions = [];
    levelOptions = [];
    leadRecordTypeId = null;

    // auto call start from lead url 
    autoCall = false;
    hasAutoCalled = false;


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
        level: '',
        canId: '',
        createdDate: '',
    mhpTag: '',
    leadOwner: ''
    };

    callHistory = [];

    eventHistory = [];
eventLoaded = false;
courseValue = '';
courseOptions = [];



    // call state
    isLive = false;
    callStatus = 'Idle';
    callTitle = 'Calling via Runo';

    elapsedMs = 0;
    elapsedLabel = '00:00';
    timerId = null;
    webinarHistory = [];
webinarLoaded = false;


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
            if (data.level) {
    this.courseValue = data.level; 
}

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

//   @wire(getPicklistValuesByRecordType, {
//     objectApiName: LEAD_OBJECT,
//     recordTypeId: '$recordTypeId'
// })
// wiredPicklists({ data, error }) {
//     if (data && data.picklistFieldValues) {

//         // Stage
//         if (data.picklistFieldValues.Stage__c) {
//             this.stageOptions = data.picklistFieldValues.Stage__c.values.map(v => ({
//                 label: v.label,
//                 value: v.value
//             }));
//         }

//         // Course (GLOBAL PICKLIST)
//         if (data.picklistFieldValues.Course__c) {
//             this.courseOptions = data.picklistFieldValues.Course__c.values.map(v => ({
//                 label: v.label,
//                 value: v.value
//             }));
//         }
//     } 
//     else if (error) {
//         console.error('Picklist load failed:', error);
//     }
// }

    // -------------- PAGE REFERENCE (URL SAFE) --------------

    @wire(CurrentPageReference)
    wiredPageRef(pageRef) {
        this.pageRef = pageRef;

        const state = pageRef?.state;
        if (!state) return;

        // resolve recordId (already your logic)
        this.resolveRecordIdFromPageRef();

        // ✅ AUTO CALL FLAG
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



    // -------------- URL RECORD ID (SAFE FALLBACK) --------------
    resolveRecordIdFromPageRef() {
        if (this.recordId) {
            return; // already provided (Quick Action / Record Page)
        }

        const state = this.pageRef?.state;
        if (!state) return;

        const recId =
        state.recordId ||
        state.c__recordId ||
        state.id ||
        state.c__id;

        if (recId && (recId.length === 15 || recId.length === 18)) {
            this.recordId = recId;
            console.log('RecordId resolved from pageRef:', this.recordId);
          
            this.loadCallHistory();
        }
    }

// async loadCourses() {
//     try {
//         const rows = await getCourses({ recordId: this.recordId });

//         this.courseOptions = (rows || []).map(c => ({
//             label: c.Name,
//             value: c.Id   
//         }));

//     } catch (e) {
//         console.error('Course load failed', e);
//     }
// }








    // --------------- LIFECYCLE -------------

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
            this.stageOptions = data.stage.map(v => ({
                label: v,
                value: v
            }));
        }

        if (data.level) {
            this.courseOptions = data.level.map(v => ({
                label: v,
                value: v
            }));
        }

    } catch (e) {
        console.error('Stage/Course load failed:', e);
    }
}




handleCourseChange(e) {
    this.courseValue = e.target.value;
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

    // async loadStageLevel() {
    //     try {
    //         const mapData = await getStageLevelValues({ recordId: this.recordId });
    //         this.levelOptions = (mapData.level || []).map(v => ({
    //             label: v,
    //             value: v
    //         }));
    //     } catch (e) {
    //         console.error('Stage/Level load failed:', e);
    //     }
    // }

async loadEventHistory() {
    if (!this.recordId) return;

    try {
        const rows = await getLeadEvents({ recordId: this.recordId });

        console.log('Event rows => ', rows);

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
    if (!this.recordId) return;

    try {
        const rows = await getWebinarMembers({ recordId: this.recordId });

        const dateFmt = new Intl.DateTimeFormat('en-US', {
            month: 'short',
            day: '2-digit',
            year: 'numeric'
        });

        this.webinarHistory = (rows || []).map(r => {
            return {
                id: r.id,
                name: r.name,
                webinar: r.webinarName,
                status: r.attendanceStatus || 'NA',
                createdDate: r.createdDate
                    ? dateFmt.format(new Date(r.createdDate))
                    : 'NA'
            };
        });

        this.webinarLoaded = true;

        console.log('Webinar rows => ', rows);

    } catch (e) {
        console.error('Webinar load failed:', e);
    }
}







  

    updateCommentVisibility() {
        const key = `${this.l1Value}:${this.l2Value}`;
        this.isCommentMandatory = this.mandatoryCommentRules[key] === true;
    }

    handleL1Change(e) {
        this.l1Value = e.target.value;
        this.userChangedStage = false;
        this.l2Options = (this.fullMap[this.l1Value] || []).map(v => ({
            label: v,
            value: v
        }));
        this.isL2Disabled = this.l2Options.length === 0;
        this.l2Value = '';


        if (this.l1Value === 'Not-Connected') {
            this.isStageDisabled = true;
        } else {
            this.isStageDisabled = false;
        }

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




    async loadCallHistory() {
    if (!this.recordId) return;

    try {
        const rows = await getCallHistory({ recordId: this.recordId });

        const dateFmt = new Intl.DateTimeFormat('en-US', {
            month: 'short',
            day: '2-digit',
            year: 'numeric'
        });

        const timeFmt = new Intl.DateTimeFormat('en-US', {
            hour: '2-digit',
            minute: '2-digit'
        });

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

        // ✅ Automatically show feedback after 30s
        this.showFeedbackSection();
        this.callButtonDisabled = true; // optional, disable call button
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
        this.callButtonDisabled = true;
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
        const next = new Date(Date.now() + 24 * 60 * 60 * 1000);

        const yyyy = next.getFullYear();
        const mm = String(next.getMonth() + 1).padStart(2, '0');
        const dd = String(next.getDate()).padStart(2, '0');
        const hh = String(next.getHours()).padStart(2, '0');
        const mi = String(next.getMinutes()).padStart(2, '0');

        this.nextFollowUpDate = `${yyyy}-${mm}-${dd}T${hh}:${mi}`;
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

        if (this.l1Value === 'Connected' && !this.stageValue) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Required',
                    message: 'Stage is required when call is connected.',
                    variant: 'warning'
                })
            );
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
               level: this.courseValue,

                notifyMe: false
            };
            if (this.stageValue && String(this.stageValue).trim()) {
                payload.stage = this.stageValue;
            }

            await updateCallFeedback({
                jsonBody: JSON.stringify(payload)
            });

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Saved',
                    message: 'Feedback saved successfully.',
                    variant: 'success'
                })
            );

            this.clearFeedbackTimers();
            payload.courseId = this.courseValue;


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
            sessionStorage.setItem('RUNO_REFRESH_ON_BACK', 'true');

          this.navigateAfterSave();

                // this.navigateAfterSave();

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

navigateAfterSave() {
    const state = this.pageRef?.state || {};

    const recordIdFromUrl =
        state.c__recordId ||
        state.recordId ||
        state.id ||
        state.c__id;

    // CASE 1: Opened from URL / Nav / Utility
    if (recordIdFromUrl) {

        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'Lead__c',
                actionName: 'list'
            },
            state: {
                filterName: 'Recent'
            }
        });

        // force refresh
        setTimeout(() => {
            window.location.reload();
        }, 500);
    }

    // CASE 2: Opened as Quick Action
    else {
        this.dispatchEvent(new CloseActionScreenEvent());
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

        this.callButtonDisabled = true;

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