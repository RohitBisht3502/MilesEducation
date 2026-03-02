import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getRecord } from 'lightning/uiRecordApi';
import getDownloadUrlForLwc from '@salesforce/apex/CallRecordingLinkController.getDownloadUrlForLwc';
import RECORDING_URL_FIELD from '@salesforce/schema/Call_Log__c.Recording_Url__c';

export default class CallrecordingLinks extends LightningElement {
    @api recordId;

    recordingPath;
    isLoading = false;

    @wire(getRecord, { recordId: '$recordId', fields: [RECORDING_URL_FIELD] })
    wiredCallLog({ data, error }) {
        if (data) {
            this.recordingPath = data.fields.Recording_Url__c?.value || null;
        } else if (error) {
            this.showToast('Error', 'Failed to load recording URL', 'error');
        }
    }

    get disableRecording() {
        return this.isLoading || !this.recordingPath;
    }

    handleOpenRecording() {
        this.openFile(this.recordingPath, 'Recording');
    }

    openFile(filePath, label) {
        if (!filePath) {
            this.showToast('Missing Path', `${label} file path is not available.`, 'warning');
            return;
        }

        this.isLoading = true;
        getDownloadUrlForLwc({ filePath })
            .then((url) => {
                if (!url) {
                    this.showToast('Not Found', `${label} URL not available.`, 'error');
                    return;
                }
                window.open(url, '_blank', 'noopener');
            })
            .catch((error) => {
                const message = error?.body?.message || error?.message || 'Failed to get URL';
                this.showToast('Error', message, 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}