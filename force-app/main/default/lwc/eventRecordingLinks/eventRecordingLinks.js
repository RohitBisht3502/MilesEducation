import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getDownloadUrlForLwc from '@salesforce/apex/EligibilityDatalakeClient.getDownloadUrlForLwc';
import getEventFileInfo from '@salesforce/apex/EventRecordingLinksController.getEventFileInfo';

export default class EventRecordingLinks extends LightningElement {
    @api recordId;

    recordingPath;
    notesPath;
    isLoading = false;

    @wire(getEventFileInfo, { recordId: '$recordId' })
    wiredEvent({ data, error }) {
        if (data) {
            this.recordingPath = data.recordingPath;
            this.notesPath = data.notesPath;
        } else if (error) {
            this.showToast('Error', 'Failed to load Event fields', 'error');
        }
    }

    get disableRecording() {
        return this.isLoading || !this.recordingPath;
    }

    get disableNotes() {
        return this.isLoading || !this.notesPath;
    }

    handleOpenRecording() {
        this.openFile(this.recordingPath, 'Recording');
    }

    handleOpenNotes() {
        this.openFile(this.notesPath, 'Notes');
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
