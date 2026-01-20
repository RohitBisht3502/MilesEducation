import { LightningElement, track } from 'lwc';
import processMComEnrollment from '@salesforce/apex/MComBulkUploadController.processMComEnrollment';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class MComBulkUpload extends LightningElement {
    @track fileName = '';
    @track isProcessing = false;
    @track processed = false;
    @track result = {
        successCount: 0,
        errorCount: 0,
        messages: [],
        notFoundEmails: []
    };

    filesUploaded = [];

    handleFileChange(event) {
        if (event.target.files.length > 0) {
            this.filesUploaded = event.target.files;
            this.fileName = event.target.files[0].name;
            this.processed = false; // Reset previous results
        }
    }

    handleProcess() {
        if (this.filesUploaded.length === 0) {
            this.showToast('Error', 'Please select a CSV file first.', 'error');
            return;
        }

        const file = this.filesUploaded[0];
        if (file.size > 2000000) { // Limit to ~2MB just in case
            this.showToast('Error', 'File is too large. Please use a smaller file.', 'error');
            return;
        }

        this.isProcessing = true;

        // Read File
        const reader = new FileReader();
        reader.onload = () => {
            const csvContent = reader.result;
            const emails = this.parseCSV(csvContent);

            if (emails.length === 0) {
                this.showToast('Warning', 'No emails found in the CSV file with header "Email".', 'warning');
                this.isProcessing = false;
                return;
            }

            console.log('Sending emails to Apex: ', emails.length);

            // Call Apex
            processMComEnrollment({ emails: emails })
                .then(result => {
                    this.result = result;
                    this.processed = true;
                    this.showToast('Success', 'Processing completed.', 'success');
                })
                .catch(error => {
                    console.error(error);
                    this.showToast('Error', 'Error processing records: ' + (error.body ? error.body.message : error.message), 'error');
                })
                .finally(() => {
                    this.isProcessing = false;
                });
        };

        reader.onerror = () => {
            this.showToast('Error', 'Error reading file.', 'error');
            this.isProcessing = false;
        };

        reader.readAsText(file);
    }

    parseCSV(content) {
        const lines = content.split(/\r\n|\n/);
        const emails = [];
        let emailColumnIndex = -1;

        if (lines.length < 2) return []; // Need header + data

        // 1. Identify Header
        const headerRow = lines[0].split(',');
        for (let i = 0; i < headerRow.length; i++) {
            // Remove quotes and whitespace
            const header = headerRow[i].replace(/["']/g, "").trim().toLowerCase();
            if (header === 'email' || header === 'email address' || header === 'email__c') {
                emailColumnIndex = i;
                break;
            }
        }

        if (emailColumnIndex === -1) {
            // Fallback: If only one column, assume it's the email
            if (headerRow.length === 1) {
                emailColumnIndex = 0;
            } else {
                return []; // Cannot find email column
            }
        }

        // 2. Extract Data
        for (let i = 1; i < lines.length; i++) {
            const line = lines[i].trim();
            if (!line) continue;

            const cells = line.split(',');
            if (cells.length > emailColumnIndex) {
                let email = cells[emailColumnIndex].trim();
                // Basic clean up of quotes if CSV wrapped them
                email = email.replace(/^"|"$/g, '');

                if (email && email.includes('@')) {
                    emails.push(email);
                }
            }
        }

        return emails;
    }

    get hasMessages() {
        return this.result.messages && this.result.messages.length > 0;
    }

    get hasNotFound() {
        return this.result.notFoundEmails && this.result.notFoundEmails.length > 0;
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: title,
                message: message,
                variant: variant
            })
        );
    }
}