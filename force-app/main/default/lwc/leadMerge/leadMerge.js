import { LightningElement, track, api } from 'lwc';
import searchLeads from '@salesforce/apex/LeadMergeController.searchLeads';
import submitMergeForApproval from '@salesforce/apex/LeadMergeController.submitMergeForApproval';
import getLeadDetails from '@salesforce/apex/LeadMergeController.getLeadDetails';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import USER_ID from '@salesforce/user/Id';

export default class LeadMerge extends LightningElement {
    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        this._recordId = value;
        if (value) {
            this.fetchMainLeadDetails();
        }
    }
    _recordId;

    currentUserId = USER_ID;
    searchKey = '';
    @track leads = [];
    @track selectedLead = null; // Changed from selectedLeads array to single object
    mainLeadWrapper = null;

    connectedCallback() {
        if (this._recordId && !this.mainLeadWrapper) {
            this.fetchMainLeadDetails();
        }
    }

    fetchMainLeadDetails() {
        getLeadDetails({ leadId: this._recordId })
            .then(result => {
                this.mainLeadWrapper = result;
            })
            .catch(error => {
                console.error('Error fetching main lead details:', error);
            });
    }

    handleChange(event) {
        this.searchKey = event.target.value;
    }

    handleSearch() {
        if (!this.searchKey || this.searchKey.trim() === '') {
            this.showToast('Warning', 'Please enter a search value', 'warning');
            return;
        }

        const selectedLeadIds = this.selectedLead ? [this.selectedLead.Id] : [];

        searchLeads({
            searchKey: this.searchKey.trim(),
            currentLeadId: this.recordId,
            selectedLeadIds: selectedLeadIds
        })
            .then(result => {
                this.leads = result.map(wrapper => ({
                    ...wrapper.lead,
                    ownerName: wrapper.lead.Owner ? wrapper.lead.Owner.Name : 'Unknown',
                    isUnderApproval: wrapper.isUnderApproval,
                    ownerManagerId: wrapper.ownerManagerId
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
        const lead = this.leads.find(l => l.Id === leadId);

        if (lead) {
            if (lead.isUnderApproval) {
                this.showToast('Error', 'This lead is already part of a pending approval process.', 'error');
                return;
            }
            // Enforce single selection: Replace current selection if exists
            if (this.selectedLead) {
                this.leads = [this.selectedLead, ...this.leads];
            }
            this.selectedLead = lead;
            this.leads = this.leads.filter(l => l.Id !== leadId);
        }
    }

    handleRemoveLead() {
        if (this.selectedLead) {
            this.leads = [this.selectedLead, ...this.leads];
            this.selectedLead = null;
        }
    }

    mergeComments = '';

    handleCommentChange(event) {
        this.mergeComments = event.target.value;
    }

    handleMerge() {
        if (!this.selectedLead) {
            this.showToast('Warning', 'Please select a lead to merge', 'warning');
            return;
        }

        if (!this.mergeComments) {
            this.showToast('Error', 'Please enter comments for this merge.', 'error');
            return;
        }

        submitMergeForApproval({
            mainLeadId: this.recordId,
            sourceLeadId: this.selectedLead.Id,
            mergeComments: this.mergeComments
        })
            .then(result => {
                this.showToast('Success', result, 'success');
                this.resetComponent();
                setTimeout(() => {
                    this.dispatchEvent(new CloseActionScreenEvent());
                }, 200);
            })
            .catch(error => {
                const errorMessage = error.body?.message || error.message || 'An error occurred during merge';
                this.showToast('Error', errorMessage, 'error');
            });
    }

    resetComponent() {
        this.selectedLead = null;
        this.leads = [];
        this.searchKey = '';
        this.mergeComments = '';
        this.fetchMainLeadDetails();
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    get hasSelectedLeads() {
        return !!this.selectedLead;
    }

    get hasAnyContent() {
        return this.hasSelectedLeads || this.leads.length > 0;
    }

    get showSearchResults() {
        return this.leads.length > 0 && !this.hasSelectedLeads;
    }
}