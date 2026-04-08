import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getRecord } from 'lightning/uiRecordApi';
import getDownloadUrlForLwc from '@salesforce/apex/EligibilityDatalakeClient.getDownloadUrlForLwc';
import FILE_PATH_FIELD from '@salesforce/schema/Student_File_Status__c.File_Path__c';

export default class GpFilesStatusView extends LightningElement {
    @api recordId;

    filePath;
    isLoading = false;

    @wire(getRecord, { recordId: '$recordId', fields: [FILE_PATH_FIELD] })
    wiredStudentFileStatus({ data, error }) {
        if (data) {
            this.filePath = data.fields.File_Path__c?.value || null;
        } else if (error) {
            this.showToast('Error', 'Failed to load GP file path.', 'error');
        }
    }

    get disableOpenFile() {
        return this.isLoading || !this.filePath;
    }

    handleOpenFile() {
        if (!this.filePath) {
            this.showToast('Missing Path', 'GP file path is not available.', 'warning');
            return;
        }

        this.isLoading = true;
        getDownloadUrlForLwc({ filePath: this.filePath })
            .then((url) => {
                if (!url) {
                    this.showToast('Not Found', 'GP file URL not available.', 'error');
                    return;
                }
                window.open(url, '_blank', 'noopener');
            })
            .catch((error) => {
                const message = error?.body?.message || error?.message || 'Failed to get GP file URL.';
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