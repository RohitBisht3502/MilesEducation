import { api, LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import createUSPPathwayLead from '@salesforce/apex/USPPathwayLeadService.createUSPPathwayLead';

export default class UspPathwayLeadAction extends LightningElement {
    @api recordId;
    isLoading = false;

    async handleCreate() {
        if (this.isLoading) return;
        this.isLoading = true;

        try {
            await createUSPPathwayLead({ accountId: this.recordId });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Success',
                    message: 'US Pathway lead created successfully.',
                    variant: 'success'
                })
            );
            this.dispatchEvent(new CloseActionScreenEvent());
        } catch (e) {
            const message =
                e?.body?.message ||
                e?.message ||
                'Failed to create US Pathway lead.';
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message,
                    variant: 'error'
                })
            );
        } finally {
            this.isLoading = false;
        }
    }
}