import { api, LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import allocateLeadNow from '@salesforce/apex/Webservice_RunoAllocationAPI.allocateLeadNow';
import { CloseActionScreenEvent } from 'lightning/actions';

export default class RunoAllocationCall extends LightningElement {
  @api recordId; 
  loading = false;
  resultText;
  errorText;

  close() {
    this.dispatchEvent(new CloseActionScreenEvent());
  }

  async callApi() {
    this.loading = true;
    this.resultText = undefined;
    this.errorText = undefined;
    try {
      const res = await allocateLeadNow({ leadId: this.recordId });
      this.resultText = res || 'Success';
      this.dispatchEvent(
        new ShowToastEvent({
          title: 'Runo Allocation',
          message: 'Lead sent successfully.',
          variant: 'success'
        })
      );
      setTimeout(() => this.close(), 800);
    } catch (e) {
      const msg = (e && e.body && e.body.message) ? e.body.message : (e && e.message) ? e.message : 'Failed';
      this.errorText = msg;
      this.dispatchEvent(
        new ShowToastEvent({
          title: 'Runo Allocation failed',
          message: msg,
          variant: 'error'
        })
      );
    } finally {
      this.loading = false;
    }
  }
}