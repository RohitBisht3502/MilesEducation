import { api, LightningElement, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import allocateLeadNow from '@salesforce/apex/Webservice_RunoAllocationAPI.allocateLeadNow';
import updateCallFeedback from '@salesforce/apex/Webservice_RunoAllocationAPI.updateCallFeedback';
import getDispositions from '@salesforce/apex/CallDispositionConfigService.getDispositions';
import getIdentity from '@salesforce/apex/RunoCallIdentityService.getIdentity';
import getRelatedLeads from '@salesforce/apex/RunoCallIdentityService.getRelatedLeads';
import updateRelatedLeadStages from '@salesforce/apex/RunoCallIdentityService.updateRelatedLeadStages';
import createRelatedLead from '@salesforce/apex/RunoCallIdentityService.createRelatedLead';
// import getStageLevelValues from '@salesforce/apex/Webservice_RunoAllocationAPI.getStageLevelValues';
import getCallHistory from '@salesforce/apex/Webservice_RunoAllocationAPI.getCallHistory';
import { getPicklistValuesByRecordType }
    from 'lightning/uiObjectInfoApi';
import getWebinarMembers from '@salesforce/apex/Webservice_RunoAllocationAPI.getWebinarMembers';
import getLeadEvents from '@salesforce/apex/Webservice_RunoAllocationAPI.getLeadEvents';
import { NavigationMixin } from 'lightning/navigation';
import getLatestUntrackedCallLog
    from '@salesforce/apex/Webservice_RunoAllocationAPI.getLatestUntrackedCallLog';
import { getObjectInfo, getPicklistValues }
    from 'lightning/uiObjectInfoApi';
import LEAD_OBJECT from '@salesforce/schema/Lead__c';
import STAGE_FIELD from '@salesforce/schema/Lead__c.Stage__c';
import { getRecord } from 'lightning/uiRecordApi';
import RECORDTYPE_FIELD from '@salesforce/schema/Lead__c.RecordTypeId';



import { CloseActionScreenEvent } from 'lightning/actions';
import { subscribe, unsubscribe, onError } from 'lightning/empApi';



export default class RunoAllocationCalls extends NavigationMixin(LightningElement) {

    @api recordId;
    @api isCallLog;
    isApiResponseReceived = false;
    @api isQueuePaused;
    @api isQueueRunning;
    _primaryTag = null;
    @api
    get primaryTag() {
        return this._primaryTag;
    }
    set primaryTag(value) {
        this._primaryTag = value;
    }
    @api candidateId;
    // isHistoryTab = true;
    objectInfo;

    hasRendered = false;
    isStageDisabled = false;

    // UI / state
    loading = false;
    disableCancel = false;
    recordTypeId;
    callButtonLabel = 'Call Runo';
    callButtonDisabled = false;


    // Call popup overlay (Calling Runo...)
    showCallPopup = false;

    callLogId = null;
    showTagLead = false;
    allStageValues = [];



    userChangedStage = false;

    l1Value = '';
    l2Value = '';
    l1Options = [];
    l2Options = [];

    isL2Disabled = true;

    autoSetFollowUp = true;
    callHistory = [];


    activeTab = 'lead';

    webinarHistory = [];
    webinarLoaded = false;

    eventHistory = [];
    eventLoaded = false;

    relatedLeads = [];
    relatedLeadsLoaded = false;
    relatedLeadEdits = {};
    newLeadCourse = '';
    newLeadEmail = '';
    isCreatingRelatedLead = false;

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
        canId: '',
        createdDate: '',
        mhpTag: '',
        leadOwner: ''
    };

    isDnd = false;
    isSpam = false;
    recordTypeStageMap = {};

    // call state
    isLive = false;
    callStatus = 'Idle';
    callTitle = 'Calling via Runo';

    elapsedMs = 0;
    elapsedLabel = '00:00';
    timerId = null;
    showTagLeadUI = false;


    openTagLeadUI() {
        this.showTagLeadUI = true;
    }
    dynamicRecordTypeId;

    showFeedback = false;
    savingFeedback = false;
    feedback = '';
    nextFollowUpDate = null;
    expectedDate = null;
    notifyMe = false;

    handleNotifyChange(event) {
        this.notifyMe = event.target.checked;
    }


    lastCallId = null;

    canEndCall = false;
    CALL_NO_RESPONSE_MS = 30000;
    noResponseTimer = null;



    handleDndChange(e) {
        this.isDnd = e.target.checked;
    }

    handleSpamChange(e) {
        this.isSpam = e.target.checked;
    }

    // mandatory comment logic
    showCommentBox = true;
    isCommentMandatory = false;
    dispositionConfigMap = {};
    l1L2Map = {};

    // ---------------- WIRE ----------------
    @wire(getIdentity, { recordId: '$recordId' })
    wiredIdentity({ data, error }) {
        if (data) {
            this.identity = data;
            if (data.stage) this.stageValue = data.stage;
            if (data.level) this.levelValue = data.level;
            // if (!this.stageOptions.length) {
            //     this.loadStageLevel();
            // }
            if (!this.candidateId && data.candidateId) {
                this.candidateId = data.candidateId;
                console.log('Candidate Id:', this.candidateId);
            }

            if (this.candidateId) {
                this.loadCallHistory();
            }
        } else if (error) {
            this.errorText = error?.body?.message || 'Failed to load identity';
            console.error('wiredIdentity error', error);
        }
    }

    @wire(getRecord, {
        recordId: '$recordId',
        fields: [RECORDTYPE_FIELD]
    })
    wiredLead({ data, error }) {
        if (data) {
            this.recordTypeId = data.fields.RecordTypeId.value;
        } else if (error) {
            console.error('Error fetching RecordTypeId', error);
        }
    }







    @wire(getObjectInfo, { objectApiName: LEAD_OBJECT })
    wiredObjectInfo({ data, error }) {
        if (data) {
            this.objectInfo = data;
            if (!this.recordTypeId && data.defaultRecordTypeId) {
                this.recordTypeId = data.defaultRecordTypeId;
            }
            const rts = Object.values(data.recordTypeInfos || {});
            this.levelOptions = rts
                .filter(rt => rt.available && !rt.master)
                .map(rt => ({ label: rt.name, value: rt.name }));
        } else if (error) {
            console.error('Object info error', error);
        }
    }



    openTagLeadUI() {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordAction',
            attributes: {
                recordId: this.recordId,
                actionName: 'Tag_Lead'
            }
        });
    }



    @wire(getPicklistValues, {
        recordTypeId: '$recordTypeId',
        fieldApiName: STAGE_FIELD
    })
    wiredStageValues({ data, error }) {
        if (data) {
            this.stageOptions = data.values.map(v => ({
                label: v.label,
                value: v.value
            }));
            if (this.relatedLeadsLoaded) {
                this.relatedLeads = (this.relatedLeads || []).map(r => ({
                    ...r,
                    stageOptions: this.stageOptions
                }));
            }
        } else if (error) {
            console.error('Stage load error', error);
        }
    }
    connectedCallback() {
        this.loadDispositionConfig();
        // this.loadStageLevel();
        this.loadCallHistory();
        this.subscribeToEvents();
        this.loadUntrackedStatus();
        onError(err => console.warn('EMP API Error:', JSON.stringify(err)));
    }

    disconnectedCallback() {
        this.stopTimer();
        this.clearFeedbackTimers();
        if (this.subscription) {
            try {
                unsubscribe(this.subscription, () => { });
            } catch (e) {
                console.warn('unsubscribe failed', e);
            }
            this.subscription = null;
        }
    }


    get isLeadTab() { return this.activeTab === 'lead'; }
    get isHistoryTab() { return this.activeTab === 'history'; }
    get isWebinarTab() { return this.activeTab === 'webinar'; }
    get isEventTab() { return this.activeTab === 'event'; }
    get isRelatedTab() { return this.activeTab === 'related'; }

    get hasWebinarHistory() {
        return (this.webinarHistory || []).length > 0;
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
            !this.newLeadEmail ||
            this.availableCourseOptions.length === 0 ||
            this.isCreatingRelatedLead
        );
    }


    handleNewLeadEmailChange(event) {
        this.newLeadEmail = event.target.value;
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

    handleTabClick(event) {
        const selectedTab = event.currentTarget.dataset.tab;
        this.activeTab = selectedTab;



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

   async loadRelatedLeads() {
    if (!this.candidateId) {
        this.relatedLeads = [];
        this.relatedLeadsLoaded = true;
        return;
    }

    try {
        const rows = await getRelatedLeads({
            candidateId: this.candidateId
        });

        this.relatedLeads = (rows || []).map(r => {
            return {
                id: r.id,
                course: r.course || 'NA',
                stage: r.stage || '',
                stageOptions: this.stageOptions
            };
        });

        this.relatedLeadsLoaded = true;

    } catch (e) {
        console.error('Related leads load failed:', e);
        this.relatedLeads = [];
        this.relatedLeadsLoaded = true;
    }
}
    // async loadStageOptionsForRecordType(recordTypeId) {
    //     if (this.recordTypeStageMap[recordTypeId]) {
    //         return this.recordTypeStageMap[recordTypeId];
    //     }

    //     const result = await getPicklistValuesByRecordType({
    //         objectApiName: LEAD_OBJECT,
    //         recordTypeId: recordTypeId
    //     });

    //     const stageField = result.picklistFieldValues.Stage__c;

    //     const options = (stageField?.values || []).map(v => ({
    //         label: v.label,
    //         value: v.value
    //     }));

    //     this.recordTypeStageMap = {
    //         ...this.recordTypeStageMap,
    //         [recordTypeId]: options
    //     };

    //     return options;
    // }


    handleRelatedStageChange(event) {
        const leadId = event.currentTarget.dataset.id;
        const stage = event.detail.value;

        this.relatedLeads = (this.relatedLeads || []).map(r => {
            if (r.id === leadId) {
                return { ...r, stage };
            }
            return r;
        });

        if (leadId) {
            this.relatedLeadEdits = { ...this.relatedLeadEdits, [leadId]: stage };
        }
    }

    handleNewLeadCourseChange(event) {
        this.newLeadCourse = event.detail.value;
    }

    async handleCreateRelatedLead() {
        if (!this.candidateId || !this.newLeadCourse || !this.newLeadEmail || this.isCreatingRelatedLead) return;

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

    async loadUntrackedStatus() {
        if (!this.recordId) return;

        try {
            const id = await getLatestUntrackedCallLog({ leadId: this.recordId });

            this.callLogId = id;
            this.showTagLead = id !== null;

        } catch (e) {
            console.error('Failed loading untracked status', e);
            this.showTagLead = false;
        }
    }

    async loadDispositionConfig() {
        try {
            const data = await getDispositions();

            const l1Set = new Set();
            const tempL1L2Map = {};
            const tempCommentMap = {};

            (data || []).forEach(row => {

                if (!row.l1) return;

                // Collect L1
                l1Set.add(row.l1);

                // Build L1 → L2 mapping
                if (!tempL1L2Map[row.l1]) {
                    tempL1L2Map[row.l1] = new Set();
                }
                if (row.l2) {
                    tempL1L2Map[row.l1].add(row.l2);
                }

                // Build Comment Mandatory map
                const key = `${row.l1}:${row.l2}`;
                tempCommentMap[key] = row.commentNeeded === true;
            });

            // Convert L1 to options
            this.l1Options = [...l1Set].map(v => ({
                label: v,
                value: v
            }));

            // Convert L1L2 map sets to arrays
            this.l1L2Map = {};
            Object.keys(tempL1L2Map).forEach(l1 => {
                this.l1L2Map[l1] = [...tempL1L2Map[l1]];
            });

            // Save comment rules
            this.dispositionConfigMap = tempCommentMap;

            console.log('Disposition metadata loaded successfully');

        } catch (e) {
            console.error('Disposition metadata load failed:', e);
        }
    }





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

            this.nextFollowUpDate = null;
        }
    }


    // async loadStageLevel() {
    //     if (!this.recordId) return;

    //     try {
    //         const mapData = await getStageLevelValues({
    //             recordId: this.recordId
    //         });

    //         this.stageOptions = (mapData.stage || []).map(v => ({
    //             label: v,
    //             value: v
    //         }));

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

        const rows = await getLeadEvents({ recordId: this.recordId });

        this.eventHistory = (rows || []).map(r => ({
            id: r.id,
            subject: r.subject,
            attendance: r.attendance || 'NA'
        }));

        this.eventLoaded = true;
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


    get hasCallHistory() {
        return (this.callHistory || []).length > 0;
    }



    get leadTabClass() {
        return `tab-item ${this.activeTab === 'lead' ? 'active' : ''}`;
    }

    get historyTabClass() {
        return `tab-item ${this.activeTab === 'history' ? 'active' : ''}`;
    }

    get webinarTabClass() {
        return `tab-item ${this.activeTab === 'webinar' ? 'active' : ''}`;
    }

    get eventTabClass() {
        return `tab-item ${this.activeTab === 'event' ? 'active' : ''}`;
    }

    get relatedTabClass() {
        return `tab-item ${this.activeTab === 'related' ? 'active' : ''}`;
    }

    get showRelatedTab() {
        return !!this.candidateId;
    }
    get normalizedPrimaryTag() {
        const raw = (this.primaryTag || '').trim().toLowerCase();
        return raw.replace(/[^a-z]/g, '');
    }

    get isUntrackedCall() {
        const tag = this.normalizedPrimaryTag;

        if (tag.includes('untracked')) return true;


        if (tag.includes('ne') || tag.includes('noteligible')) return false;

        if (tag.includes('missed')) return false;

        return this.isCallLog === true && !this.candidateId;
    }

    get filteredL1Options() {
        if (!this.isApiResponseReceived) {
            return this.l1Options;
        }

        // After API response → remove Not-Connected
        return (this.l1Options || []).filter(
            opt => opt.value !== 'Not-Connected'
        );
    }

    get isMissedCall() {
        const tag = this.normalizedPrimaryTag;

        if (tag.includes('missed')) return true;


        if (tag.includes('ne') || tag.includes('noteligible')) return true;

        if (tag.includes('untracked')) return false;

        return this.isCallLog === true && !!this.candidateId;
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




    updateCommentVisibility() {
        const key = `${this.l1Value}:${this.l2Value}`;
        this.isCommentMandatory = this.dispositionConfigMap[key] === true;
    }

    handleL1Change(e) {
        this.l1Value = e.target.value;
        this.userChangedStage = false;

        const l2List = this.l1L2Map[this.l1Value] || [];

        this.l2Options = l2List.map(v => ({
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

        this.resetConnectedOnlyFieldsIfNeeded();

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

    handleLevelChange(event) {
        this.levelValue = event.detail.value;

        if (!this.objectInfo?.recordTypeInfos) return;

        const matchedRt = Object.values(this.objectInfo.recordTypeInfos)
            .find(rt => rt.name.trim() === this.levelValue.trim());

        if (matchedRt) {
            this.recordTypeId = matchedRt.recordTypeId;
            this.stageValue = null;   // reset stage
        }
    }
    handleFeedbackChange(e) {
        this.feedback = e.target.value;
    }

    handleNextFollowUpDateChange(e) {
        if (this.autoSetFollowUp) return;
        const dateVal = e.target.value;
        if (!dateVal) {
            this.nextFollowUpDate = null;
            return;
        }
        const timeVal = this.nextFollowUpTimeOnly || '00:00';
        this.nextFollowUpDate = `${dateVal}T${timeVal}`;
    }

    handleNextFollowUpTimeChange(e) {
        if (this.autoSetFollowUp) return;
        const timeVal = e.target.value;
        if (!timeVal) {
            return;
        }
        const dateVal = this.nextFollowUpDateOnly || new Date().toISOString().slice(0, 10);
        this.nextFollowUpDate = `${dateVal}T${timeVal}`;
    }

    handleExpectedDateChange(e) {
        this.expectedDate = e.target.value;
    }

    get todayIsoDate() {
        return new Date().toLocaleDateString('en-CA');
    }

    get isConnectedOnlyFieldsDisabled() {
        return this.disableUntilApi || this.l1Value !== 'Connected';
    }

    resetConnectedOnlyFieldsIfNeeded() {
        if (this.l1Value === 'Connected') {
            return;
        }

        this.expectedDate = null;
        this.notifyMe = false;
        this.isDnd = false;
        this.isSpam = false;
    }

    isPastExpectedPaymentDate() {
        return !!this.expectedDate && this.expectedDate < this.todayIsoDate;
    }

    getNormalizedProgramName() {
        return String(this.levelValue || this.identity?.level || '')
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

    close() {
        try {
            this.dispatchEvent(new CloseActionScreenEvent());
        } catch (err) {
            console.warn('CloseActionScreenEvent dispatch failed (ignored):', err);
        }
    }

    @api
    startCall() {
        if (!this.recordId) {
            console.warn('startCall: missing recordId');
            return;
        }
        this.callApi();
    }


    async callApi() {
        this.callButtonDisabled = true;
        this.loading = true;
        this.errorText = null;
        this.isApiResponseReceived = false;
        this.l1Value = 'Not-Connected';
        this.handleL1Change({ target: { value: this.l1Value } });
        if (this.l2Options.length > 0) {
            this.l2Value = this.l2Options[0].value;
        }
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
                    this.l1Value = 'Not-Connected';
                    this.handleL1Change({ target: { value: this.l1Value } });

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






    // showLeadTab() {
    //     this.isLeadTab = true;
    //     this.isHistoryTab = false;
    // }

    // showHistoryTab() {
    //     this.isLeadTab = false;
    //     this.isHistoryTab = true;
    // }




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
    async saveFeedback(options = {}) {
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
        if (this.isExpectedPaymentDateRequired() && !this.expectedDate) {
            this.toast('Required', 'Expected Payment Date is mandatory for this stage.', 'warning');
            return false;
        }
        if (this.isPastExpectedPaymentDate()) {
            this.toast('Required', 'Expected Payment Date cannot be in the past.', 'warning');
            return false;
        }
        if (this.l1Value === 'Not-Connected') {
            this.stageValue = null;
            this.resetConnectedOnlyFieldsIfNeeded();
        }

        this.savingFeedback = true;
        console.log('Saving feedback, callId = ', this.lastCallId);


        try {

            const payload = {

                recordId: this.recordId,
                callId: this.lastCallId,
                feedback: this.feedback?.trim(),
                nextFollowUpDate: this.nextFollowUpDate,
                l1: this.l1Value,
                l2: this.l2Value,
                level: this.levelValue,
                expectedPaymentDate: this.expectedDate,
                notifyMe: this.notifyMe,
                isDnd: this.isDnd,
                isSpam: this.isSpam
            };
            if (this.stageValue && String(this.stageValue).trim()) {
                payload.stage = this.stageValue;
            }
            await updateCallFeedback({
                jsonBody: JSON.stringify(payload)
            });

            this.toast('Saved', 'Feedback saved successfully.', 'success');

            await this.loadCallHistory();
            await this.loadUntrackedStatus();

            // Save related lead stage edits (if any)
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
                    this.toast('Related Update Failed', e?.body?.message || e?.message || 'Failed to update related leads', 'error');
                }
            }




            const eventDetail = {
                recordId: this.recordId,
                callId: this.lastCallId,
                feedback: this.feedback?.trim() || '',
                nextFollowUpDate: this.nextFollowUpDate || null,
                l1: this.l1Value || '',
                l2: this.l2Value || '',
                stage: this.stageValue || '',
                level: this.levelValue || '',
                stopQueue: options.stopQueue === true
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
            this.relatedLeadEdits = {};

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


    async loadCallHistory() {
    if (!this.candidateId) return;

    try {
        const rows = await getCallHistory({
            recordId: this.candidateId
        });

        console.log('Call History rows:', rows);

        const dateFmt = new Intl.DateTimeFormat('en-IN', {
            day: '2-digit',
            month: 'short',
            year: 'numeric'
        });

        const timeFmt = new Intl.DateTimeFormat('en-IN', {
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

    get disablePauseBtnFinal() {
        return (
            this.isQueuePaused ||
            !this.showFeedback
        );
    }
    async handlePauseQueue() {
        const saved = await this.saveFeedback({ stopQueue: true });
        if (!saved) {
            return;
        }
        this.dispatchEvent(
            new CustomEvent('pausequeue', {
                bubbles: true,
                composed: true

            })
        );
    }
    async handleResumeQueue() {
        const saved = await this.saveFeedback();
        if (!saved) {
            return;
        }
        this.dispatchEvent(
            new CustomEvent('resumequeue', {
                detail: { stopQueue: true },
                bubbles: true,
                composed: true
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
        this.isApiResponseReceived = true;

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

            //  CONNECTED CASE
            this.l1Value = 'Connected';
            this.handleL1Change({ target: { value: this.l1Value } });

        } else {

            //  NOT CONNECTED CASE
            this.l1Value = 'Not-Connected';
            this.handleL1Change({ target: { value: this.l1Value } });

            // AUTO SELECT L2 WHEN DURATION = 0
            if (this.l2Options.length > 0) {
                this.l2Value = this.l2Options[0].value;
            }
        }

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
            this.loadCallHistory();

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

    get disablePauseBtn() {
        return !this.isLive;
    }

    get disableSaveDispositionBtn() {
        return this.savingFeedback || !this.showFeedback;
    }

    get panelHeader() {
        return `Calling via Runo | ${this.callStatus} | ${this.elapsedLabel}`;
    }



    get disableUntilApi() {
        return !this.isApiResponseReceived;
    }

    get disableFollowUpDateTime() {
        return this.disableUntilApi || this.autoSetFollowUp;
    }

    get nextFollowUpDateOnly() {
        if (!this.nextFollowUpDate) return '';
        const val = String(this.nextFollowUpDate);
        return val.includes('T') ? val.split('T')[0] : val;
    }

    get nextFollowUpTimeOnly() {
        if (!this.nextFollowUpDate) return '';
        const val = String(this.nextFollowUpDate);
        if (!val.includes('T')) return '';
        return val.split('T')[1].slice(0, 5);
    }

    get disableL1() {
        return !this.isApiResponseReceived;
    }
    get disableL2Final() {

        return this.isL2Disabled;
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