import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { subscribe, unsubscribe, onError } from 'lightning/empApi';
import updateCallFeedback from '@salesforce/apex/Webservice_RunoAllocationAPI.updateCallFeedback';
import getL1L2Values from '@salesforce/apex/Webservice_RunoAllocationAPI.getL1L2Values';

import {
    getAllUtilityInfo,
    open,
    updateUtility,
    minimize
} from 'lightning/platformUtilityBarApi';

const CHANNEL = '/event/Runo_Call_Completed__e';

export default class RunoCallFeedbackUtility extends LightningElement {
    utilityIdValue;
    pendingOpen = false;

    channelName = CHANNEL;
    subscription = null;

    lastCallId = null;
    lastLeadId = null;
    elapsedLabel = '00:00';

    @track showFeedback = false;
    @track feedback = '';
    @track savingFeedback = false;

    @track l1Value = '';
    @track l2Value = '';
    @track nextFollowUpDate = '';

    @track l1Options = [];
    @track l2Options = [];

    l1L2Map = {};

    connectedCallback() {
        onError(() => {});
        this.initUtilityId();
        this.subscribeToEvents();
        this.loadL1L2Values();
    }

    async loadL1L2Values() {
        try {
            const data = await getL1L2Values();
            this.l1L2Map = data || {};

            this.l1Options = Object.keys(this.l1L2Map).map(key => ({
                label: key.replace('-', ' '),
                value: key
            }));

            // L2 debug root map
            // eslint-disable-next-line no-console
            console.log('L1L2 map from Apex: ', JSON.stringify(this.l1L2Map));
        } catch (e) {
            const msg = e?.body?.message || e?.message || 'Failed to load L1/L2 values';
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Picklist load failed',
                    message: msg,
                    variant: 'error'
                })
            );
        }
    }

    get isL2Disabled() {
        return !this.l1Value;
    }

    handleL1Change(event) {
        this.l1Value = event.detail.value;

        const l2List = this.l1L2Map[this.l1Value] || [];
        this.l2Options = l2List.map(v => ({
            label: v,
            value: v
        }));

        this.l2Value = '';

        // L2 debug for selection
        // eslint-disable-next-line no-console
        console.log('Selected L1: ', this.l1Value);
        // eslint-disable-next-line no-console
        console.log('Available L2 options: ', JSON.stringify(this.l2Options));
    }

    handleL2Change(event) {
        this.l2Value = event.detail.value;
    }

    handleNextFollowUpDateChange(event) {
        this.nextFollowUpDate = event.target.value;
    }

    handleFeedbackChange(event) {
        this.feedback = event.target.value;
    }

    disconnectedCallback() {
        if (this.subscription) {
            unsubscribe(this.subscription, () => {});
        }
    }

    async initUtilityId() {
        try {
            const utils = await getAllUtilityInfo();

            const me =
                utils.find(
                    (u) => u.componentName === 'c__runoCallFeedbackUtility'
                ) ||
                utils.find(
                    (u) => u.utilityLabel === 'Runo Call Feedback Utility'
                );

            if (me) {
                this.utilityIdValue = me.id;

                if (this.pendingOpen) {
                    this.openMyUtility();
                    this.pendingOpen = false;
                }
            }
        } catch {}
    }

    openMyUtility() {
        if (!this.utilityIdValue) {
            this.pendingOpen = true;
            return;
        }

        const id = this.utilityIdValue;

        open(id)
            .then(() => {
                return updateUtility(id, {
                    label: 'Runo Feedback',
                    icon: 'utility:feedback',
                    highlighted: true
                });
            })
            .catch(() => {});
    }

    subscribeToEvents() {
        if (this.subscription) return;

        subscribe(this.channelName, -1, (msg) => this.onRunoEvent(msg))
            .then((resp) => {
                this.subscription = resp;
            })
            .catch(() => {});
    }

    onRunoEvent(msg) {
        const p = (msg && msg.data && msg.data.payload) || {};

        this.lastCallId = p.Call_Id__c || p.callId || null;
        this.lastLeadId = p.Lead_Id__c || null;

        const s = Number(p.Duration_Seconds__c);
        if (!Number.isNaN(s) && s > 0) {
            const totalSec = Math.floor(s);
            const mm = String(Math.floor(totalSec / 60)).padStart(2, '0');
            const ss = String(totalSec % 60).padStart(2, '0');
            this.elapsedLabel = `${mm}:${ss}`;
        } else {
            this.elapsedLabel = '00:00';
        }

        this.showFeedback = true;
        this.feedback = '';
        this.l1Value = '';
        this.l2Value = '';
        this.nextFollowUpDate = '';

        if (this.utilityIdValue) {
            this.openMyUtility();
        } else {
            this.pendingOpen = true;
        }
    }

    async saveFeedback() {
        if (!this.feedback?.trim()) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Feedback required',
                    message: 'Please enter a short call summary.',
                    variant: 'warning'
                })
            );
            return;
        }

        if (!this.lastCallId) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'No Call Id',
                    message: 'Call Id not found from event payload.',
                    variant: 'error'
                })
            );
            return;
        }

        this.savingFeedback = true;

        try {
            await updateCallFeedback({
                leadId: this.lastLeadId,
                callId: this.lastCallId,
                feedback: this.feedback.trim(),
                nextFollowUpDate: this.nextFollowUpDate,
                l1: this.l1Value,
                l2: this.l2Value
            });

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Saved',
                    message: 'Call feedback saved to Call Log.',
                    variant: 'success'
                })
            );

            if (this.utilityIdValue) {
                const id = this.utilityIdValue;
                updateUtility(id, { highlighted: false }).then(() => {
                    minimize(id);
                });
            }

            this.showFeedback = false;
            this.feedback = '';
            this.l1Value = '';
            this.l2Value = '';
            this.nextFollowUpDate = '';
        } catch (e) {
            const msg =
                e?.body?.message ||
                e?.message ||
                'Failed to save feedback';
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Save failed',
                    message: msg,
                    variant: 'error'
                })
            );
        } finally {
            this.savingFeedback = false;
        }
    }

    skip() {
        this.showFeedback = false;
        if (this.utilityIdValue) {
            const id = this.utilityIdValue;
            updateUtility(id, { highlighted: false }).then(() => {
                minimize(id);
            });
        }
    }
}