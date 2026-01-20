import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getRecord } from 'lightning/uiRecordApi';
import appendUrlsCtx from '@salesforce/apex/AWSFileUploaderService.appendUrlsCtx';
import getDownloadLinks from '@salesforce/apex/Callout_AWSFileDownloader.getDownloadLinks';
import { CloseActionScreenEvent } from 'lightning/actions';

export default class FileDownloader extends LightningElement {
  @api recordId;
  @api objectApiName;
  @api uuidFieldApiName = 'UUID__c';
  @api urlsFieldApiName = 'Download_URLs';
  @track loading = false;
  @track lastResultMessage = '';
  uuid;
  @track files = [];


  @wire(getRecord, { recordId: '$recordId', fields: '$computedFields' })
  wiredRecord({ data }) {
    if (data) this.uuid = data.fields[this.uuidFieldApiName]?.value ?? null;
  }

  get computedFields() {
    if (!this.objectApiName || !this.uuidFieldApiName) return [];
    return [`${this.objectApiName}.${this.uuidFieldApiName}`];
  }

  get isDisabled() {
    return !this.recordId || !this.objectApiName || !this.uuid || this.loading;
  }

  async getLinks() {
  if (!this.uuid) {
    this.toast(
      'Error',
      `UUID field "${this.uuidFieldApiName}" is empty on this ${this.objectApiName} record.`,
      'error'
    );
    return;
  }

  this.loading = true;
  this.lastResultMessage = '';
  this.files = []; // reset list

  try {
    const data = await getDownloadLinks({ uuid: this.uuid });

    const items = [];
    for (const k of Object.keys(data || {})) {
      const url = data[k];
  if (url && url.startsWith('http')) {
      items.push({ name: k, url: data[k] });
    }
    }

    if (items.length === 0) {
      this.lastResultMessage = 'No files found.';
      this.toast('Info', this.lastResultMessage, 'info');
    } else {
      // 🔹 IMPORTANT: set files for UI rendering
      this.files = items;

      // optional: still save HTML to field
      await appendUrlsCtx({
        objectApiName: this.objectApiName,
        recordId: this.recordId,
        items,
        urlsFieldApiName: this.urlsFieldApiName,
        context: 'download'
      });

      this.lastResultMessage = `Fetched ${items.length} download link(s).`;
      this.toast('Success', this.lastResultMessage, 'success');
    }
  } catch (e) {
    this.toast('Error', e?.body?.message || e.message, 'error');
  } finally {
    this.loading = false;
  }
}




openFile(event) {
    const url = event.currentTarget.dataset.url;

    const a = document.createElement('a');
    a.href = url;
    a.target = '_blank';
    a.download = '';  
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
}



  toast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }
}