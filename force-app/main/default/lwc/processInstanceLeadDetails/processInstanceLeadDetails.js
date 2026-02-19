import { LightningElement, api, wire } from 'lwc';
import getLeadForWorkitem from '@salesforce/apex/ProcessInstanceLeadService.getLeadForWorkitem';

export default class ProcessInstanceLeadDetails extends LightningElement {
    @api recordId;

    leadId;
    leadRecord;
    loadError;


    @wire(getLeadForWorkitem, { workitemId: '$recordId' })
    wiredLead({ data, error }) {
        if (data) {
            this.leadRecord = data;
            this.leadId = data.Id;
            this.loadError = undefined;
        } else if (error) {
            this.leadRecord = undefined;
            this.leadId = undefined;
            this.loadError = error;
        }
    }
}