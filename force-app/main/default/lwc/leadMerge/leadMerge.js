import { LightningElement, track, api } from 'lwc';
import searchLeads from '@salesforce/apex/LeadMergeController.searchLeads';
import submitMergeForApproval from '@salesforce/apex/LeadMergeController.submitMergeForApproval';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class LeadMerge extends LightningElement {
    @api recordId; // Current Lead record ID
    searchKey = '';
    @track leads = [];
    @track selectedLeads = []; // Array to store multiple selected leads

    handleChange(event) {
        this.searchKey = event.target.value;
    }

    handleSearch() {
        if (!this.searchKey) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: "Warning",
                    message: "Please enter a search value",
                    variant: "warning"
                })
            );
            return;
        }

        // Get IDs of already selected leads
        const selectedLeadIds = this.selectedLeads.map(lead => lead.Id);

        searchLeads({ 
            searchKey: this.searchKey, 
            currentLeadId: this.recordId,
            selectedLeadIds: selectedLeadIds 
        })
            .then(result => {
                this.leads = result.map(lead => ({
                    ...lead,
                    ownerName: lead.Owner ? lead.Owner.Name : 'Unknown',
                    cardStyle: 'border: 1px solid #e4e7ec; border-radius: 8px; padding: 16px; margin-bottom: 12px; cursor: pointer; background: white; transition: all 0.15s;'
                }));
            })
            .catch(error => {
                console.error(error);
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: "Error",
                        message: "Error searching leads",
                        variant: "error"
                    })
                );
            });
    }

    handleSelectLead(event) {
        const leadId = event.currentTarget.dataset.id;
        
        // Find the selected lead
        const selectedLead = this.leads.find(lead => lead.Id === leadId);
        
        if (selectedLead) {
            // Add to selected leads array
            this.selectedLeads = [...this.selectedLeads, {
                ...selectedLead,
                cardStyle: 'border: 2px solid #1570ef; border-radius: 8px; padding: 15px; margin-bottom: 12px; background: #e0f2fe; box-shadow: 0 2px 8px rgba(21, 112, 239, 0.2);'
            }];
            
            // Remove from search results
            this.leads = this.leads.filter(lead => lead.Id !== leadId);
        }
    }

    handleRemoveLead(event) {
        const leadId = event.currentTarget.dataset.id;
        
        // Remove from selected leads
        this.selectedLeads = this.selectedLeads.filter(lead => lead.Id !== leadId);
    }

    get hasSelectedLeads() {
        return this.selectedLeads.length > 0;
    }

    get selectedLeadsCount() {
        return this.selectedLeads.length;
    }

    handleMerge() {
        if (this.selectedLeads.length === 0) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: "Warning",
                    message: "Please select at least one lead to merge",
                    variant: "warning"
                })
            );
            return;
        }

        const leadIdsToMerge = this.selectedLeads.map(lead => lead.Id);

        submitMergeForApproval({
            mainLeadId: this.recordId,
            leadIdsToMerge: leadIdsToMerge
        })
        .then(result => {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: "Success",
                    message: result,
                    variant: "success"
                })
            );
            // Reset
            this.selectedLeads = [];
            this.leads = [];
            this.searchKey = '';
        })
        .catch(error => {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: "Error",
                    message: error.body ? error.body.message : error.message,
                    variant: "error"
                })
            );
        });
    }
}