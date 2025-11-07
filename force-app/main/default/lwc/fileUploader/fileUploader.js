import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getRecord } from 'lightning/uiRecordApi';
import appendUrls from '@salesforce/apex/AWSFileUploaderService.appendUrls';
import getPresignedUrlApex from '@salesforce/apex/Webservice_AWSFileUploader.getPresignedUrl';

export default class FileUploader extends LightningElement {
  @api recordId;
  @api objectApiName;
  @api uuidFieldApiName = 'UUID__c';
  @api urlsFieldApiName = 'URLs';

  @track uploading = false;
  @track lastResultMessage = '';
  files = [];
  uuid;

  @wire(getRecord, { recordId: '$recordId', fields: '$computedFields' })
  wiredRecord({ data }) {
    if (data) this.uuid = data.fields[this.uuidFieldApiName]?.value ?? null;
  }

  get computedFields() {
    if (!this.objectApiName || !this.uuidFieldApiName) return [];
    return [`${this.objectApiName}.${this.uuidFieldApiName}`];
  }

  get isUploadDisabled() {
    return !this.recordId || !this.uuid || this.files.length === 0 || this.uploading;
  }

  handleFileChange(e) {
    this.files = Array.from(e.target.files || []);
    this.lastResultMessage = '';
  }

  async upload() {
    if (!this.uuid) {
      this.toast('Error', `UUID field "${this.uuidFieldApiName}" is empty on this ${this.objectApiName} record.`, 'error');
      return;
    }
    if (!this.files.length) return;

    this.uploading = true;
    this.lastResultMessage = '';
    const successItems = [];
    let success = 0, failed = 0;

    for (const file of this.files) {
      try {
        const presignedUrl = await getPresignedUrlApex({
          fileName: file.name,
          uuid: this.uuid,
          contentType: file.type || 'application/octet-stream'
        });

        await this.putToS3(presignedUrl, file, file.type || 'application/octet-stream');

        successItems.push({ name: file.name, url: presignedUrl });
        success += 1;
      } catch (e) {
        failed += 1;
        // eslint-disable-next-line no-console
        console.error('Upload failed:', e);
      }
    }

    if (successItems.length) {
      try {
        await appendUrls({
          objectApiName: this.objectApiName,
          recordId: this.recordId,
          items: JSON.stringify(successItems),
          urlsFieldApiName: this.urlsFieldApiName
        });
        this.toast('Success', 'Files uploaded and full URLs saved successfully.', 'success');
      } catch (error) {
        // eslint-disable-next-line no-console
        console.error('Error saving URLs:', error);
        this.toast('Warning', 'Files uploaded but failed to save full URLs.', 'warning');
      }
    }

    this.uploading = false;
    this.lastResultMessage = `Uploaded: ${success} | Failed: ${failed}`;
    this.toast(failed === 0 ? 'Success' : 'Partial Success', this.lastResultMessage, failed === 0 ? 'success' : 'warning');
  }

  async putToS3(url, file, contentType) {
    const res = await fetch(url, { method: 'PUT', headers: { 'Content-Type': contentType }, body: file });
    if (!res.ok) throw new Error('S3 upload failed');
  }

  toast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }
}