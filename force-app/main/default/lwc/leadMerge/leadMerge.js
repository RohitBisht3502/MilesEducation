import { LightningElement, track, api } from 'lwc';
import searchLeads from '@salesforce/apex/LeadMergeController.searchLeads';
import submitMergeForApproval from '@salesforce/apex/LeadMergeController.submitMergeForApproval';
import getLeadDetails from '@salesforce/apex/LeadMergeController.getLeadDetails';
import getUserAccessInfo from '@salesforce/apex/LeadMergeController.getUserAccessInfo';
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
    @track selectedLead = null;
    mainLeadWrapper = null;
    accessInfo;
    isLoading = false;
    mergeComments = '';

    connectedCallback() {
        this.loadAccess();
        if (this._recordId && !this.mainLeadWrapper) {
            this.fetchMainLeadDetails();
        }
    }

    loadAccess() {
        getUserAccessInfo()
            .then(result => {
                this.accessInfo = result;
            })
            .catch(error => {
                this.accessInfo = {
                    hasAccess: false,
                    message: error.body?.message || error.message || 'You do not have access.'
                };
            });
    }

    fetchMainLeadDetails() {
        this.isLoading = true;
        getLeadDetails({ leadId: this._recordId })
            .then(result => {
                this.mainLeadWrapper = result ? this.normalizeLeadWrapper(result) : null;
            })
            .catch(error => {
                console.error('Error fetching main lead details:', error);
            })
            .finally(() => {
                this.isLoading = false;
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

        this.isLoading = true;
        searchLeads({
            searchKey: this.searchKey.trim(),
            currentLeadId: this.recordId,
            selectedLeadIds: []
        })
            .then(result => {
                const selectedLeadId = this.selectedLead?.Id;
                this.leads = result.map(wrapper => this.normalizeLeadWrapper(wrapper, selectedLeadId));

                if (selectedLeadId) {
                    const refreshedSelectedLead = this.leads.find(lead => lead.Id === selectedLeadId);
                    if (refreshedSelectedLead) {
                        this.selectedLead = refreshedSelectedLead;
                    }
                }

                if (this.leads.length === 0) {
                    this.showToast('Info', 'No candidates found matching your search', 'info');
                }
            })
            .catch(error => {
                console.error('Search error:', error);
                this.showToast('Error', error.body?.message || 'Error searching candidates', 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleSelectLead(event) {
        const leadId = event.currentTarget.dataset.id;
        const lead = this.leads.find(l => l.Id === leadId);

        if (lead) {
            if (lead.isUnderApproval) {
                this.showToast('Error', 'This candidate is already part of a pending approval process.', 'error');
                return;
            }
            if (this.selectedLead?.Id === leadId) {
                this.selectedLead = null;
                this.syncSelectedState();
                return;
            }

            this.selectedLead = lead;
            this.syncSelectedState();
        }
    }

    handleRemoveLead() {
        if (this.selectedLead) {
            this.selectedLead = null;
            this.syncSelectedState();
        }
    }

    handleMerge() {
        if (!this.isAuthorized) {
            this.showToast('Error', this.accessMessage, 'error');
            return;
        }

        if (!this.selectedLead) {
            this.showToast('Warning', 'Please select a candidate to merge', 'warning');
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
                const errorMessage = error.body?.message || error.message || 'An error occurred during candidate merge';
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

    normalizeLeadWrapper(wrapper, selectedLeadId = null) {
        return this.buildLeadViewModel(wrapper, selectedLeadId);
    }

    buildLeadViewModel(wrapper, selectedLeadId) {
        const lead = wrapper?.lead || {};
        const customLeads = wrapper?.customLeads || [];
        const programLevels = this.getProgramLevels(customLeads);

        return {
            ...lead,
            ownerName: lead.Owner ? lead.Owner.Name : 'Unknown',
            isUnderApproval: wrapper.isUnderApproval,
            approvalMessage: wrapper.approvalMessage,
            ownerManagerId: wrapper.ownerManagerId,
            customLeads,
            courseSummary: wrapper.courseSummary || 'No related leads',
            initials: this.getInitials(lead.Name),
            candidateUrl: lead.Id ? `/${lead.Id}` : '#',
            programLevels,
            hasPrograms: programLevels.length > 0,
            spocName: lead.Owner ? lead.Owner.Name : '--',
            rowClass: lead.Id === selectedLeadId ? 'data-row search-results-row selected-row' : 'data-row search-results-row',
            checkboxClass: lead.Id === selectedLeadId ? 'row-check row-check-selected' : 'row-check'
        };
    }

    handleCommentChange(event) {
        this.mergeComments = event.target.value;
    }

    syncSelectedState() {
        const selectedLeadId = this.selectedLead?.Id;
        this.leads = this.leads.map(lead => ({
            ...lead,
            rowClass: lead.Id === selectedLeadId ? 'data-row search-results-row selected-row' : 'data-row search-results-row',
            checkboxClass: lead.Id === selectedLeadId ? 'row-check row-check-selected' : 'row-check'
        }));
    }

    get showSearchResults() {
        return this.leads.length > 0;
    }

    get isAuthorized() {
        return this.accessInfo?.hasAccess === true;
    }

    get accessMessage() {
        return this.accessInfo?.message || 'You do not have access. Only CC and SR users can merge candidates.';
    }

    get hasMainLead() {
        return !!this.mainLeadWrapper;
    }

    get hasPendingMergeProcess() {
        return this.mainLeadWrapper?.isUnderApproval === true;
    }

    get pendingMergeMessage() {
        return this.mainLeadWrapper?.approvalMessage || 'One process already exists for this candidate merge.';
    }

    get mainLeadView() {
        return this.mainLeadWrapper;
    }

    get resultCount() {
        return this.leads.length;
    }

    get isMergeDisabled() {
        return !this.selectedLead || !this.mergeComments || !this.mergeComments.trim();
    }

    get hasAnyContent() {
        return this.leads.length > 0 || this.hasMainLead;
    }

    getInitials(name) {
        if (!name) {
            return '?';
        }

        return name
            .trim()
            .split(/\s+/)
            .slice(0, 2)
            .map(part => part.charAt(0).toUpperCase())
            .join('');
    }

    getProgramLevels(customLeads) {
        const seen = new Set();
        const programs = [];

        (customLeads || []).forEach(customLead => {
            if (customLead.Course__c && !seen.has(customLead.Course__c)) {
                seen.add(customLead.Course__c);
                programs.push(customLead.Course__c);
            }
        });

        return programs;
    }

}
