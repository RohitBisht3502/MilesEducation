import { api, LightningElement, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import allocateLeadNow from '@salesforce/apex/Webservice_RunoAllocationAPI.allocateLeadNow';
import updateCallFeedback from '@salesforce/apex/Webservice_RunoAllocationAPI.updateCallFeedback';
import getCallHistory from '@salesforce/apex/Webservice_RunoAllocationAPI.getCallHistory';
import getIdentity from '@salesforce/apex/RunoCallIdentityService.getIdentity';
import getRelatedLeads from '@salesforce/apex/RunoCallIdentityService.getRelatedLeads';
import createRelatedLead from '@salesforce/apex/RunoCallIdentityService.createRelatedLead';
import getStageLevelValues from '@salesforce/apex/Webservice_RunoAllocationAPI.getStageLevelValues';
import updateRelatedLeadStages from '@salesforce/apex/RunoCallIdentityService.updateRelatedLeadStages';
import { CurrentPageReference } from 'lightning/navigation';
import { NavigationMixin } from 'lightning/navigation';
// import { getPicklistValuesByRecordType }
// from 'lightning/uiObjectInfoApi';
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
import USER_ID from '@salesforce/user/Id';
import { EnclosingUtilityId } from 'lightning/platformUtilityBarApi';




export default class RunoCallFeedbackUtility extends NavigationMixin(LightningElement) {

    @api recordId;
    @wire(EnclosingUtilityId) utilityId;

    objectApiName;
    candidateId;
    isFeedbackDisabled = true;
    isL1Locked = false;
    // UI / state
    loading = false;
    disableCancel = false;
    @track isListening = false;
    @track feedback = '';
    @track interimText = '';

    callButtonDisabled = false;

    // Call popup overlay (Calling Runo...)
    showCallPopup = false;
    isStageDisabled = false;
    relatedLeadEdits = {};
    activeTab = 'feedback';
    expectedPaymentDate;
    notifyMe = false;
    isApiResponseReceived = false;
    recognition;
    currentUserId = USER_ID;
    // L1/L2
    l1Value = '';
    l2Value = '';
    l1Options = [];
    l2Options = [];

    isL2Disabled = true;
    l1L2Map = {};
    autoSetFollowUp = true;
    userChangedStage = false;
    showCreateLeadSection = false;
    // Stage / Course
    stageValue = '';
    levelValue = '';
    stageOptions = [];
    currentStageOptions = [];
    levelOptions = [];
    leadRecordTypeId = null;
    recordTypeStageMap = {};
    activeRelatedRecordTypeId = null;
    pendingRelatedRecordTypeIds = [];

    // auto call start from lead url 
    autoCall = false;
    hasAutoCalled = false;


    // Toast / error
    showPopup = false;
    errorText;

    // Lead summary shown in the fixed left panel.
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
    // call state
    isLive = false;
    callStatus = 'Idle';
    callTitle = 'Calling via Runo';

    elapsedMs = 0;
    elapsedLabel = '00:00';
    timerId = null;
    webinarHistory = [];
    webinarLoaded = false;
    relatedLeads = [];
    relatedLeadsLoaded = false;
    newLeadCourse = '';
    newLeadEmail = '';
    isCreatingRelatedLead = false;
    openedFromMissedCallPanel = false;
    missedCallRefreshToken = 0;
    // feedback
    showFeedback = false;
    savingFeedback = false;

    nextFollowUpDate = null;
    nextFollowUpTime = null;
    lastCallId = null;

    // manual end call if no response in 30s
    canEndCall = false;
    CALL_NO_RESPONSE_MS = 30000;
    noResponseTimer = null;


    handleNotifyChange(event) {
        this.notifyMe = event.target.checked;
    }

    // comment box always visible; mandatory controlled by isCommentMandatory
    showCommentBox = true;
    isCommentMandatory = false;
    dispositionConfigMap = {};
    // ---------------- WIRE ----------------

    @wire(getIdentity, { recordId: '$recordId' })
    wiredIdentity({ data, error }) {
        if (data) {
            this.identity = data;

            if (data.stage) this.stageValue = data.stage;

            if (data.level) {
                this.courseValue = data.level;
            }

            if (!this.candidateId && data.candidateId) {
                this.candidateId = data.candidateId;
                // Load the course cards as soon as identity gives us the candidate.
                this.loadRelatedLeads();
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

    @wire(getPicklistValues, {
        recordTypeId: '$recordTypeId',
        fieldApiName: STAGE_FIELD
    })
    wiredCurrentStagePicklist({ data, error }) {
        if (data) {
            this.currentStageOptions = (data.values || []).map(v => ({
                label: v.label,
                value: v.value
            }));
            return;
        }

        if (error) {
            this.currentStageOptions = [];
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

            this.relatedLeads = (this.relatedLeads || []).map(row => (
                row.recordTypeId === this.activeRelatedRecordTypeId
                    ? {
                        ...row,
                        stageOptions: this.mergeStageOptions(options, row.stage)
                    }
                    : row
            ));

            this.loadNextRelatedStageOptions();
        } else if (error && this.activeRelatedRecordTypeId) {
            console.error('Related stage picklist load failed:', error);
            this.loadNextRelatedStageOptions();
        }
    }

    mergeStageOptions(options, selectedValue) {
        const normalizedOptions = [...(options || [])];
        if (
            selectedValue &&
            !normalizedOptions.some(option => option.value === selectedValue)
        ) {
            normalizedOptions.unshift({
                label: selectedValue,
                value: selectedValue
            });
        }
        return normalizedOptions;
    }

    // -------------- PAGE REFERENCE (URL SAFE) --------------

    @wire(CurrentPageReference)
    wiredPageRef(pageRef) {
        this.pageRef = pageRef;

        const state = pageRef?.state;
        if (!state) return;

        // resolve recordId (already your logic)
        this.resolveRecordIdFromPageRef();

        //  AUTO CALL FLAG
        if (state.c__autoCall === 'true') {
            this.autoCall = true;
        }
    }

    get isFeedbackTab() {
        return this.activeTab === 'feedback';
    }

    get isLeadTab() {
        return this.activeTab === 'lead';
    }


    get isHistoryTab() {
        return this.activeTab === 'history';
    }

    get showExtendedLeadFields() {
        if (!this.recordId) return false;

        // Lead__c custom object prefix usually starts with 'a0'
        return this.recordId.startsWith('a0');
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


    get feedbackTabClass() {
        return `tab-item ${this.activeTab === 'feedback' ? 'active' : ''}`;
    }

    get leadTabClass() {
        return `tab-item ${this.activeTab === 'lead' ? 'active' : ''}`;
    }

    // Utility bar is narrow, so feedback and lead info both stay single-column.
    get contentRowClass() {
        if (this.isFeedbackTab || this.isLeadTab) {
            return 'content-row one-col-layout utility-single-col';
        }

        return 'content-row one-col-layout';
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

    get showLiveCallWorkspace() {
        return this.showFeedback || this.showCallPopup || this.isLive;
    }

    get showMissedCallWorkspace() {
        return !this.showLiveCallWorkspace;
    }

    get panelTitle() {
        return this.showMissedCallWorkspace ? 'Runo Missed Calls' : this.callTitle;
    }

    get panelStatus() {
        return this.showMissedCallWorkspace ? 'Follow-up' : this.callStatus;
    }

    get isEventTab() {
        return this.activeTab === 'event';
    }

    get hasEvents() {
        return (this.eventHistory || []).length > 0;
    }

    get hasRelatedLeads() {
        return (this.relatedLeads || []).length > 0;
    }

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

    get disableCreateLead() {
        return (
            !this.candidateId ||
            !this.newLeadCourse ||

            this.availableCourseOptions.length === 0 ||
            this.isCreatingRelatedLead
        );
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

    handleNewLeadEmailChange(event) {
        this.newLeadEmail = event.target.value;
    }

    resetForMissedCallRecord(recordId, callId) {
        this.recordId = recordId || null;
        this.lastCallId = callId || null;
        this.candidateId = null;
        this.leadRecordTypeId = null;
        this.stageValue = '';
        this.currentStageOptions = [];
        this.levelValue = '';
        this.courseValue = '';
        this.stageOptions = [];
        this.levelOptions = [];
        this.l1Value = '';
        this.l2Value = '';
        this.l2Options = [];
        this.isL2Disabled = true;
        this.isL1Locked = false;
        this.isStageDisabled = false;
        this.userChangedStage = false;
        this.expectedPaymentDate = null;
        this.notifyMe = false;
        this.isDnd = false;
        this.isSpam = false;
        this.feedback = '';
        this.interimText = '';
        this.nextFollowUpDate = null;
        this.nextFollowUpTime = null;
        this.relatedLeadEdits = {};
        this.relatedLeads = [];
        this.relatedLeadsLoaded = false;
        this.showCreateLeadSection = false;
        this.identity = {
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
        this.loadStageAndCourse();
        this.loadCallHistory();
    }

    returnToMissedCallPanel() {
        this.clearFeedbackTimers();
        this.showFeedback = false;
        this.showCallPopup = false;
        this.isLive = false;
        this.callButtonDisabled = false;
        this.isFeedbackDisabled = true;
        this.activeTab = 'feedback';
        this.callStatus = 'Idle';
        this.setElapsed(0);
        this.recordId = null;
        this.lastCallId = null;
        this.candidateId = null;
    }

    handleMissedCallFeedback(event) {
        const { recordId, callId } = event.detail || {};
        Promise.resolve().then(() => {
            if (!recordId) {
                return;
            }
            this.resetForMissedCallRecord(recordId, callId);
            this.openedFromMissedCallPanel = true;
            this.activeTab = 'feedback';
            this.showCallPopup = false;
            this.isLive = false;
            this.callStatus = 'Missed Call Follow-up';
            this.callButtonDisabled = false;
            this.isFeedbackDisabled = false;
            this.stopTimer();
            this.setElapsed(0);
            this.showFeedbackSection();
            this.openUtilityPanel();
        }).catch(error => {
            console.error('Missed call feedback open failed:', error);
            this.toast('Error', error?.body?.message || error?.message || 'Failed to open feedback.', 'error');
        });
    }

    handleMissedCallCandidate(event) {
        const { recordId, callId } = event.detail || {};
        Promise.resolve().then(() => {
            if (!recordId) {
                return;
            }
            this.resetForMissedCallRecord(recordId, callId);
            this.openedFromMissedCallPanel = true;
            this.activeTab = 'feedback';
            this.openUtilityPanel();
            return this.callApi();
        }).catch(error => {
            console.error('Missed call candidate dial failed:', error);
            this.toast('Error', error?.body?.message || error?.message || 'Failed to start candidate call.', 'error');
        });
    }

    handleNewLeadCourseChange(event) {
        this.newLeadCourse = event.detail.value;
    }

    // Keep the course cards numbered in UI order.
    reindexRelatedLeads(rows = []) {
        return rows.map((row, index) => ({
            ...row,
            displayIndex: index + 1
        }));
    }
    handleExpectedDateChange(event) {
        const id = event.target.dataset.id;
        const value = event.target.value;

        this.relatedLeads = this.relatedLeads.map(row => {
            if (row.id === id) return { ...row, expectedPaymentDate: value };
            return row;
        });

        if (id === this.recordId) {
            this.expectedPaymentDate = value;
        }

        // ✅ also track in edits map so saveFeedback picks it up
        this.relatedLeadEdits = {
            ...this.relatedLeadEdits,
            [id]: {
                ...(this.relatedLeadEdits[id] || {}),
                expectedPaymentDate: value
            }
        };
    }

    get todayIsoDate() {
        return new Date().toLocaleDateString('en-CA');
    }

    get isConnectedOnlyFieldsDisabled() {
        return this.isFeedbackDisabled || this.l1Value !== 'Connected';
    }

    getCurrentLeadExpectedPaymentDate() {
        const currentLeadEdit = this.relatedLeadEdits?.[this.recordId];
        if (currentLeadEdit && Object.prototype.hasOwnProperty.call(currentLeadEdit, 'expectedPaymentDate')) {
            return currentLeadEdit.expectedPaymentDate || null;
        }

        const currentLeadRow = (this.relatedLeads || []).find(row => String(row.id) === String(this.recordId));
        if (currentLeadRow) {
            return currentLeadRow.expectedPaymentDate || null;
        }

        return this.expectedPaymentDate || null;
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


    renderedCallback() {
        const textarea = this.template.querySelector('.comment-textarea');
        if (textarea && !this.isListening) {
            // Keep the native textarea synced without interrupting live dictation.
            if (textarea.value !== (this.feedback || '')) {
                textarea.value = this.feedback || '';
            }
        }
    }

    isPastExpectedPaymentDate() {
        const expectedPaymentDate = this.getCurrentLeadExpectedPaymentDate();
        return !!expectedPaymentDate && expectedPaymentDate < this.todayIsoDate;
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

    toggleCreateLead() {
        this.showCreateLeadSection = !this.showCreateLeadSection;
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
            this.loadCallHistory();
        }
    }



    handleRelatedStageChange(event) {
        const leadId = event.target?.dataset?.id || event.currentTarget?.dataset?.id;
        const stage = event.detail.value;

        this.relatedLeads = (this.relatedLeads || []).map(r => {
            if (r.id === leadId) {
                return {
                    ...r,
                    stage,
                    stageOptions: this.mergeStageOptions(r.stageOptions, stage)
                };
            }
            return r;
        });

        if (leadId) {
            this.relatedLeadEdits = {
                ...this.relatedLeadEdits,
                [leadId]: {
                    // preserve existing EPD if already tracked
                    ...(this.relatedLeadEdits[leadId] || {}),
                    stage
                }
            };
        }
    }

    // --------------- LIFECYCLE -------------

    connectedCallback() {
        // Set up browser speech recognition once when the component mounts.
        const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;

        if (SpeechRecognition) {
            this.recognition = new SpeechRecognition();

            this.recognition.continuous = true;
            this.recognition.interimResults = true;
            this.recognition.lang = 'en-IN'; // or 'hi-IN'

            this.recognition.onresult = (event) => {
                let finalTranscript = '';
                let interimTranscript = '';

                for (let i = event.resultIndex; i < event.results.length; i++) {
                    const transcript = event.results[i][0].transcript;
                    if (event.results[i].isFinal) {
                        finalTranscript += transcript + ' ';
                    } else {
                        interimTranscript += transcript;
                    }
                }

                if (finalTranscript) {
                    this.feedback = (this.feedback || '') + finalTranscript;

                    const textarea = this.template.querySelector('.comment-textarea');
                    if (textarea) {
                        textarea.value = this.feedback;
                        textarea.selectionStart = textarea.selectionEnd = textarea.value.length;
                    }
                }

                this.interimText = interimTranscript;
            };

            this.recognition.onend = () => {
                // Commit any pending interim text before the UI leaves listening mode.
                if (this.interimText) {
                    this.feedback = (this.feedback || '') + this.interimText;
                    this.interimText = '';

                    const textarea = this.template.querySelector('.comment-textarea');
                    if (textarea) {
                        textarea.value = this.feedback;
                        textarea.selectionStart = textarea.selectionEnd = textarea.value.length;
                    }
                }

                this.isListening = false;
            };
            this.recognition.onerror = (event) => {
                console.error('Speech recognition error:', event.error);
                this.isListening = false;
            };

        } else {
            console.error('Speech Recognition not supported');
        }

        this.resolveRecordIdFromPageRef();
        this.loadDispositionConfig();
        this.loadStageAndCourse();
        if (this.autoSetFollowUp) {
            this.setAutoDate24();
        }

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

        if (!this.candidateId) {
            this.relatedLeads = [];
            this.relatedLeadsLoaded = true;
            return;
        }
        try {
            // Reload the card list from server whenever a course is added/updated.
            const rows = await getRelatedLeads({
                candidateId: this.candidateId
            });

            this.relatedLeads = this.reindexRelatedLeads((rows || []).map(r => ({
                id: r.id,
                recordTypeId: r.recordTypeId,
                course: r.course || 'NA',
                stage: r.stage || '',
                expectedPaymentDate: r.expectedPaymentDate || null,
                stageOptions: this.recordTypeStageMap[r.recordTypeId] || []
            })));

            const currentLeadRow = (this.relatedLeads || []).find(row => row.id === this.recordId);
            this.expectedPaymentDate = currentLeadRow ? currentLeadRow.expectedPaymentDate : null;

            this.queueRelatedStageOptions();

            this.relatedLeadsLoaded = true;

        } catch (e) {
            console.error('Related leads load failed:', e);
            this.relatedLeads = [];
            this.relatedLeadsLoaded = true;
        }
    }

    queueRelatedStageOptions() {
        const missingIds = [...new Set(
            (this.relatedLeads || [])
                .map(row => row.recordTypeId)
                .filter(id => id && !this.recordTypeStageMap[id])
        )];

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


    get isRelatedStageDisabled() {
        return !this.isApiResponseReceived;
    }

    // async loadStageOptionsForLeads() {

    //     for (let lead of this.relatedLeads) {

    //         if (!lead.recordTypeId) continue;

    //         if (this.recordTypeStageMap[lead.recordTypeId]) {
    //             lead.stageOptions = this.recordTypeStageMap[lead.recordTypeId];
    //             continue;
    //         }

    //         const result = await getPicklistValuesByRecordType({
    //             objectApiName: 'Lead__c',
    //             recordTypeId: lead.recordTypeId
    //         });

    //         const stageField = result.picklistFieldValues.Stage__c;

    //         const options = (stageField?.values || []).map(v => ({
    //             label: v.label,
    //             value: v.value
    //         }));

    //         this.recordTypeStageMap[lead.recordTypeId] = options;

    //         lead.stageOptions = options;
    //     }

    //     this.relatedLeads = [...this.relatedLeads];
    // }

    // Create the extra course card, show it immediately, then sync with backend data.
    async handleCreateRelatedLead() {
        if (!this.candidateId || !this.newLeadCourse || this.isCreatingRelatedLead) return;

        try {
            this.isCreatingRelatedLead = true;
            const createdCourse = this.newLeadCourse;

            await createRelatedLead({
                candidateId: this.candidateId,
                course: createdCourse,
                email: this.newLeadEmail,
                sourceRecordId: this.recordId
            });

            const optimisticRow = {
                id: `temp-${Date.now()}`,
                recordTypeId: null,
                course: createdCourse || 'NA',
                stage: '',
                expectedPaymentDate: null,
                stageOptions: []
            };

            this.relatedLeads = this.reindexRelatedLeads([
                ...(this.relatedLeads || []),
                optimisticRow
            ]);

            this.newLeadCourse = '';
            this.newLeadEmail = '';
            this.showCreateLeadSection = false;

            this.relatedLeadsLoaded = false;
            await this.loadRelatedLeads();
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
        if (this.initiateSubscription) {
            unsubscribe(this.initiateSubscription, () => { });
            this.initiateSubscription = null;
        }
    }

    // -------------- DATA LOAD --------------


    async loadDispositionConfig() {
        try {
            const data = await getDispositions();

            this.dispositionConfigMap = {};
            this.l1Options = [];
            this.l2Options = [];

            const l1Set = new Set();
            const l1L2Map = {};

            (data || []).forEach(row => {

                // Build comment mandatory map
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

        } catch (e) {
            console.error('Disposition metadata load failed:', e);
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
                    durationSeconds: totalSec,
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
        if (!this.candidateId) return;

        try {
            const rows = await getWebinarMembers({
                candidateId: this.candidateId
            });

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

    handleL1Change(e) {


        if (this.isL1Locked) {
            return;
        }

        this.l1Value = e.target.value;
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


    // Start voice input for the comment box.
    handleMicClick() {
        if (this.recognition) {
            this.isListening = true;
            this.recognition.start();
        }
    }

    get commentTextareaClass() {
        return `comment-textarea ${this.isListening ? 'comment-textarea--listening' : ''}`.trim();
    }

    // Stop voice input and keep the last interim text.
    handleMicStop() {
        if (this.recognition) {
            if (this.interimText) {
                this.feedback = (this.feedback || '') + this.interimText;
                this.interimText = '';

                const textarea = this.template.querySelector('.comment-textarea');
                if (textarea) {
                    textarea.value = this.feedback;
                    textarea.selectionStart = textarea.selectionEnd = textarea.value.length;
                }
            }

            this.isListening = false;
            this.recognition.stop();
        }
    }
    handleFeedbackChange(e) {
        this.feedback = e.target.value;
    }

    // checkbox handler for "Auto set next follow up"
    handleAutoSetChange(e) {
        this.autoSetFollowUp = e.target.checked;

        if (this.autoSetFollowUp) {
            this.setAutoDate24();
        }
    }

    handleNextFollowUpDateChange(e) {
        this.nextFollowUpDate = e.target.value;
        this.autoSetFollowUp = false;
    }



    handleNextFollowUpTimeChange(e) {
        this.nextFollowUpTime = e.target.value;
        this.autoSetFollowUp = false;
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
        this.isFeedbackDisabled = true;

        this.callStatus = 'Dialing…';
        this.isLive = false;
        this.showFeedback = true;
        this.showCallPopup = true;

        this.l1Value = '';
        this.resetConnectedOnlyFieldsIfNeeded();
        this.l2Value = '';

        // Load L2 options immediately
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

                    //  Automatically show feedback after 30s
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




    get disableL2Final() {

        return this.isL2Disabled;
    }
    // use autoSetFollowUp + setAutoDate24 (same as good LWC)
    showFeedbackSection() {
        this.showFeedback = true;
        this.disableCancel = false;
        if (this.autoSetFollowUp) {
            this.setAutoDate24();
        }
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

    get normalizedCurrentStageValues() {
        return new Set((this.currentStageOptions || []).map(option => String(option.value || '').trim()));
    }

    get hasValidSelectedStage() {
        const selectedStage = String(this.stageValue || '').trim();
        if (!selectedStage) {
            return false;
        }

        if (!(this.currentStageOptions || []).length) {
            return true;
        }

        return this.normalizedCurrentStageValues.has(selectedStage);
    }


    get filteredL1Options() {
        return this.l1Options;
    }

    //  helper to set nextFollowUpDate = now + 24h in ISO format
    setAutoDate24() {
        const next = new Date(Date.now() + 24 * 60 * 60 * 1000);

        const yyyy = next.getFullYear();
        const mm = String(next.getMonth() + 1).padStart(2, '0');
        const dd = String(next.getDate()).padStart(2, '0');
        const hh = String(next.getHours()).padStart(2, '0');
        const min = String(next.getMinutes()).padStart(2, '0');


        this.nextFollowUpDate = `${yyyy}-${mm}-${dd}`;
        this.nextFollowUpTime = `${hh}:${min}`;
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
        const effectiveExpectedPaymentDate = this.getCurrentLeadExpectedPaymentDate();

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

        if (this.isExpectedPaymentDateRequired() && !effectiveExpectedPaymentDate) {
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

            // Drop milliseconds so Apex gets a stable datetime string.
            if (combinedDateTime) {
                combinedDateTime = combinedDateTime.split('.')[0];
            }

            const payload = {
                recordId: this.recordId,
                callId: this.lastCallId,
                feedback: this.feedback?.trim(),
                nextFollowUpDate: combinedDateTime ? String(combinedDateTime) : null,
                l1: this.l1Value,
                l2: this.l2Value,
                //    level: this.courseValue,

                notifyMe: this.notifyMe,
                isDnd: this.isDnd,
                isSpam: this.isSpam,
                expectedPaymentDate: effectiveExpectedPaymentDate

            };
            console.log('Runo feedback save debug', {
                recordId: this.recordId,
                lastCallId: this.lastCallId,
                leadRecordTypeId: this.leadRecordTypeId,
                identity: this.identity,
                candidateId: this.candidateId,
                stageValue: this.stageValue,
                currentStageOptions: this.currentStageOptions,
                l1Value: this.l1Value,
                l2Value: this.l2Value,
                nextFollowUpDate: this.nextFollowUpDate,
                nextFollowUpTime: this.nextFollowUpTime,
                payload
            });
            if (this.stageValue && String(this.stageValue).trim() && !this.hasValidSelectedStage) {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Invalid Stage',
                        message: 'Selected stage is not valid for this record.',
                        variant: 'error'
                    })
                );
                return;
            }

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
            // await this.loadUntrackedStatus();
            const edits = Object.keys(this.relatedLeadEdits || {})
                .map(id => {
                    const edit = this.relatedLeadEdits[id] || {};
                    const hasStage = Object.prototype.hasOwnProperty.call(edit, 'stage');
                    const hasExpectedPaymentDate = Object.prototype.hasOwnProperty.call(edit, 'expectedPaymentDate');
                    const hasNextFollowUpDate = !!combinedDateTime;

                    if (!hasStage && !hasExpectedPaymentDate && !hasNextFollowUpDate) {
                        return null;
                    }

                    return {
                        id,
                        stage: hasStage ? (edit.stage || null) : null,
                        expectedPaymentDate: hasExpectedPaymentDate ? (edit.expectedPaymentDate || null) : null,
                        nextFollowUpDate: combinedDateTime ? String(combinedDateTime) : null
                    };
                })
                .filter(edit => edit !== null);
            if (edits.length > 0) {
                try {
                    await updateRelatedLeadStages({
                        jsonBody: JSON.stringify({
                            updates: edits,
                            callDisposition: this.l1Value
                        })
                    });
                    await this.loadRelatedLeads();
                    this.relatedLeadEdits = {};
                } catch (e) {
                    console.error('Related leads update failed:', e);
                    this.toast('Related Update Failed', e?.body?.message || e?.message || 'Failed to update related leads', 'error');
                }
            }


            // this.dispatchEvent(new CloseActionScreenEvent());

            this.clearFeedbackTimers();
            this.disableCancel = true;
            this.callStatus = 'Idle';
            this.isLive = false;
            this.showCallPopup = false;
            this.setElapsed(0);

            //         setTimeout(() => {
            //     window.location.reload();
            // }, 500);

            // reset fields like good LWC
            this.feedback = '';
            this.l1Value = '';
            this.l2Value = '';
            this.updateCommentVisibility();
            if (this.autoSetFollowUp) {
                this.setAutoDate24();
            } else {
                this.nextFollowUpDate = null;
                this.nextFollowUpTime = null;
            }
            sessionStorage.setItem('RUNO_REFRESH_ON_BACK', 'true');
            if (this.openedFromMissedCallPanel) {
                this.missedCallRefreshToken += 1;
                this.openedFromMissedCallPanel = false;
                this.returnToMissedCallPanel();
            } else {
                this.dispatchEvent(new CloseActionScreenEvent());
                this.navigateAfterSave();
            }



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


            } catch (err) { }

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
    initiateChannelName = '/event/Runo_Call_Initiate__e';
    subscription = null;
    initiateSubscription = null;

    subscribeToEvents() {
        if (!this.subscription) {
            subscribe(this.channelName, -1, msg => this.onRunoEvent(msg))
                .then(resp => {
                    this.subscription = resp;
                })
                .catch(() => { });
        }

        if (!this.initiateSubscription) {
            subscribe(this.initiateChannelName, -1, msg => this.onRunoInitiateEvent(msg))
                .then(resp => {
                    this.initiateSubscription = resp;
                })
                .catch(() => { });
        }
    }

    onRunoEvent(msg) {
        this.isApiResponseReceived = true;
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

        const duration = Number(
            p.Duration_Seconds__c ||
            p.Duration__c ||
            p.durationSeconds
        );

        const status = p.Status__c || p.status || '';

        let totalSec = 0;

        //  FINAL CORRECT LOGIC
        // if (status === 'Completed' && !Number.isNaN(duration) && duration > 0) {

        //     this.l1Value = 'Connected';
        //     this.isL1Locked = true;

        //     totalSec = Math.floor(duration);
        //     const mm = String(Math.floor(totalSec / 60)).padStart(2, '0');
        //     const ss = String(totalSec % 60).padStart(2, '0');
        //     this.elapsedLabel = `${mm}:${ss}`;

        // } else {

        //     this.l1Value = 'Not-Connected';
        //     this.isL1Locked = true;
        //     this.resetConnectedOnlyFieldsIfNeeded();

        //     this.elapsedLabel = '00:00';
        // }
        const l2List = this.l1L2Map[this.l1Value] || [];

        this.l2Options = l2List.map(v => ({
            label: v,
            value: v
        }));

        this.isL2Disabled = this.l2Options.length === 0;

        this.l2Value = '';
        this.updateCommentVisibility();

        // Stop call UI
        this.callStatus = 'Ended';
        this.isLive = false;
        this.showCallPopup = false;

        this.stopTimer();
        this.clearFeedbackTimers();

        // Show feedback section
        this.showFeedbackSection();
        this.callButtonDisabled = true;
        this.isFeedbackDisabled = false;
    }

    onRunoInitiateEvent(msg) {
        const p = (msg && msg.data && msg.data.payload) || {};
        const assignedUserId =
            p.Assigned_User__c || p.AssignedUserId__c || p.assignedUserId || null;

        if (!this.isSameUser(assignedUserId, this.currentUserId)) {
            return;
        }

        const evtLeadId =
            p.Lead_Id__c || p.LeadId__c || p.leadId || null;
        const evtCallId =
            p.Call_Id__c || p.CallId__c || p.callId || null;

        if (!evtLeadId) {
            return;
        }

        this.recordId = String(evtLeadId);
        this.activeTab = 'feedback';
        this.showFeedback = true;
        this.showCallPopup = true;
        this.callButtonDisabled = true;
        this.isFeedbackDisabled = true;
        this.callStatus = 'Dialing...';
        this.isLive = true;
        this.lastCallId = evtCallId ? String(evtCallId) : null;
        this.setElapsed(0);
        this.stopTimer();
        this.startTimer();
        this.loadCallHistory();
        this.openUtilityPanel();
    }

    isSameUser(firstId, secondId) {
        if (!firstId || !secondId) {
            return false;
        }

        return String(firstId).substring(0, 15) === String(secondId).substring(0, 15);
    }

    openUtilityPanel() {
        if (!this.utilityId) {
            return;
        }
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