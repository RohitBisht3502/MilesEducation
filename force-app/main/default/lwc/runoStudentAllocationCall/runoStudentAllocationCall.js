import { api, LightningElement, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import allocateLeadNow from '@salesforce/apex/Webservice_RunoAllocationAPI.allocateLeadNow';
import updateCallFeedback from '@salesforce/apex/Webservice_RunoAllocationAPI.updateCallFeedback';
import getCallHistory from '@salesforce/apex/Webservice_RunoAllocationAPI.getCallHistory';
import getIdentity from '@salesforce/apex/RunoCallIdentityService.getIdentity';
import getStageLevelValues from '@salesforce/apex/Webservice_RunoAllocationAPI.getStageLevelValues';
import getRelatedLeads from '@salesforce/apex/RunoCallIdentityService.getRelatedLeads';
import createRelatedLead from '@salesforce/apex/RunoCallIdentityService.createRelatedLead';
import updateRelatedLeadStages from '@salesforce/apex/RunoCallIdentityService.updateRelatedLeadStages';
import { CurrentPageReference } from 'lightning/navigation';
import { NavigationMixin } from 'lightning/navigation';
import { CloseActionScreenEvent } from 'lightning/actions';
import { subscribe, unsubscribe, onError } from 'lightning/empApi';
import { getRecord } from 'lightning/uiRecordApi';
import { getObjectInfo, getPicklistValues } from 'lightning/uiObjectInfoApi';
import LEAD_OBJECT from '@salesforce/schema/Lead__c';
import LEAD_RECORDTYPE_FIELD from '@salesforce/schema/Lead__c.RecordTypeId';
import STAGE_FIELD from '@salesforce/schema/Lead__c.Stage__c';
import getWebinarMembers from '@salesforce/apex/Webservice_RunoAllocationAPI.getWebinarMembers';
import getLeadEvents from '@salesforce/apex/Webservice_RunoAllocationAPI.getLeadEvents';
import getDispositions from '@salesforce/apex/CallDispositionConfigService.getDispositions';

export default class RunoStudentAllocationCall extends NavigationMixin(LightningElement) {
    @api recordId;

    candidateId;
    studentId;
    isFeedbackDisabled = true;

    loading = false;
    disableCancel = false;

    callButtonLabel = 'Call Runo';
    callButtonDisabled = false;

    relatedLeads = [];
    relatedLeadsLoaded = false;
    relatedLeadEdits = {};
    newLeadCourse = '';
    newLeadEmail = '';
    isCreatingRelatedLead = false;

    showCallPopup = false;
    isStageDisabled = false;

    activeTab = 'lead';
    expectedPaymentDate;
    notifyMe = false;
    isApiResponseReceived = false;

    l1Value = '';
    l2Value = '';
    l1Options = [];
    l2Options = [];
    isL2Disabled = true;
    l1L2Map = {};

    autoSetFollowUp = true;
    userChangedStage = false;

    stageValue = '';
    levelValue = '';
    stageOptions = [];
    levelOptions = [];
    leadRecordTypeId = null;
    recordTypeStageMap = {};
    activeRelatedRecordTypeId = null;
    pendingRelatedRecordTypeIds = [];

    autoCall = false;
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
  showCallButton = true;
showFeedback = false;   
    savingFeedback = false;
    feedback = '';
    nextFollowUpDate = null;
    nextFollowUpTime = null;

    lastCallId = null;

    canEndCall = false;
    CALL_NO_RESPONSE_MS = 30000;
    noResponseTimer = null;

    showCommentBox = true;
    isCommentMandatory = false;
    dispositionConfigMap = {};

    channelName = '/event/Runo_Call_Completed__e';
    subscription = null;

    @wire(getIdentity, { recordId: '$recordId' })
    wiredIdentity({ data, error }) {
        if (data) {
            this.identity = data;

            if (data.stage) {
                this.stageValue = data.stage;
            }

            if (data.level) {
                this.courseValue = data.level;
            }

            if (!this.candidateId && data.candidateId) {
                this.candidateId = data.candidateId;
            }

            if (!this.studentId && data.studentId) {
                this.studentId = data.studentId;
            }
        } else if (error) {
            this.errorText = error?.body?.message || 'Failed to load identity';
        }
    }

    @wire(getObjectInfo, { objectApiName: LEAD_OBJECT })
    objectInfo;

    @wire(getRecord, { recordId: '$recordId', fields: [LEAD_RECORDTYPE_FIELD] })
    wiredLeadRecordType({ data }) {
        if (data) {
            this.leadRecordTypeId = data.fields.RecordTypeId?.value;
        }
    }

    @wire(getPicklistValues, {
        recordTypeId: '$activeRelatedRecordTypeId',
        fieldApiName: STAGE_FIELD
    })
    wiredRelatedStagePicklist({ data, error }) {
        if (data && this.activeRelatedRecordTypeId) {
            const options = (data.values || []).map(v => ({
                label: v.label,
                value: v.value
            }));

            this.recordTypeStageMap = {
                ...this.recordTypeStageMap,
                [this.activeRelatedRecordTypeId]: options
            };

            this.relatedLeads = (this.relatedLeads || []).map(row =>
                row.recordTypeId === this.activeRelatedRecordTypeId
                    ? { ...row, stageOptions: options }
                    : row
            );

            this.loadNextRelatedStageOptions();
        } else if (error && this.activeRelatedRecordTypeId) {
            console.error('Related stage picklist load failed:', error);
            this.loadNextRelatedStageOptions();
        }
    }

    @wire(CurrentPageReference)
    wiredPageRef(pageRef) {
        this.pageRef = pageRef;

        const state = pageRef?.state;
        if (!state) {
            return;
        }

        this.resolveRecordIdFromPageRef();

        if (state.c__autoCall === 'true') {
            this.autoCall = true;
        }
    }

    get recordTypeId() {
        return this.leadRecordTypeId || this.objectInfo?.data?.defaultRecordTypeId;
    }

    // get showFeedbackInLeadTab() {
    //     return this.isLeadTab && this.showFeedback;
    // }

    get availableCourseOptions() {
        const existing = new Set(
            (this.relatedLeads || [])
                .map(r => (r.course || '').trim().toLowerCase())
                .filter(v => v.length > 0)
        );

        return (this.levelOptions || []).filter(opt => {
            const val = (opt.value || '').trim().toLowerCase();
            return val && !existing.has(val);
        });
    }
    get isRelatedStageDisabled() {
        return !this.isApiResponseReceived;
    }



    get disableCreateLead() {
        return (
            !this.newLeadCourse ||
            this.isCreatingRelatedLead
        );
    }
    get isLeadTab() {
        return this.activeTab === 'lead';
    }

    get isHistoryTab() {
        return this.activeTab === 'history';
    }

    get isRelatedTab() {
        return this.activeTab === 'related';
    }

    get hasRelatedLeads() {
        return (this.relatedLeads || []).length > 0;
    }

    get leadTabClass() {
        return `tab-item ${this.activeTab === 'lead' ? 'active' : ''}`;
    }

    get historyTabClass() {
        return `tab-item ${this.activeTab === 'history' ? 'active' : ''}`;
    }

    get relatedTabClass() {
        return `tab-item ${this.activeTab === 'related' ? 'active' : ''}`;
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

    get formattedCreatedDate() {
        if (!this.identity.createdDate) {
            return '';
        }

        const date = new Date(this.identity.createdDate);

        return new Intl.DateTimeFormat('en-IN', {
            year: 'numeric',
            month: 'short',
            day: '2-digit',
            hour: '2-digit',
            minute: '2-digit'
        }).format(date);
    }

    get hasCallHistory() {
        return (this.callHistory || []).length > 0;
    }

    get isSaveDisabled() {
        return this.savingFeedback || !this.showFeedback;
    }

    get disableL2Final() {
        return this.isL2Disabled;
    }

    get isL2FinalDisabled() {
        return this.isL2Disabled || this.isFeedbackDisabled;
    }

    get isStageFinalDisabled() {
        return this.isStageDisabled || this.isFeedbackDisabled;
    }

    get isFollowUpFinalDisabled() {
        return this.autoSetFollowUp || this.isFeedbackDisabled;
    }

    get filteredL1Options() {
        return this.l1Options;
    }

    handleNotifyChange(event) {
        this.notifyMe = event.target.checked;
    }

    handleTabClick(event) {
        this.activeTab = event.target.dataset.tab;

        if (this.activeTab === 'webinar' && !this.webinarLoaded) {
            this.loadWebinarHistory();
        }

        if (this.activeTab === 'event' && !this.eventLoaded) {
            this.loadEventHistory();
        }

        if (this.activeTab === 'related' && !this.relatedLeadsLoaded) {
            this.loadRelatedLeads();
        }
    }

    handleRelatedStageChange(event) {
        const leadId = event.currentTarget?.dataset?.id;
        const stage = event.detail.value;

        this.relatedLeads = (this.relatedLeads || []).map(r => {
            if (r.id === leadId) {
                return { ...r, stage };
            }
            return r;
        });

        if (leadId) {
            this.relatedLeadEdits = {
                ...this.relatedLeadEdits,
                [leadId]: stage
            };
        }
    }

    handleNewLeadCourseChange(event) {
        this.newLeadCourse = event.detail.value;
        console.log('Selected Course:', this.newLeadCourse);
    }

    handleNewLeadEmailChange(event) {
        this.newLeadEmail = event.target.value;
    }

    handleViewMoreLead() {
        if (!this.recordId) {
            return;
        }

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

    handleDndChange(event) {
        this.isDnd = event.target.checked;
    }

    handleSpamChange(event) {
        this.isSpam = event.target.checked;
    }

    handleExpectedDateChange(event) {
        this.expectedPaymentDate = event.target.value;
    }

    get todayIsoDate() {
        return new Date().toLocaleDateString('en-CA');
    }

    get isConnectedOnlyFieldsDisabled() {
        return this.isFeedbackDisabled || this.l1Value !== 'Connected';
    }

    resetConnectedOnlyFieldsIfNeeded() {
        if (this.l1Value === 'Connected') {
            return;
        }

        this.expectedPaymentDate = null;
        this.notifyMe = false;
        this.isDnd = false;
        this.isSpam = false;
    }

    isPastExpectedPaymentDate() {
        return !!this.expectedPaymentDate && this.expectedPaymentDate < this.todayIsoDate;
    }

    getNormalizedProgramName() {
        return String(this.levelValue || this.courseValue || this.identity?.level || '')
            .trim()
            .toUpperCase()
            .replace(/\s+/g, '');
    }

    isExpectedPaymentDateRequired() {
        const stage = String(this.stageValue || '').trim().toUpperCase();
        const program = this.getNormalizedProgramName();

        if (!stage || !program) {
            return false;
        }

        if (program.includes('USP')) {
            return stage === 'U6';
        }

        if (
            program.includes('CPA') ||
            program.includes('CMA') ||
            program.includes('CAIRA')
        ) {
            return stage === 'M6';
        }

        return false;
    }

    handleCourseChange(event) {
        this.courseValue = event.target.value;
    }

    handleL1Change(event) {
        this.l1Value = event.target.value;
        this.userChangedStage = false;

        const l2List = this.l1L2Map[this.l1Value] || [];
        this.l2Options = l2List.map(v => ({
            label: v,
            value: v
        }));

        this.isL2Disabled = this.l2Options.length === 0;
        this.l2Value = '';
        this.isStageDisabled = this.l1Value === 'Not-Connected';
        this.resetConnectedOnlyFieldsIfNeeded();

        this.updateCommentVisibility();
    }

    handleL2Change(event) {
        this.l2Value = event.target.value;
        this.updateCommentVisibility();

        if (this.l2Value) {
            this.applyAutoStageLogic();
        }
    }

    handleStageChange(event) {
        this.stageValue = event.target.value;
        this.userChangedStage = true;
    }

    handleLevelChange(event) {
        this.levelValue = event.target.value;
    }

    handleFeedbackChange(event) {
        this.feedback = event.target.value;
    }

    handleAutoSetChange(event) {
        this.autoSetFollowUp = event.target.checked;

        if (this.autoSetFollowUp) {
            this.setAutoDate24();
        }
    }

    handleNextFollowUpDateChange(event) {
        if (!this.autoSetFollowUp) {
            this.nextFollowUpDate = event.target.value;
        }
    }


    handleNextFollowUpTimeChange(event) {
        if (!this.autoSetFollowUp) {
            this.nextFollowUpTime = event.target.value;
        }
    }

    close() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    @api
    startCall() {
        this.callApi();
    }

    resolveRecordIdFromPageRef() {
        if (this.recordId) {
            return;
        }

        const state = this.pageRef?.state;
        if (!state) {
            return;
        }

        const recId = state.recordId || state.c__recordId || state.id || state.c__id;

        if (recId && (recId.length === 15 || recId.length === 18)) {
            this.recordId = recId;
            console.log('RecordId resolved from pageRef:', this.recordId);
            this.loadCallHistory();
        }
    }

    async handleCreateRelatedLead() {
        if (!this.candidateId || !this.newLeadCourse || this.isCreatingRelatedLead) {
            return;
        }

        try {
            this.isCreatingRelatedLead = true;

            await createRelatedLead({
                candidateId: this.candidateId,
                course: this.newLeadCourse,
                email: this.newLeadEmail,
                sourceRecordId: this.recordId
            });

            this.newLeadCourse = '';
            this.newLeadEmail = '';

            await this.loadRelatedLeads();

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Success',
                    message: 'Related lead created successfully',
                    variant: 'success'
                })
            );
        } catch (e) {
            console.error('Create related lead failed:', e);
            this.toast(
                'Create Failed',
                e?.body?.message || e?.message || 'Failed to create lead',
                'error'
            );
        } finally {
            this.isCreatingRelatedLead = false;
        }
    }

    connectedCallback() {
        this.resolveRecordIdFromPageRef();
        this.loadDispositionConfig();
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

    disconnectedCallback() {
        this.stopTimer();
        this.clearFeedbackTimers();

        if (this.subscription) {
            unsubscribe(this.subscription, () => { });
            this.subscription = null;
        }
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
                this.levelOptions = data.level.map(v => ({
                    label: v,
                    value: v
                }));
            }
        } catch (e) {
            console.error('Stage/Course load failed:', e);
        }
    }

    async loadRelatedLeads() {
        const relatedEntityId = this.candidateId || this.studentId || this.recordId;

        if (!relatedEntityId) {
            this.relatedLeads = [];
            this.relatedLeadsLoaded = true;
            return;
        }

        try {
            const rows = await getRelatedLeads({
                candidateId: relatedEntityId
            });

            this.relatedLeads = (rows || []).map(r => ({
                id: r.id,
                recordTypeId: r.recordTypeId,
                course: r.course || 'NA',
                stage: r.stage || '',
                stageOptions: this.recordTypeStageMap[r.recordTypeId] || []
            }));

            this.queueRelatedStageOptions();
            this.relatedLeadsLoaded = true;
        } catch (e) {
            console.error('Related leads load failed:', e);
            this.relatedLeads = [];
            this.relatedLeadsLoaded = true;
        }
    }

    queueRelatedStageOptions() {
        const missingIds = [
            ...new Set(
                (this.relatedLeads || [])
                    .map(row => row.recordTypeId)
                    .filter(id => id && !this.recordTypeStageMap[id])
            )
        ];

        this.pendingRelatedRecordTypeIds = missingIds;

        if (!this.activeRelatedRecordTypeId) {
            this.loadNextRelatedStageOptions();
        }
    }

    loadNextRelatedStageOptions() {
        if (this.pendingRelatedRecordTypeIds.length === 0) {
            this.activeRelatedRecordTypeId = null;
            return;
        }

        this.activeRelatedRecordTypeId = this.pendingRelatedRecordTypeIds[0];
        this.pendingRelatedRecordTypeIds = this.pendingRelatedRecordTypeIds.slice(1);
    }

    async loadDispositionConfig() {
        try {
            const data = await getDispositions();

            this.dispositionConfigMap = {};
            this.l1Options = [];
            this.l2Options = [];

            const l1Set = new Set();
            const l1L2Map = {};

            (data || []).forEach(row => {
                const key = `${row.l1}:${row.l2}`;
                this.dispositionConfigMap[key] = row.commentNeeded;

                if (row.l1) {
                    l1Set.add(row.l1);
                }

                if (!l1L2Map[row.l1]) {
                    l1L2Map[row.l1] = new Set();
                }

                if (row.l2) {
                    l1L2Map[row.l1].add(row.l2);
                }
            });

            this.l1Options = [...l1Set].map(val => ({
                label: val,
                value: val
            }));

            this.l1L2Map = {};
            Object.keys(l1L2Map).forEach(l1 => {
                this.l1L2Map[l1] = [...l1L2Map[l1]];
            });

            console.log('Metadata L1/L2 loaded successfully');
        } catch (e) {
            console.error('Disposition metadata load failed:', e);
        }
    }

    async loadEventHistory() {
        if (!this.recordId) {
            return;
        }

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
        if (!this.recordId) {
            return;
        }

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

    async loadWebinarHistory() {
        if (!this.recordId) {
            return;
        }

        try {
            const rows = await getWebinarMembers({
                candidateId: this.recordId
            });

            console.log('Webinar rows => ', rows);

            const dateFmt = new Intl.DateTimeFormat('en-IN', {
                day: '2-digit',
                month: 'short',
                year: 'numeric'
            });

            this.webinarHistory = (rows || []).map(r => ({
                id: r.id,
                webinar: r.webinarName,
                status: r.attendanceStatus || 'NA',
                createdDate: r.createdDate
                    ? dateFmt.format(new Date(r.createdDate))
                    : 'NA'
            }));

            this.webinarLoaded = true;
        } catch (e) {
            console.error('Webinar history load failed:', e);
        }
    }

    updateCommentVisibility() {
        const key = `${this.l1Value}:${this.l2Value}`;
        this.isCommentMandatory = this.dispositionConfigMap[key] === true;
    }

    async callApi() {
        this.callButtonDisabled = true;
        this.loading = true;
        this.errorText = null;
        this.isFeedbackDisabled = true;

        this.callStatus = 'Dialing…';
        this.isLive = false;
        this.showCallButton = false;  
this.showFeedback = false; 
        this.showCallPopup = true;

        this.l1Value = '';
        this.resetConnectedOnlyFieldsIfNeeded();
        this.l2Value = '';

        const l2List = this.l1L2Map[this.l1Value] || [];
        this.l2Options = l2List.map(v => ({
            label: v,
            value: v
        }));

        this.isL2Disabled = this.l2Options.length === 0;
        this.updateCommentVisibility();
        this.canEndCall = false;

        this.setElapsed(0);
        this.startTimer();
        this.lastCallId = null;
        this.clearFeedbackTimers();

        try {
            const response = await allocateLeadNow({ recordId: this.recordId });
            const parsed = typeof response === 'string' ? JSON.parse(response) : response || {};

            this.lastCallId = parsed?.callId || this.lastCallId;
            this.callTitle = parsed?.displayName || 'Calling via Runo';
            this.callStatus = 'In Call…';
            this.isLive = true;

            this.showPopup = true;
            setTimeout(() => (this.showPopup = false),200);

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
            this.isFeedbackDisabled = false;

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


    toggleToFeedbackMode() {
    this.showCallButton = false;
    this.showFeedback = true;
    this.isFeedbackDisabled = false;
}

    handleEndCall() {
        if (!this.canEndCall && !this.isLive) {
            return;
        }

        this.callStatus = 'Ended';
        this.isLive = false;
        this.showCallPopup = false;

        this.stopTimer();
        this.clearFeedbackTimers();
       this.toggleToFeedbackMode();
        this.callButtonDisabled = true;
    }

    showFeedbackSection() {
      
    this.toggleToFeedbackMode();

        if (this.autoSetFollowUp) {
            this.setAutoDate24();
        }
    }

    setAutoDate24() {
        const next = new Date(Date.now() + 24 * 60 * 60 * 1000);

        const yyyy = next.getFullYear();
        const mm = String(next.getMonth() + 1).padStart(2, '0');
        const dd = String(next.getDate()).padStart(2, '0');


        this.nextFollowUpDate = `${yyyy}-${mm}-${dd}`;
        this.nextFollowUpTime = `10:00`;
    }

    applyAutoStageLogic() {
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

    async saveFeedback() {
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
        if (!this.l2Value) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: 'Please select L2 before saving feedback.',
                    variant: 'error'
                })
            );
            return;
        }

        if (this.isExpectedPaymentDateRequired() && !this.expectedPaymentDate) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Required',
                    message: 'Expected Payment Date is mandatory for this stage.',
                    variant: 'error'
                })
            );
            return;
        }
        if (this.isPastExpectedPaymentDate()) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Required',
                    message: 'Expected Payment Date cannot be in the past.',
                    variant: 'error'
                })
            );
            return;
        }


        if (this.l1Value === 'Not-Connected') {
            this.stageValue = null;
            this.resetConnectedOnlyFieldsIfNeeded();
        }

        this.savingFeedback = true;

        try {
            let combinedDateTime = this.nextFollowUpDate
                ? this.nextFollowUpDate + 'T' + (this.nextFollowUpTime || '10:00') + ':00'
                : null;

            // FORCE CLEAN (THIS FIXES YOUR ERROR)
            if (combinedDateTime) {
                combinedDateTime = combinedDateTime.split('.')[0];
            }

            console.log('FINAL DATETIME:', combinedDateTime);


            const payload = {
                recordId: this.recordId,
                callId: this.lastCallId,
                feedback: this.feedback?.trim(),
                nextFollowUpDate: combinedDateTime,
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

            await this.loadCallHistory();

            const edits = Object.keys(this.relatedLeadEdits || {}).map(id => ({
                id,
                stage: this.relatedLeadEdits[id]
            }));

            if (edits.length > 0) {
                try {
                    await updateRelatedLeadStages({ updates: edits });
                    await this.loadRelatedLeads();
                } catch (e) {
                    console.error('Related leads update failed:', e);
                    this.toast(
                        'Related Update Failed',
                        e?.body?.message || e?.message || 'Failed to update related leads',
                        'error'
                    );
                }
            }

            this.dispatchEvent(new CloseActionScreenEvent());

            this.clearFeedbackTimers();
            this.showFeedback = true;
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
            this.relatedLeadEdits = {};

            sessionStorage.setItem('RUNO_REFRESH_ON_BACK', 'true');
            this.navigateAfterSave();
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
            } catch (err) { }

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Save Failed',
                    message,
                    variant: 'error'
                })
            );
        } finally {
            this.savingFeedback = false;
            this.disableCancel = false;
        }
    }

    navigateAfterSave() {
        if (!this.recordId) {
            return;
        }

        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this.recordId,
                objectApiName: 'Lead',
                actionName: 'view'
            }
        });
    }

    clearFeedbackTimers() {
        if (this.noResponseTimer) {
            clearTimeout(this.noResponseTimer);
            this.noResponseTimer = null;
        }

        this.canEndCall = false;
    }

    startTimer() {
        if (this.timerId) {
            return;
        }

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

    subscribeToEvents() {
        if (this.subscription) {
            return;
        }

        subscribe(this.channelName, -1, msg => this.onRunoEvent(msg))
            .then(resp => {
                this.subscription = resp;
            })
            .catch(() => { });
    }

    onRunoEvent(msg) {
        this.isApiResponseReceived = true;

        const p = (msg && msg.data && msg.data.payload) || {};

        const evtLeadId = p.Lead_Id__c || p.LeadId__c || p.leadId || null;
        const evtCallId = p.Call_Id__c || p.CallId__c || p.callId || null;

        if (evtLeadId && String(evtLeadId) !== String(this.recordId)) {
            return;
        }

        if (evtCallId) {
            this.lastCallId = String(evtCallId);
        }

        const duration = Number(
            p.Duration_Seconds__c ||
            p.Duration__c ||
            p.durationSeconds
        );

        const status = p.Status__c || p.status || '';

        if (status === 'Completed' && !Number.isNaN(duration) && duration > 0) {

            this.l1Value = 'Connected';
            this.isL1Locked = true;

            totalSec = Math.floor(duration);
            const mm = String(Math.floor(totalSec / 60)).padStart(2, '0');
            const ss = String(totalSec % 60).padStart(2, '0');
            this.elapsedLabel = `${mm}:${ss}`;

        } else {

            this.l1Value = 'Not-Connected';
            this.isL1Locked = true;
            this.resetConnectedOnlyFieldsIfNeeded();

            this.elapsedLabel = '00:00';
        }

        const l2List = this.l1L2Map[this.l1Value] || [];
        this.l2Options = l2List.map(v => ({
            label: v,
            value: v
        }));

        this.isL2Disabled = this.l2Options.length === 0;
        this.l2Value = '';
        this.updateCommentVisibility();

        this.callStatus = 'Ended';
        this.isLive = false;
        this.showCallPopup = false;

        this.stopTimer();
        this.clearFeedbackTimers();

        this.showFeedbackSection();
        this.callButtonDisabled = true;
this.toggleToFeedbackMode();
        this.isFeedbackDisabled = false;

        console.log('RUNO EVENT => CALL ENDED');
        console.log('Platform Event Payload:', JSON.stringify(p));
    }

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