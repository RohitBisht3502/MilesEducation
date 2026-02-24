import { LightningElement, api, wire } from 'lwc';
import getLeadForWorkitem from '@salesforce/apex/ProcessInstanceLeadService.getLeadForWorkitem';

export default class ProcessInstanceLeadDetails extends LightningElement {
    @api recordId;

    mainLead;
    mergedLead;
    loadError;

    @wire(getLeadForWorkitem, { workitemId: '$recordId' })
    wiredLead({ data, error }) {
        if (data) {
            this.mainLead = data.mainLead;
            this.mergedLead = data.mergedLead;
            this.loadError = undefined;
        } else if (error) {
            this.mainLead = undefined;
            this.mergedLead = undefined;
            this.loadError = error;
        }
    }
}