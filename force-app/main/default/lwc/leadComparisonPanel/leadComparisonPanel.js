import { LightningElement, api, wire, track } from 'lwc';
import getComparisonDetails from '@salesforce/apex/LeadMergeController.getComparisonDetails';

export default class LeadComparisonPanel extends LightningElement {
    @api recordId;
    @track comparisonData;
    @track error;
    @track isLoading = true;

    @wire(getComparisonDetails, { approvalId: '$recordId' })
    wiredComparison({ error, data }) {
        this.isLoading = true;
        if (data) {
            this.comparisonData = data;
            this.error = undefined;
            this.isLoading = false;
        } else if (error) {
            this.error = error.body ? error.body.message : error.message;
            this.comparisonData = undefined;
            this.isLoading = false;
        }
    }
}