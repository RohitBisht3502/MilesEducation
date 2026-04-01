import { api, LightningElement, track, wire } from 'lwc';
import { loadStyle } from 'lightning/platformResourceLoader';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import openSansFont from '@salesforce/resourceUrl/openSansFont';

import getNavData from '@salesforce/apex/SobjectNavBarController.getNavData';
import getIconDates from '@salesforce/apex/NavBarDateService.getIconDates';
import ROADMAP_IMG from '@salesforce/resourceUrl/Roadmap';
import GMEET_IMG from '@salesforce/resourceUrl/Gmeet';
import OFFICE_VISIT_IMG from '@salesforce/resourceUrl/OfficeVisitLight';
import MILES_ONE_IMG from '@salesforce/resourceUrl/MILES_ONE_IMG';
import CAIRA_WEBINAR_IMG from '@salesforce/resourceUrl/CAIRAwebinar';

import allocateLeadNow from '@salesforce/apex/Webservice_RunoAllocationAPI.allocateLeadNow';
import updateCallFeedback from '@salesforce/apex/Webservice_RunoAllocationAPI.updateCallFeedback';
import getDispositions from '@salesforce/apex/CallDispositionConfigService.getDispositions';
import getIdentity from '@salesforce/apex/RunoCallIdentityService.getIdentity';
import getCallHistory from '@salesforce/apex/Webservice_RunoAllocationAPI.getCallHistory';
// import getStageLevelValues from '@salesforce/apex/Webservice_RunoAllocationAPI.getStageLevelValues';
import { getPicklistValuesByRecordType }
    from 'lightning/uiObjectInfoApi';
import getSupplementaryData from '@salesforce/apex/RunoCallSupplementaryService.getSupplementaryData';
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



export default class RunoAllocationCallsCopy extends NavigationMixin(LightningElement) {

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


    activeTab = 'lead';

    // Supplementary data
    supplementaryLoaded = false;
    courseStages = [];
    lastCall = null;
    conversations = [];
    enquiries = [];

    // Dummy data for design (to be removed later)
    @track dummyQualifications = [
        { id: '1', type: 'UG', title: 'B.Com', university: 'Mumbai University', year: '2020', isEditing: false },
        { id: '2', type: 'PG', title: 'M.Com', university: 'Delhi University', year: '2022', isEditing: false }
    ];
    @track dummyCertifications = [
        { id: '1', name: 'CPA', status: 'In Progress', isEditing: false },
        { id: '2', name: 'CMA', status: 'Completed', isEditing: false }
    ];
    @track dummyWorkExperience = [
        { id: '1', company: 'Deloitte', role: 'Audit Associate', period: 'Jan 2021 - Dec 2022', isEditing: false },
        { id: '2', company: 'EY', role: 'Staff Accountant', period: 'Jan 2023 - Present', isEditing: false }
    ];
    _editBackup = {};
    _nextDummyId = 100;


    // Nav bar source/engagement data — DUMMY DATA FOR TESTING (remove later)
    @track iconTabs = [];
    @track pillTabs = [];
    @track latestSource = '';
    iconDates = {};
    _dummyNavLoaded = false;

    // Tooltip state (JS-driven to avoid overflow clipping)
    @track showNavTooltip = false;
    @track navTooltipText = '';
    @track navTooltipStyle = '';

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
    callTitle = '';

