import { LightningElement, track, api } from 'lwc';
import searchLeads from '@salesforce/apex/LeadMergeController.searchLeads';
import submitMergeForApproval from '@salesforce/apex/LeadMergeController.submitMergeForApproval';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class LeadMerge extends LightningElement {
    @api recordId;
    searchKey = '';
    @track leads = [];
    @track selectedLeads = [];

    handleChange(event) {
        this.searchKey = event.target.value;
    }

    handleSearch() {
        if (!this.searchKey || this.searchKey.trim() === '') {
            this.showToast('Warning', 'Please enter a search value', 'warning');
            return;
        }

        const selectedLeadIds = this.selectedLeads.map(lead => lead.Id);

        searchLeads({ 
            searchKey: this.searchKey.trim(), 
            currentLeadId: this.recordId,
            selectedLeadIds: selectedLeadIds 
        })
        .then(result => {
            this.leads = result.map(lead => ({
                ...lead,
                ownerName: lead.Owner ? lead.Owner.Name : 'Unknown'
            }));
            
            if (this.leads.length === 0) {
                this.showToast('Info', 'No leads found matching your search', 'info');
            }
        })
        .catch(error => {
            console.error('Search error:', error);
            this.showToast('Error', 'Error searching leads', 'error');
        });
    }

    handleSelectLead(event) {
        const leadId = event.currentTarget.dataset.id;
        const selectedLead = this.leads.find(lead => lead.Id === leadId);
        
        if (selectedLead) {
            this.selectedLeads = [...this.selectedLeads, selectedLead];
            this.leads = this.leads.filter(lead => lead.Id !== leadId);
        }
    }

    handleRemoveLead(event) {
        event.stopPropagation();
        const leadId = event.currentTarget.dataset.id;
        this.selectedLeads = this.selectedLeads.filter(lead => lead.Id !== leadId);
    }

    handleMerge() {
        if (this.selectedLeads.length === 0) {
            this.showToast('Warning', 'Please select at least one lead to merge', 'warning');
            return;
        }

        const leadIdsToMerge = this.selectedLeads.map(lead => lead.Id);

        submitMergeForApproval({
            mainLeadId: this.recordId,
            leadIdsToMerge: leadIdsToMerge
        })
        .then(result => {
            this.showToast('Success', result, 'success');
            this.resetComponent();
        })
        .catch(error => {
            const errorMessage = error.body?.message || error.message || 'An error occurred during merge';
            this.showToast('Error', errorMessage, 'error');
        });
    }

    resetComponent() {
        this.selectedLeads = [];
        this.leads = [];
        this.searchKey = '';
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

    get hasSelectedLeads() {
        return this.selectedLeads.length > 0;
    }

    get selectedLeadsCount() {
        return this.selectedLeads.length;
    }

    get selectedLeadsCountPlural() {
        return this.selectedLeadsCount > 1 ? 's' : '';
    }

    get hasAnyContent() {
        return this.hasSelectedLeads || this.leads.length > 0;
    }
}