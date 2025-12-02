import { LightningElement, track, api } from 'lwc';
import searchLeads from '@salesforce/apex/LeadMergeController.searchLeads';
import submitMergeForApproval from '@salesforce/apex/LeadMergeController.submitMergeForApproval';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class LeadMerge extends LightningElement {
    @api recordId; // Current Lead record ID
    searchKey = '';
    @track leads = [];
    @track selectedLead = null;

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

        searchLeads({ searchKey: this.searchKey, currentLeadId: this.recordId })
            .then(result => {
                // Add properties to each lead for styling and display
                this.leads = result.map(lead => ({
                    ...lead,
                    isSelected: false,
                    ownerName: lead.Owner ? lead.Owner.Name : 'Unknown',
                    cardStyle: 'border: 1px solid #e4e7ec; border-radius: 8px; padding: 16px; margin-bottom: 12px; cursor: pointer; background: white; transition: all 0.15s;'
                }));
                this.selectedLead = null; // Reset selection on new search
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
        
        // Update styling for all leads with distinct selected state
        this.leads = this.leads.map(lead => {
            const isSelected = lead.Id === leadId;
            return {
                ...lead,
                isSelected: isSelected,
                cardStyle: isSelected 
                    ? 'border: 2px solid #1570ef; border-radius: 8px; padding: 15px; margin-bottom: 12px; cursor: pointer; background: #e0f2fe; transition: all 0.15s; box-shadow: 0 2px 8px rgba(21, 112, 239, 0.2);'
                    : 'border: 1px solid #e4e7ec; border-radius: 8px; padding: 16px; margin-bottom: 12px; cursor: pointer; background: white; transition: all 0.15s;'
            };
        });
        
        this.selectedLead = leadId;
    }

    get showMergeButton() {
        return this.selectedLead !== null;
    }

    handleMerge() {
        if (!this.selectedLead) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: "Warning",
                    message: "Please select a lead to merge",
                    variant: "warning"
                })
            );
            return;
        }

        submitMergeForApproval({
            lead1Id: this.recordId,
            lead2Id: this.selectedLead
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
            this.selectedLead = null;
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