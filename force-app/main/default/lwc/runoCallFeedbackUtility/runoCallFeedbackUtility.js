import { api, LightningElement, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import updateCallFeedback from '@salesforce/apex/Webservice_RunoAllocationAPI.updateCallFeedback';
import getIdentity from '@salesforce/apex/RunoCallIdentityService.getIdentity';
import getStageLevelValues from '@salesforce/apex/Webservice_RunoAllocationAPI.getStageLevelValues';
import getDispositions from '@salesforce/apex/CallDispositionConfigService.getDispositions';
import { CloseActionScreenEvent } from 'lightning/actions';
import { subscribe, unsubscribe, onError } from 'lightning/empApi';
import {
    getAllUtilityInfo,
    open,
    updateUtility,
    minimize
} from 'lightning/platformUtilityBarApi';

const CHANNEL = '/event/Runo_Call_Completed__e';
const COMPONENT_NAME = 'c__runoCallFeedbackUtility';
const UTILITY_LABEL = 'Runo Call Feedback Utility';

export default class RunoCallFeedbackUtility extends LightningElement {
    @api recordId;

    // Lead id used for identity + feedback (either recordId or id from event)
    leadIdForIdentity;

    // L1 / L2
    l1Value = '';
    l2Value = '';
    l1Options = [];
    l2Options = [];
    fullMap = {};
    isL2Disabled = true;

    // Stage / Level
    stageValue = '';
    levelValue = '';
    stageOptions = [];
    levelOptions = [];

    // Identity
    identity = {
        name: '',
        email: '',
        phone: '',
        city: '',
        source: '',
        stage: '',
        level: ''
    };

    // Feedback
    showFeedback = false;
    savingFeedback = false;
    feedback = '';
    nextFollowUpDate = null;

    // Duration label for template
    elapsedLabel = '';

    // Comment box rules
    showCommentBox = false;
    isCommentMandatory = false;
    dispositionData = [];
    commentRuleMap = {};
    lastCallId = null;
    subscription = null;
    errorText;

    get isSaveDisabled() {
        return this.savingFeedback || !this.showFeedback;
    }

    connectedCallback() {
    this.leadIdForIdentity = this.recordId || null;

    this.loadDispositions();
    this.subscribeToEvents();

  
    this.loadStageLevel();

    if (this.leadIdForIdentity) {
        this.showFeedback = true;
        this.loadIdentity();
    }
}

    disconnectedCallback() {
        if (this.subscription) {
            unsubscribe(this.subscription, () => {
                console.log('Unsubscribed from RUNO events.');
            });
            this.subscription = null;
        }
    }

    //     // 🔹 Wire uses leadIdForIdentity (can be set by recordId OR platform event)
    //     @wire(getIdentity, { recordId: '$leadIdForIdentity' })
    // // wiredIdentity({ data, error }) {
    // //     if (data) {
    // //         this.identity = data;

    // //         if (data.stage) this.stageValue = data.stage;
    // //         if (data.level) this.levelValue = data.level;
    // //       // ALWAYS reload picklists when identity loads
    // //         this.loadStageLevel();
    // //     } 
    // //     else if (error) {
    // //         this.errorText = error?.body?.message || 'Failed to load identity';
    // //     }
    // // }

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

 async loadIdentity() {
    if (!this.leadIdForIdentity) {
        return;
    }

    try {
        const data = await getIdentity({
            recordId: this.leadIdForIdentity
        });

        if (data) {
            this.identity = data;

            await this.loadStageLevel();

            this.stageValue = data.stage || '';
            this.levelValue = data.level || '';
        }

    } catch (error) {
        console.error('Identity load failed:', error);
        this.errorText = error?.body?.message || 'Failed to load identity';
    }
}

    async loadStageLevel() {
    try {
        const mapData = await getStageLevelValues({
            recordId: this.leadIdForIdentity || this.recordId
        });

        console.log('StageLevel Response:', mapData);

        this.stageOptions = [];
        this.levelOptions = [];

        if (mapData && mapData.stage) {
            this.stageOptions = mapData.stage.map(v => ({
                label: v,
                value: v
            }));
        }

        if (mapData && mapData.level) {
            this.levelOptions = mapData.level.map(v => ({
                label: v,
                value: v
            }));
        }

    } catch (error) {
        console.error('Stage/Level load failed:', error);
    }
}

    updateCommentVisibility() {
        const key = `${this.l1Value}:${this.l2Value}`;
        this.isCommentMandatory = this.commentRuleMap[key] === true;
    }

    handleL1Change(e) {
        this.l1Value = e.target.value;
        this.l2Options = (this.fullMap[this.l1Value] || []).map(v => ({
            label: v,
            value: v
        }));
        this.isL2Disabled = this.l2Options.length === 0;
        this.l2Value = '';
        this.updateCommentVisibility();
    }

    handleL2Change(e) {
        this.l2Value = e.target.value;
        this.updateCommentVisibility();
    }

    handleStageChange(e) {
        this.stageValue = e.target.value;
    }

    handleLevelChange(e) {
        this.levelValue = e.target.value;
    }

    handleFeedbackChange(e) {
        this.feedback = e.target.value;
    }

    handleNextFollowUpDateChange(e) {
        this.nextFollowUpDate = e.target.value;
    }

    close() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

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

    handleSaveClick() {
        this.saveFeedback(false);
    }

    async saveFeedback(isAuto = false) {
        if (this.isCommentMandatory && !this.feedback?.trim()) {
            this.toast(
                isAuto ? 'Auto-save failed' : 'Mandatory',
                'Feedback comment is required.',
                'warning'
            );
            return;
        }

        this.savingFeedback = true;

        try {
            await updateCallFeedback({
    jsonBody: JSON.stringify({
        recordId: this.leadIdForIdentity || this.recordId,
        callId: this.lastCallId,
        feedback: this.feedback?.trim(),
        nextFollowUpDate: this.nextFollowUpDate,
        l1: this.l1Value,
        l2: this.l2Value,
        stage: this.stageValue,
        level: this.levelValue,
        notifyMe: false,
        isDnd: false,
        isSpam: false
    })
});

            this.toast(
                isAuto ? 'Auto Saved' : 'Saved',
                isAuto ? 'Feedback auto-saved.' : 'Feedback saved successfully.',
                'success'
            );

            this.feedback = '';
            this.showFeedback = false;

            this.closeUtilityItem();
        } catch (e) {
            this.toast(
                'Save Failed',
                e?.body?.message || e?.message || 'Failed to save feedback.',
                'error'
            );
        } finally {
            this.savingFeedback = false;
        }
    }


    async loadDispositions() {
        try {
            const data = await getDispositions();
            this.dispositionData = data;

            const l1Set = new Set();
            const l1L2Map = {};
            const commentMap = {};

            data.forEach(row => {
                l1Set.add(row.l1);

                if (!l1L2Map[row.l1]) {
                    l1L2Map[row.l1] = [];
                }

                if (row.l2 && !l1L2Map[row.l1].includes(row.l2)) {
                    l1L2Map[row.l1].push(row.l2);
                }

                const key = `${row.l1}:${row.l2}`;
                commentMap[key] = row.commentNeeded === true;
            });

            this.l1Options = [...l1Set].map(v => ({
                label: v,
                value: v
            }));

            this.fullMap = l1L2Map;
            this.commentRuleMap = commentMap;

        } catch (e) {
            console.error('Disposition load failed:', e);
        }
    }
    subscribeToEvents() {
        if (this.subscription) return;

        subscribe(CHANNEL, -1, msg => this.onRunoEvent(msg))
            .then(resp => {
                this.subscription = resp;
                console.log('Subscribed to RUNO events');
            })
            .catch(err => {
                console.error('Subscribe failed: ', err);
            });
    }

    onRunoEvent(msg) {
        debugger;
        const p = (msg && msg.data && msg.data.payload) || {};

        const callType = p.Type__c || p.Type || null;
        if (callType && String(callType).toLowerCase() === 'outgoing') {
            return;
        }

        const evtLeadId = p.Lead_Id__c || p.LeadId__c || p.leadId || null;
        const evtCandidateId = p.Candidate_Id__c || p.CandidateId__c || p.candidateId || null;
        const evtCallId = p.Call_Id__c || p.CallId__c || p.callId || null;

    
        if (
            this.recordId &&
            evtLeadId &&
            String(evtLeadId) !== String(this.recordId)
        ) {
            return;
        }

        if (evtLeadId) {
           this.leadIdForIdentity = evtLeadId;
            this.loadIdentity();
        }
        else if (evtCandidateId) {

            this.leadIdForIdentity = evtCandidateId;
            this.loadIdentity();
        }

        this.showFeedbackSection();

        if (evtCallId) {
            this.lastCallId = String(evtCallId);
        }

        if (p.Duration_Label__c) {
            this.elapsedLabel = p.Duration_Label__c;
        }

        this.openUtilityItem();
        this.showFeedbackSection();
    }

    openUtilityItem() {
        getAllUtilityInfo()
            .then(utils => {
                const me =
                    utils.find(u => u.componentName === COMPONENT_NAME) ||
                    utils.find(u => u.utilityLabel === UTILITY_LABEL);

                if (me) {
                    return open(me.id, { autoFocus: true });
                }
                return null;
            })
            .catch(err => {
                console.error('Failed to open utility:', err);
            });
    }

    closeUtilityItem() {
        getAllUtilityInfo()
            .then(utils => {
                const me =
                    utils.find(u => u.componentName === COMPONENT_NAME) ||
                    utils.find(u => u.utilityLabel === UTILITY_LABEL);

                if (me) {
                    return updateUtility(me.id, {
                        highlighted: false
                    }).then(() => {
                        minimize(me.id);
                    });
                }
                return null;
            })
            .catch(err => {
                console.error('Failed to minimize utility:', err);
            });
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