    get candidateIdDisplay() {
        return this.identity?.canId || '';
    }

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
    isRecording = false;
    _recognition = null;

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
            this.callTitle = data.name || 'Calling via Runo';
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
                this.loadSupplementaryData();
            }
        } else if (error) {
            this.errorText = error?.body?.message || 'Failed to load identity';
            console.error('wiredIdentity error', error);
        }
    }

    // ─── Nav data wire (source/engagement) ───
    @wire(getNavData, { recordId: '$recordId' })
    wiredNavData({ data, error }) {
        if (this._dummyNavLoaded) return; // DUMMY guard — remove later
        if (!this.recordId) return;
        if (data) {
            const iconSourceSet = new Set([
                'caira webinar', 'zoom webinar', 'online', 'offline',
                'gmeet online', 'gmeet visit', 'miles one app'
            ]);

            const iconUrlMap = {
                'caira webinar': CAIRA_WEBINAR_IMG,
                'zoom webinar': ROADMAP_IMG,
                'online': GMEET_IMG,
                'offline': OFFICE_VISIT_IMG,
                'gmeet online': GMEET_IMG,
                'gmeet visit': OFFICE_VISIT_IMG,
                'miles one app': MILES_ONE_IMG
            };

            const iconLabelMap = {
                'caira webinar': 'CAIRA Webinar',
                'zoom webinar': 'Roadmap Webinar',
                'online': 'Gmeet Online',
                'offline': 'Gmeet Visit',
                'gmeet online': 'Gmeet Online',
                'gmeet visit': 'Gmeet Visit',
                'miles one app': 'Miles One App'
            };

            const icons = [];
            const pills = [];

            (data.enquiry || [])
                .filter(item => item && item.source && item.source.trim() !== '')
                .forEach(item => {
                    const normalized = (item.source || '').toLowerCase();
                    if (iconSourceSet.has(normalized)) {
                        const lbl = iconLabelMap[normalized] || item.source;
                        const dt = this.iconDates[lbl] || null;
                        icons.push({
                            name: item.source,
                            label: lbl,
                            iconUrl: iconUrlMap[normalized],
                            tooltipDate: dt,
                            tooltipText: dt ? `${lbl} — ${dt}` : lbl
                        });
                    } else {
                        pills.push({
                            name: item.source,
                            label: this.formatSourceLabel(item.source),
                            count: item.count > 1 ? item.count : null
                        });
                    }
                });

            this.iconTabs = icons;
            this.pillTabs = pills;
            this.latestSource = this.formatSourceLabel(data.latestSource || '');
        } else if (error) {
            console.error('NavData wire error:', error);
        }
    }

    @wire(getIconDates, { recordId: '$recordId' })
    wiredIconDates({ data, error }) {
        if (this._dummyNavLoaded) return; // DUMMY guard — remove later
        if (data) {
            const formatted = {};
            const dtFmt = new Intl.DateTimeFormat('en-IN', {
                day: '2-digit', month: 'short', year: 'numeric',
                hour: '2-digit', minute: '2-digit'
            });
            for (const key of Object.keys(data)) {
                formatted[key] = dtFmt.format(new Date(data[key]));
            }
            this.iconDates = formatted;

            // Merge dates into existing iconTabs
            if (this.iconTabs.length > 0) {
                this.iconTabs = this.iconTabs.map(tab => {
                    const dt = formatted[tab.label] || tab.tooltipDate || null;
                    return {
                        ...tab,
                        tooltipDate: dt,
                        tooltipText: dt ? `${tab.label} — ${dt}` : tab.label
                    };
                });
            }
        } else if (error) {
            console.error('IconDates wire error:', error);
        }
    }

    get showRingingAnimation() {
        return !this.showFeedback && this.callStatus !== 'Idle';
    }

    get hasNavData() {
        return (this.iconTabs && this.iconTabs.length > 0) || (this.pillTabs && this.pillTabs.length > 0) || !!this.latestSource;
    }

    get hasIconTabs() {
        return this.iconTabs && this.iconTabs.length > 0;
    }

    get hasPillTabs() {
        return this.pillTabs && this.pillTabs.length > 0;
    }

    formatSourceLabel(source) {
        const normalized = (source || '').toLowerCase();
        if (normalized === 'online') return 'GMEET';
        if (normalized === 'offline') return 'GVISIT';
        return source;
    }

    handleNavImageError(event) {
        const tabName = event.target.dataset.name;
        if (!tabName) return;

        // Move failed icon tab to pill tabs
        const failedTab = this.iconTabs.find(t => t.name === tabName);
        if (failedTab) {
            this.iconTabs = this.iconTabs.filter(t => t.name !== tabName);
            this.pillTabs = [
                ...this.pillTabs,
                { name: failedTab.name, label: failedTab.label, count: failedTab.count }
            ];
        }
    }

    handleIconMouseEnter(event) {
        const text = event.currentTarget.dataset.tooltip;
        if (!text) return;

        const rect = event.currentTarget.getBoundingClientRect();
        const headerEl = this.template.querySelector('.custom-header');
        if (!headerEl) return;
        const headerRect = headerEl.getBoundingClientRect();

        // Position tooltip below the icon, relative to .custom-header
        const left = rect.left - headerRect.left + rect.width / 2;
        const top = rect.bottom - headerRect.top + 6;

        this.navTooltipText = text;
        this.navTooltipStyle = `left:${left}px;top:${top}px;`;
        this.showNavTooltip = true;
    }

    handleIconMouseLeave() {
        this.showNavTooltip = false;
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
        } else if (error) {
            console.error('Stage load error', error);
        }
    }
    connectedCallback() {
        this.loadDispositionConfig();
        // this.loadStageLevel();
        this.subscribeToEvents();
        this.loadUntrackedStatus();
        this._loadDummyNavData(); // DUMMY — remove later
        onError(err => console.warn('EMP API Error:', JSON.stringify(err)));
    }

    // ── DUMMY NAV DATA FOR TESTING (remove this entire method later) ──
    _loadDummyNavData() {
        if (this._dummyNavLoaded) return;
        this._dummyNavLoaded = true;

        this.iconTabs = [
            { name: 'CAIRA Webinar',  label: 'CAIRA Webinar',  iconUrl: CAIRA_WEBINAR_IMG, tooltipDate: '15 Mar 2026, 10:00 AM', tooltipText: 'CAIRA Webinar — 15 Mar 2026, 10:00 AM' },
            { name: 'Zoom Webinar',   label: 'Roadmap Webinar', iconUrl: ROADMAP_IMG,       tooltipDate: '12 Mar 2026, 02:30 PM', tooltipText: 'Roadmap Webinar — 12 Mar 2026, 02:30 PM' },
            { name: 'Gmeet Online',   label: 'Gmeet Online',   iconUrl: GMEET_IMG,         tooltipDate: '10 Mar 2026, 11:00 AM', tooltipText: 'Gmeet Online — 10 Mar 2026, 11:00 AM' },
            { name: 'Gmeet Visit',    label: 'Gmeet Visit',    iconUrl: OFFICE_VISIT_IMG,  tooltipDate: '08 Mar 2026, 04:00 PM', tooltipText: 'Gmeet Visit — 08 Mar 2026, 04:00 PM' },
            { name: 'Miles One App',  label: 'Miles One App',  iconUrl: MILES_ONE_IMG,     tooltipDate: '20 Mar 2026, 09:15 AM', tooltipText: 'Miles One App — 20 Mar 2026, 09:15 AM' }
        ];

        this.pillTabs = [
            { name: 'Google Ads',   label: 'Google Ads',   count: 4 },
            { name: 'Facebook',     label: 'Facebook',     count: 2 },
            { name: 'Website',      label: 'Website',      count: null }
        ];

        this.latestSource = 'Google Ads';
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

    handleViewCandidate() {
        if (!this.candidateId) return;
        this[NavigationMixin.GenerateUrl]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this.candidateId,
                objectApiName: 'Lead',
                actionName: 'view'
            }
        }).then(url => {
            window.open(url, '_blank');
        });
    }

    handleTabClick(event) {
        this.activeTab = event.currentTarget.dataset.tab;
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
            loadStyle(this, openSansFont)
                .catch(err => console.error('Failed to load Open Sans font', err));
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





    get leadTabClass() {
        return `tab-item ${this.activeTab === 'lead' ? 'active' : ''}`;
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
        
        // Keep the currently selected value visible in the combobox.
        if (this.l1Value === 'Not-Connected') {
            return this.l1Options;
        }

        // After API response → remove Not-Connected for manual changes.
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

    applySystemL1Change(value) {
        this.l1Value = value;
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

    handleL1Change() {
        // L1 is system-controlled in this component and only changes via internal flow.
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

    formatFollowUpDateForSave() {
        if (!this.nextFollowUpDate) {
            return null;
        }

        let value = String(this.nextFollowUpDate).trim();
        if (!value) {
            return null;
        }

        if (/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(value)) {
            value = `${value}:00`;
        }

        return value.replace('T', ' ');
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
        this.applySystemL1Change('Not-Connected');
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
                    this.applySystemL1Change('Not-Connected');

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
                nextFollowUpDate: this.formatFollowUpDateForSave(),
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
            this.savingFeedback = false;

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
            this.savingFeedback = false;
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
            await getCallHistory({
                recordId: this.candidateId
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

        const s = Number(
            p.Duration_Seconds__c ||
            p.Duration__c ||
            p.durationSeconds
        );

        if (!Number.isNaN(s) && s > 0) {
            this.applySystemL1Change('Connected');
        } else {
            this.applySystemL1Change('Not-Connected');

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
        return true;
    }
    get disableL2Final() {

        return this.isL2Disabled;
    }
    get statusPillClass() {
        const status = (this.callStatus || '').toLowerCase();
        if (status.includes('connecting') || status.includes('in call') || status.includes('dialing')) return 'status-pill live';
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

    // ─── Supplementary data getters ───
    get hasCourseStages() {
        return this.courseStages && this.courseStages.length > 0;
    }

    get hasLastCall() {
        return this.lastCall != null;
    }

    // Dummy conversations for design testing (to be removed later)
    _dummyConversations = [
        { id: 'dummy-1', dateLabel: '18 Mar 2026, 02:30 pm', calledBy: 'Vishy', l1: 'Connected', l2: 'Interested', course: 'CMA', stage: 'M3', feedback: 'Candidate is interested in CMA. Requested a callback after 2 days to discuss payment options.' },
        { id: 'dummy-2', dateLabel: '15 Mar 2026, 11:15 am', calledBy: 'Priya', l1: 'Connected', l2: 'Follow Up', course: 'CPA', stage: 'M5', feedback: 'Spoke briefly, candidate was busy at work. Asked to call back next week.' },
        { id: 'dummy-3', dateLabel: '10 Mar 2026, 04:45 pm', calledBy: 'Vishy', l1: 'Not-Connected', l2: 'Busy', course: 'CMA', stage: 'M1', feedback: 'Call went unanswered. Will retry tomorrow.' }
    ];

    get hasEnquiries() {
        return this.enquiries && this.enquiries.length > 0;
    }

    get hasConversations() {
        return this.displayConversations && this.displayConversations.length > 0;
    }

    get displayConversations() {
        if (this.conversations && this.conversations.length > 0) {
            return this.conversations;
        }
        return this._dummyConversations;
    }

    get lastCallDateLabel() {
        if (!this.lastCall || !this.lastCall.startTime) return 'NA';
        return new Intl.DateTimeFormat('en-IN', {
            day: '2-digit', month: 'short', year: 'numeric',
            hour: '2-digit', minute: '2-digit'
        }).format(new Date(this.lastCall.startTime));
    }

    get lastCallDurationLabel() {
        if (!this.lastCall) return '00:00';
        const totalSec = Number(this.lastCall.durationSeconds || 0);
        const mm = String(Math.floor(totalSec / 60)).padStart(2, '0');
        const ss = String(totalSec % 60).padStart(2, '0');
        return `${mm}:${ss}`;
    }

    get hasQualifications() {
        return this.dummyQualifications && this.dummyQualifications.length > 0;
    }

    get hasCertifications() {
        return this.dummyCertifications && this.dummyCertifications.length > 0;
    }

    get hasWorkExperience() {
        return this.dummyWorkExperience && this.dummyWorkExperience.length > 0;
    }

    // ─── Load supplementary data ───
    async loadSupplementaryData() {
        if (this.supplementaryLoaded || !this.candidateId) return;

        try {
            const data = await getSupplementaryData({
                candidateId: this.candidateId,
                studentId: this.identity?.studentId || null
            });

            if (data) {
                this.courseStages = (data.courseStages || []).map(cs => ({
                    id: cs.id,
                    course: cs.course || 'NA',
                    stage: cs.stage || 'NA',
                    label: `${cs.course || 'NA'}: ${cs.stage || 'NA'}`
                }));

                this.lastCall = data.lastCall || null;

                const dateFmt = new Intl.DateTimeFormat('en-IN', {
                    day: '2-digit', month: 'short', year: 'numeric',
                    hour: '2-digit', minute: '2-digit'
                });

                this.conversations = (data.conversations || []).map(c => ({
                    id: c.id,
                    dateLabel: c.callDate ? dateFmt.format(new Date(c.callDate)) : 'NA',
                    calledBy: c.calledBy || 'Unknown',
                    feedback: c.feedback || '',
                    l1: c.l1 || '',
                    l2: c.l2 || '',
                    course: c.course || '',
                    stage: c.stage || ''
                }));

                const enquiryDateFmt = new Intl.DateTimeFormat('en-IN', {
                    day: '2-digit', month: 'short', year: 'numeric',
                    hour: '2-digit', minute: '2-digit'
                });

                this.enquiries = (data.enquiries || []).map(e => ({
                    id: e.id,
                    dateLabel: e.enquiryDate ? enquiryDateFmt.format(new Date(e.enquiryDate)) : 'NA',
                    source: e.source || 'Unknown'
                }));
            }

            this.supplementaryLoaded = true;
        } catch (e) {
            console.error('Supplementary data load failed:', e);
            this.supplementaryLoaded = true;
        }
    }

    // ─── Editable row handlers (for dummy data sections) ───
    _getSectionArray(section) {
        if (section === 'qualification') return 'dummyQualifications';
        if (section === 'certification') return 'dummyCertifications';
        if (section === 'workExperience') return 'dummyWorkExperience';
        return null;
    }

    handleEditRow(event) {
        const id = event.currentTarget.dataset.id;
        const section = event.currentTarget.dataset.section;
        const prop = this._getSectionArray(section);
        if (!prop) return;

        // Backup original values
        const item = this[prop].find(r => r.id === id);
        if (item) {
            this._editBackup[`${section}_${id}`] = { ...item };
        }

        this[prop] = this[prop].map(r =>
            r.id === id ? { ...r, isEditing: true } : r
        );
    }

    handleSaveRow(event) {
        const id = event.currentTarget.dataset.id;
        const section = event.currentTarget.dataset.section;
        const prop = this._getSectionArray(section);
        if (!prop) return;

        this[prop] = this[prop].map(r =>
            r.id === id ? { ...r, isEditing: false } : r
        );
        delete this._editBackup[`${section}_${id}`];
    }

    handleCancelRow(event) {
        const id = event.currentTarget.dataset.id;
        const section = event.currentTarget.dataset.section;
        const prop = this._getSectionArray(section);
        if (!prop) return;

        const backupKey = `${section}_${id}`;
        const backup = this._editBackup[backupKey];

        if (backup) {
            this[prop] = this[prop].map(r =>
                r.id === id ? { ...backup, isEditing: false } : r
            );
            delete this._editBackup[backupKey];
        } else {
            // New row with no backup — remove it
            this[prop] = this[prop].filter(r => r.id !== id);
        }
    }

    handleDeleteRow(event) {
        const id = event.currentTarget.dataset.id;
        const section = event.currentTarget.dataset.section;
        const prop = this._getSectionArray(section);
        if (!prop) return;

        this[prop] = this[prop].filter(r => r.id !== id);
    }

    handleFieldChange(event) {
        const id = event.currentTarget.dataset.id;
        const field = event.currentTarget.dataset.field;
        const section = event.currentTarget.dataset.section;
        const prop = this._getSectionArray(section);
        if (!prop) return;

        this[prop] = this[prop].map(r =>
            r.id === id ? { ...r, [field]: event.target.value } : r
        );
    }

    handleAddRow(event) {
        const section = event.currentTarget.dataset.section;
        const prop = this._getSectionArray(section);
        if (!prop) return;

        this._nextDummyId++;
        const newId = String(this._nextDummyId);
        let newRow;

        if (section === 'qualification') {
            newRow = { id: newId, type: '', title: '', university: '', year: '', isEditing: true };
        } else if (section === 'certification') {
            newRow = { id: newId, name: '', status: '', isEditing: true };
        } else {
            newRow = { id: newId, company: '', role: '', period: '', isEditing: true };
        }

        this[prop] = [...this[prop], newRow];
    }

    // ─── Speech-to-Text (Dictation) ───
    get micBtnClass() {
        return this.isRecording ? 'mic-btn recording' : 'mic-btn';
    }

    get micIcon() {
        return this.isRecording ? 'utility:stop' : 'utility:unmuted';
    }

    get micTooltip() {
        return this.isRecording ? 'Stop dictation' : 'Start dictation';
    }

    get commentsMandatoryStar() {
        return this.isCommentMandatory ? ' *' : '';
    }

    handleMicToggle() {
        if (this.isRecording) {
            this._stopRecognition();
            return;
        }

        const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;
        if (!SpeechRecognition) {
            this.toast('Unsupported', 'Speech recognition is not supported in this browser.', 'error');
            return;
        }

        this._feedbackBeforeMic = this.feedback || '';

        this._recognition = new SpeechRecognition();
        this._recognition.lang = 'en-US';
        this._recognition.interimResults = true;
        this._recognition.continuous = true;

        this._recognition.onresult = (e) => {
            let finalText = '';
            let interimText = '';
            for (let i = 0; i < e.results.length; i++) {
                const t = e.results[i][0].transcript;
                if (e.results[i].isFinal) {
                    finalText += t;
                } else {
                    interimText += t;
                }
            }
            const combined = (finalText + interimText).trim();
            this.feedback = this._feedbackBeforeMic
                ? this._feedbackBeforeMic + ' ' + combined
                : combined;
        };

        this._recognition.onerror = (e) => {
            console.error('Speech recognition error', e.error);
            this.isRecording = false;
            this._recognition = null;
        };

        this._recognition.onend = () => {
            this.isRecording = false;
            this._recognition = null;
            this._feedbackBeforeMic = null;
        };

        this._recognition.start();
        this.isRecording = true;
    }

    _stopRecognition() {
        if (this._recognition) {
            this._recognition.stop();
        }
    }

}