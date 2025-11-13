import { api, LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import allocateLeadNow from '@salesforce/apex/Webservice_RunoAllocationAPI.allocateLeadNow';
import updateCallFeedback from '@salesforce/apex/Webservice_RunoAllocationAPI.updateCallFeedback';
import getIdentity from '@salesforce/apex/RunoCallIdentityService.getIdentity';
import { CloseActionScreenEvent } from 'lightning/actions';
import { subscribe, unsubscribe, onError } from 'lightning/empApi';

export default class RunoAllocationCall extends LightningElement {
  @api recordId;

  loading = false;
  resultText;
  errorText;

  channelName = '/event/Runo_Call_Completed__e';
  subscription = null;

  identity = { name: '', email: '', phone: '', city: '', source: '' };

  isLive = false;
  callStatus = 'Idle';
  callTitle = 'Calling via Runo';
  elapsedMs = 0;
  elapsedLabel = '00:00';
  timerId = null;

  showFeedback = false;
  feedback = '';
  savingFeedback = false;
  lastCallId = null;

  connectedCallback() {
    onError(() => {});
    this.subscribeToEvents();
    this.loadIdentity();
  }

  disconnectedCallback() {
    if (this.subscription) unsubscribe(this.subscription, () => {});
    this.stopTimer();
  }

  async loadIdentity() {
    try {
      const dto = await getIdentity({ recordId: this.recordId });
      this.identity = {
        name: dto?.name || '',
        email: dto?.email || '',
        phone: dto?.phone || '',
        city: dto?.city || '',
        source: dto?.source || ''
      };
    } catch {
      this.identity = { name: '', email: '', phone: '', city: '', source: '' };
    }
  }

  subscribeToEvents() {
    if (this.subscription) return;
    subscribe(this.channelName, -1, (msg) => this.onRunoEvent(msg))
      .then((resp) => { this.subscription = resp; })
      .catch(() => {});
  }

  onRunoEvent(msg) {
    const p = (msg && msg.data && msg.data.payload) || {};

    // Match only this lead or the exact call made from this LWC
    const evtCallId = p.Call_Id__c || p.callId || null;
    const evtLeadId = p.Lead_Id__c || null;

    const leadMatch = evtLeadId === this.recordId;
    const callMatch = this.lastCallId && evtCallId === this.lastCallId;
    if (!leadMatch && !callMatch) {
      return; // Ignore events for other leads
    }

    this.callStatus = 'Ended';
    this.isLive = false;
    this.stopTimer();
    this.showFeedback = true;

    const s = Number(p.Duration_Seconds__c);
    if (!Number.isNaN(s) && s > 0) this.setElapsed(s * 1000);
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

  close() {
    this.dispatchEvent(new CloseActionScreenEvent());
  }

  async callApi() {
    this.loading = true;
    this.errorText = undefined;
    this.resultText = undefined;
    this.showFeedback = false;

    this.callStatus = 'Dialing…';
    this.isLive = false;
    this.setElapsed(0);
    this.startTimer();

    try {
      const res = await allocateLeadNow({ leadId: this.recordId });
      let parsed;
      try { parsed = (typeof res === 'string') ? JSON.parse(res) : res; } catch {}
      this.lastCallId = parsed?.callId || parsed?.data?.callId || null;
      this.callTitle = parsed?.displayName || 'Calling via Runo';

      this.callStatus = 'In Call…';
      this.isLive = true;
      this.resultText = res || 'Success';

      this.dispatchEvent(new ShowToastEvent({
        title: 'Runo Allocation',
        message: 'Lead sent successfully.',
        variant: 'success'
      }));
    } catch (e) {
      const msg = e?.body?.message || e?.message || 'Failed';
      this.errorText = msg;
      this.callStatus = 'Failed to Dial';
      this.isLive = false;
      this.stopTimer();
      this.dispatchEvent(new ShowToastEvent({
        title: 'Runo Allocation failed',
        message: msg,
        variant: 'error'
      }));
    } finally {
      this.loading = false;
    }
  }

  handleFeedbackChange(e) {
    this.feedback = e.target.value;
  }

  async saveFeedback() {
    if (!this.feedback?.trim()) {
      this.dispatchEvent(new ShowToastEvent({
        title: 'Feedback required',
        message: 'Please enter a short call summary.',
        variant: 'warning'
      }));
      return;
    }
    this.savingFeedback = true;
    try {
      await updateCallFeedback({
        leadId: this.recordId,
        callId: this.lastCallId,
        feedback: this.feedback.trim()
      });
      this.dispatchEvent(new ShowToastEvent({
        title: 'Saved',
        message: 'Call feedback saved to Call Log.',
        variant: 'success'
      }));
      setTimeout(() => this.close(), 800);
    } catch (e) {
      const msg = e?.body?.message || e?.message || 'Failed to save feedback';
      this.dispatchEvent(new ShowToastEvent({
        title: 'Save failed',
        message: msg,
        variant: 'error'
      }));
    } finally {
      this.savingFeedback = false;
    }
  }
}
