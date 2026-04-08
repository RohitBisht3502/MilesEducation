import { api, LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import allocateLeadNow from '@salesforce/apex/Webservice_RunoAllocationAPI.allocateLeadNow';
import updateCallFeedback from '@salesforce/apex/Webservice_RunoAllocationAPI.updateCallFeedback';

import getCallHistory from '@salesforce/apex/Webservice_RunoAllocationAPI.getCallHistory';
import getIdentity from '@salesforce/apex/RunoCallIdentityService.getIdentity';
import getRelatedLeads from '@salesforce/apex/RunoCallIdentityService.getRelatedLeads';
import createRelatedLead from '@salesforce/apex/RunoCallIdentityService.createRelatedLead';
import getStageLevelValues from '@salesforce/apex/Webservice_RunoAllocationAPI.getStageLevelValues';
import updateRelatedLeadStages from '@salesforce/apex/RunoCallIdentityService.updateRelatedLeadStages';
import getDispositions from '@salesforce/apex/CallDispositionConfigService.getDispositions';
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

export default class RunoAllocationCallQ2 extends NavigationMixin(LightningElement) {

    @api recordId;
    candidateId;
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
    isFeedbackDisabled = true;
    callButtonLabel = 'Call Runo';
    callButtonDisabled = false;
    showCallPopup = false;
    isStageDisabled = false;
    relatedLeadEdits = {};
    activeTab = 'feedback';
    expectedPaymentDate;
    notifyMe = false;
    @track isListening = false;
    @track interimText = '';

    l1Value = '';
    l2Value = '';
    @track _allL1Options = [];
    @track fullMap = {};
    isL2Disabled = true;

    autoSetFollowUp = true;
    userChangedStage = false;
    showCreateLeadSection = false;

    stageValue = '';
    levelValue = '';
    stageOptions = [];
    levelOptions = [];
    leadRecordTypeId = null;
    recordTypeStageMap = {};
    activeRelatedRecordTypeId = null;
    pendingRelatedRecordTypeIds = [];

    @api autoCall = false;
    hasAutoCalled = false;

    showPopup = false;
    errorText;
    isApiResponseReceived = false;
    recognition;

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
    relatedLeads = [];
    relatedLeadsLoaded = false;
    newLeadCourse = '';
    isCreatingRelatedLead = false;

    showFeedback = false;
    savingFeedback = false;
    feedback = '';
    nextFollowUpDate = null;
    nextFollowUpTime = null;
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
            if (!this.candidateId && data.candidateId) {
                this.candidateId = data.candidateId;
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
                    ? { ...row, stageOptions: this.mergeStageOptions(options, row.stage) }
                    : row
            ));

            this.loadNextRelatedStageOptions();
        } else if (error && this.activeRelatedRecordTypeId) {
            this.loadNextRelatedStageOptions();
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

    get isFeedbackTab() {
        return this.activeTab === 'feedback';
    }

    get showLeadInfoPanel() {
        return this.isFeedbackTab;
    }

    get isLeadTab() {
        return this.isFeedbackTab;
    }

    get isHistoryTab() {
        return this.activeTab === 'history';
    }

    get l1Options() {
        return this._allL1Options || [];
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

    get feedbackTabClass() {
        return `tab-item ${this.activeTab === 'feedback' ? 'active' : ''}`;
    }

    get leadTabClass() {
        return this.feedbackTabClass;
    }

    get contentRowClass() {
        if (this.isFeedbackTab) {
            return 'content-row two-col-layout';
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

    get isEventTab() {
        return this.activeTab === 'event';
    }

    get isDndSpamDisabled() {
        return this.isFeedbackDisabled || this.l1Value !== 'Connected';
    }

    get hasEvents() {
        return (this.eventHistory || []).length > 0;
    }

    get hasRelatedLeads() {
        return (this.relatedLeads || []).length > 0;
    }

    formatLeadInfoSummary(values = [], fallback = 'NA') {
        const uniqueValues = [...new Set((values || []).filter(Boolean))];
        if (uniqueValues.length === 0) {
            return fallback;
        }
        if (uniqueValues.length === 1) {
            return uniqueValues[0];
        }
        return `Multiple (${uniqueValues.length})`;
    }

    get leadInfoCourseDisplay() {
        if (!this.hasRelatedLeads) {
            return this.identity.source || 'NA';
        }

        return this.formatLeadInfoSummary(
            this.relatedLeads.map(row => row.course),
            this.identity.source || 'NA'
        );
    }

    get leadInfoStageDisplay() {
        if (!this.hasRelatedLeads) {
            return this.identity.stage || '--';
        }

        return this.formatLeadInfoSummary(
            this.relatedLeads.map(row => row.stage),
            this.identity.stage || '--'
        );
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

    get isConnectedOnlyFieldsDisabled() {
        return this.l1Value !== 'Connected';
    }

    get disableL2Final() {
        return this.isL2Disabled;
    }

    get isStageFinalDisabled() {
        return this.isStageDisabled || this.isFeedbackDisabled;
    }

    get filteredL1Options() {
        return this.l1Options;
    }

    get commentTextareaClass() {
        return `comment-textarea ${this.isListening ? 'comment-textarea--listening' : ''}`.trim();
    }

    get todayIsoDate() {
        return new Date().toLocaleDateString('en-CA');
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
        const id = event.target.dataset.id;
        const value = event.target.value;

        if (!id) {
            this.expectedPaymentDate = value;
            return;
        }

        this.relatedLeads = this.relatedLeads.map(row => {
            if (row.id === id) return { ...row, expectedPaymentDate: value };
            return row;
        });

        if (id === this.recordId) {
            this.expectedPaymentDate = value;
        }

        this.relatedLeadEdits = {
            ...this.relatedLeadEdits,
            [id]: {
                ...(this.relatedLeadEdits[id] || {}),
                expectedPaymentDate: value
            }
        };
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

    isPastExpectedPaymentDate() {
        const expectedPaymentDate = this.getCurrentLeadExpectedPaymentDate();
        return !!expectedPaymentDate && expectedPaymentDate < this.todayIsoDate;
    }

    getCurrentLeadCourse() {
        const currentLeadRow = (this.relatedLeads || []).find(row => String(row.id) === String(this.recordId));
        return currentLeadRow?.course || this.identity.source || '';
    }

    getCurrentLeadStage() {
        const currentLeadEdit = this.relatedLeadEdits?.[this.recordId];
        if (currentLeadEdit && Object.prototype.hasOwnProperty.call(currentLeadEdit, 'stage')) {
            return currentLeadEdit.stage || '';
        }

        const currentLeadRow = (this.relatedLeads || []).find(row => String(row.id) === String(this.recordId));
        return currentLeadRow?.stage || this.identity.stage || '';
    }

    getNormalizedProgramName() {
        return String(this.getCurrentLeadCourse() || '')
            .trim()
            .toUpperCase()
            .replace(/\s+/g, '');
    }

    isExpectedPaymentDateRequired() {
        const stage = String(this.getCurrentLeadStage() || '').trim().toUpperCase();
        const program = this.getNormalizedProgramName();

        if (!stage || !program) {
            return false;
        }

        if (program.includes('USP') || program.includes('USPATHWAY')) {
            return stage === 'U6';
        }

        if (program.includes('MCOM')) {
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
        const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;

        if (SpeechRecognition) {
            this.recognition = new SpeechRecognition();
            this.recognition.continuous = true;
            this.recognition.interimResults = true;
            this.recognition.lang = 'en-IN';

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

            this.recognition.onerror = () => {
                this.isListening = false;
            };
        }

        this.resolveRecordIdFromPageRef();
        this.loadPicklists();
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

    renderedCallback() {
        const textarea = this.template.querySelector('.comment-textarea');
        if (textarea && !this.isListening && textarea.value !== (this.feedback || '')) {
            textarea.value = this.feedback || '';
        }
    }

    async loadStageAndCourse() {
        try {
            const data = await getStageLevelValues({ recordId: this.recordId });
            if (data.stage) {
                this.stageOptions = data.stage.map(v => ({ label: v, value: v }));
            }
            if (data.level) {
                this.levelOptions = data.level.map(v => ({ label: v, value: v }));
            }
        } catch (e) {
            console.error('Stage/Course load failed:', e);
        }
    }

    mergeStageOptions(options, selectedValue) {
        const normalizedOptions = [...(options || [])];
        if (selectedValue && !normalizedOptions.some(option => option.value === selectedValue)) {
            normalizedOptions.unshift({
                label: selectedValue,
                value: selectedValue
            });
        }
        return normalizedOptions;
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

    handleNewLeadCourseChange(event) {
        this.newLeadCourse = event.detail.value;
    }

    reindexRelatedLeads(rows = []) {
        return rows.map((row, index) => ({
            ...row,
            displayIndex: index + 1
        }));
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
            const data = await getDispositions();

            if (data && data.length > 0) {
                this.processDispositions(data);
            }

        } catch (e) {
            console.error('Picklist load failed:', e);
        }
    }

    async loadRelatedLeads() {
        if (!this.candidateId) {
            this.relatedLeads = [];
            this.relatedLeadsLoaded = true;
            return;
        }

        try {
            const rows = await getRelatedLeads({ candidateId: this.candidateId });

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

    toggleCreateLead() {
        this.showCreateLeadSection = !this.showCreateLeadSection;
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
                    ...(this.relatedLeadEdits[leadId] || {}),
                    stage
                }
            };
        }
    }

    async handleCreateRelatedLead() {
        if (!this.candidateId || !this.newLeadCourse || this.isCreatingRelatedLead) return;

        try {
            this.isCreatingRelatedLead = true;
            const createdCourse = this.newLeadCourse;

            await createRelatedLead({
                candidateId: this.candidateId,
                course: createdCourse,
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
            this.showCreateLeadSection = false;
            this.relatedLeadsLoaded = false;
            await this.loadRelatedLeads();
        } catch (e) {
            this.toast(
                'Create Failed',
                e?.body?.message || e?.message || 'Failed to create lead',
                'error'
            );
        } finally {
            this.isCreatingRelatedLead = false;
        }
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
        if (this.l1Value === 'Not-Connected') {
            this.resetConnectedOnlyFieldsIfNeeded();
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

    handleMicClick() {
        if (this.recognition) {
            this.isListening = true;
            this.recognition.start();
        }
    }

    handleMicStop() {
        if (this.recognition) {
            if (this.interimText) {
                this.feedback = (this.feedback || '') + this.interimText;
                this.interimText = '';
            }

            this.isListening = false;
            this.recognition.stop();
        }
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

    async callApi() {
        this.callButtonDisabled = true;
        this.loading = true;
        this.errorText = null;
        this.isFeedbackDisabled = true;
        this.callStatus = 'Dialing\u2026';
        this.isLive = false;
        this.showFeedback = true;
        this.showCallPopup = true;
        this.l2Value = '';
        this.resetConnectedOnlyFieldsIfNeeded();
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
            this.isFeedbackDisabled = false;
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
        this.isFeedbackDisabled = false;
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
        this.nextFollowUpDate = `${yyyy}-${mm}-${dd}`;
        this.nextFollowUpTime = `${hh}:${mi}`;
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
        const effectiveExpectedPaymentDate = this.getCurrentLeadExpectedPaymentDate();

        if (this.isCommentMandatory && !this.feedback?.trim()) {
            this.toast('Mandatory', 'Feedback comment is required.', 'warning');
            return;
        }
        if (this.l1Value && !this.l2Value) {
            this.toast('Mandatory', 'Sub Status (L2) is required.', 'warning');
            return;
        }
        if (this.isExpectedPaymentDateRequired() && !effectiveExpectedPaymentDate) {
            this.toast('Required', 'Expected Payment Date is mandatory for this stage.', 'error');
            return;
        }
        if (this.isPastExpectedPaymentDate()) {
            this.toast('Required', 'Expected Payment Date cannot be in the past.', 'error');
            return;
        }
        if (this.l1Value === 'Not-Connected') {
            this.resetConnectedOnlyFieldsIfNeeded();
        }
        this.savingFeedback = true;
        try {
            let combinedDateTime = this.nextFollowUpDate
                ? `${this.nextFollowUpDate}T${this.nextFollowUpTime || '10:00'}:00`
                : null;

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
                notifyMe: this.notifyMe,
                isDnd: this.isDnd,
                isSpam: this.isSpam,
                expectedPaymentDate: effectiveExpectedPaymentDate
            };
            await updateCallFeedback({ jsonBody: JSON.stringify(payload) });
            this.toast('Saved', 'Feedback saved successfully.', 'success');

            // 🔥 DISPATCH CUSTOM EVENT
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
                    this.toast('Related Update Failed', e?.body?.message || e?.message || 'Failed to update related leads', 'error');
                }
            }

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
            if (this.autoSetFollowUp) {
                this.setAutoDate24();
            } else {
                this.nextFollowUpDate = null;
                this.nextFollowUpTime = null;
            }
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
        this.isApiResponseReceived = true;
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
        } else {
            this.elapsedLabel = '00:00';
        }
        this.callStatus = 'Ended';
        this.isLive = false;
        this.showCallPopup = false;
        this.stopTimer();
        this.clearFeedbackTimers();
        this.showFeedbackSection();
        this.callButtonDisabled = true;
        this.isFeedbackDisabled = false;
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}