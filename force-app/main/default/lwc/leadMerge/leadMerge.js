import { LightningElement, track, api, wire } from 'lwc';
import searchLeads from '@salesforce/apex/LeadMergeController.searchLeads';
import submitMergeForApproval from '@salesforce/apex/LeadMergeController.submitMergeForApproval';
import getLeadDetails from '@salesforce/apex/LeadMergeController.getLeadDetails';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
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
    @track selectedLeads = [];
    mainLeadWrapper = null;

    connectedCallback() {
        // Fallback if recordId was set before connectedCallback
        if (this._recordId && !this.mainLeadWrapper) {
            this.fetchMainLeadDetails();
        }
    }

    fetchMainLeadDetails() {
        console.log('Fetching main lead details for:', this._recordId);
        getLeadDetails({ leadId: this._recordId })
            .then(result => {
                console.log('Main Lead Details Fetched:', JSON.stringify(result));
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

        const selectedLeadIds = this.selectedLeads.map(lead => lead.Id);

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
        const selectedLead = this.leads.find(lead => lead.Id === leadId);

        if (selectedLead) {
            if (selectedLead.isUnderApproval) {
                this.showToast('Error', 'This lead is already in an approval process and cannot be selected.', 'error');
                return;
            }
            this.selectedLeads = [...this.selectedLeads, selectedLead];
            this.leads = this.leads.filter(lead => lead.Id !== leadId);
        }
    }

    handleRemoveLead(event) {
        event.stopPropagation();
        const leadId = event.currentTarget.dataset.id;
        this.selectedLeads = this.selectedLeads.filter(lead => lead.Id !== leadId);
    }

    mergeComments = '';

    handleCommentChange(event) {
        this.mergeComments = event.target.value;
    }

    handleMerge() {
        if (this.selectedLeads.length === 0) {
            this.showToast('Warning', 'Please select at least one lead to merge', 'warning');
            return;
        }

        const leadIdsToMerge = this.selectedLeads.map(lead => lead.Id);

        // If validation logic is required on client side before server call:
        // For now, reliance on server validation is safe, but we could check comments here if showComments is true.
        if (this.showComments && !this.mergeComments) {
            this.showToast('Error', 'Please enter comments for this merge.', 'error');
            return;
        }

        submitMergeForApproval({
            mainLeadId: this.recordId,
            leadIdsToMerge: leadIdsToMerge,
            mergeComments: this.mergeComments
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
        this.mergeComments = '';
        this.fetchMainLeadDetails(); // Refresh main lead details if needed, though status might have changed.
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

    get showComments() {
        if (!this.selectedLeads.length || !this.mainLeadWrapper) {
            return false;
        }

        console.log('--- showComments Debug ---');
        console.log('Current User ID:', this.currentUserId);

        // Logic: The Current User must be the Manager of the Main Lead's Owner AND the Selected Lead's Owner.

        // 1. Check Main Lead
        const mainManagerId = this.mainLeadWrapper.ownerManagerId;
        const amIMainManager = mainManagerId === this.currentUserId;

        if (!amIMainManager) {
            console.log('ShowComments: Current user is not Manager of Main Lead.');
            return false;
        }

        // 2. Check All Selected Leads
        for (let lead of this.selectedLeads) {
            const leadManagerId = lead.ownerManagerId;
            const amILeadManager = leadManagerId === this.currentUserId;

            if (!amILeadManager) {
                console.log('ShowComments: Current user is not Manager of Selected Lead:', lead.Name);
                return false;
            }
        }

        console.log('All checks passed -> SHOW COMMENTS (GM Scenario)');
        return true;
    }
}