import { api, LightningElement, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import updateCallFeedback from '@salesforce/apex/Webservice_RunoAllocationAPI.updateCallFeedback';
import getL1L2Values from '@salesforce/apex/Webservice_RunoAllocationAPI.getL1L2Values';
import getIdentity from '@salesforce/apex/RunoCallIdentityService.getIdentity';
import getStageLevelValues from '@salesforce/apex/Webservice_RunoAllocationAPI.getStageLevelValues';

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

    lastCallId = null;
    subscription = null;
    errorText;

    get isSaveDisabled() {
        return this.savingFeedback || !this.showFeedback;
    }

    connectedCallback() {
        // 🔹 Use recordId initially if utility was opened from a record
        this.leadIdForIdentity = this.recordId || null;

        this.loadPicklists();
        this.loadStageLevel();
        this.subscribeToEvents();
        onError(() => {});
    }

    disconnectedCallback() {
        if (this.subscription) {
            unsubscribe(this.subscription, () => {
                console.log('Unsubscribed from RUNO events.');
            });
            this.subscription = null;
        }
    }

    // 🔹 Wire uses leadIdForIdentity (can be set by recordId OR platform event)
    @wire(getIdentity, { recordId: '$leadIdForIdentity' })
    wiredIdentity({ data, error }) {
        if (data) {
            this.identity = data;
            if (data.stage) this.stageValue = data.stage;
            if (data.level) this.levelValue = data.level;
        } else if (error) {
            this.errorText = error?.body?.message || 'Failed to load identity';
        }
    }

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
        } catch (e) {
            console.error('Stage/Level load failed:', e);
        }
    }

    updateCommentVisibility() {
        const key = `${this.l1Value}:${this.l2Value}`;
        this.isCommentMandatory = this.mandatoryCommentRules[key] === true;
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
                // 🔹 Use leadId from event if available, fallback to recordId
                leadId: this.leadIdForIdentity || this.recordId,
                callId: this.lastCallId,
                feedback: this.feedback?.trim(),
                nextFollowUpDate: this.nextFollowUpDate,
                l1: this.l1Value,
                l2: this.l2Value,
                stage: this.stageValue,
                level: this.levelValue
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
        const evtCallId = p.Call_Id__c || p.CallId__c || p.callId || null;

        // 🔹 If component was opened from a record, keep old protection.
        if (
            this.recordId &&
            evtLeadId &&
            String(evtLeadId) !== String(this.recordId)
        ) {
            return;
        }

        // 🔹 Use lead id from event for identity + save
        if (evtLeadId) {
            this.leadIdForIdentity = evtLeadId;
        }

        if (evtCallId) {
            this.lastCallId = String(evtCallId);
        }

        // Optional: if event has a duration label, you can populate it
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