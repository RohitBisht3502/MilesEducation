import { LightningElement, api, wire, track } from 'lwc';
import fetchLeadData from '@salesforce/apex/Webservice_RegistantAttendee.fetchLeadData';
import getWebinarsForLead from '@salesforce/apex/WebinarSelectionController.getWebinarsForLead';
import { getRecord } from 'lightning/uiRecordApi';
import { CloseActionScreenEvent } from 'lightning/actions';

const PAGE_SIZE = 5;
const REGISTRANT_FIELD = 'Webinar_Member__c.Registrant_Id__c';

export default class WebinarAttendeeDetailsModal extends LightningElement {

    /* ===== INPUT ===== */
    @api recordId;

    /* ===== STATE - WEBINAR SELECTION ===== */
    @track webinarOptions = [];
    @track selectedWebinarId;
    @track selectedWebinarMemberId;
    @track selectedRegistrantId;
    @track showDetails = false;
    @track isLoadingWebinars = true;
    @track webinarError;

    /* ===== STATE - REGISTRANT DETAILS ===== */
    @track data;
    @track polls = [];
    @track pagedPolls = [];
    @track isLoadingDetails = false;
    @track detailsError;

    currentPage = 1;
    totalPages = 0;

    /* ========= STEP 1: FETCH UNIQUE WEBINARS ========= */
    connectedCallback() {
        this.loadWebinars();
    }

    loadWebinars() {
        this.isLoadingWebinars = true;

        getWebinarsForLead({ leadId: this.recordId })
            .then(result => {
                if (result && result.length > 0) {
                    // Map to combobox options format
                    this.webinarOptions = result.map(webinar => ({
                        value: webinar.webinarId,
                        label: `${webinar.webinarName} - ${webinar.topic || 'No Topic'}`,
                        webinarName: webinar.webinarName,
                        topic: webinar.topic,
                        status: webinar.status,
                        startDateTime: webinar.startDateTime,
                        webinarMemberId: webinar.webinarMemberId,
                        registrantId: webinar.registrantId
                    }));
                    this.webinarError = null;
                } else {
                    this.webinarError = 'No webinar registrations found for this lead';
                }
                this.isLoadingWebinars = false;
            })
            .catch(err => {
                this.webinarError = err?.body?.message || err.message || 'Error loading webinar data';
                this.isLoadingWebinars = false;
            });
    }

    /* ========= HANDLE WEBINAR SELECTION ========= */
    handleWebinarChange(event) {
        this.selectedWebinarId = event.detail.value;
        
        // Find the selected webinar and store its member ID and registrant ID
        const selectedWebinar = this.webinarOptions.find(
            option => option.value === this.selectedWebinarId
        );
        
        if (selectedWebinar) {
            this.selectedWebinarMemberId = selectedWebinar.webinarMemberId;
            this.selectedRegistrantId = selectedWebinar.registrantId;
        }
    }

    /* ========= SHOW REGISTRANT DETAILS ========= */
    viewDetails() {
        if (this.selectedWebinarId && this.selectedRegistrantId) {
            this.showDetails = true;
            this.loadRegistrantData();
        }
    }

    /* ========= API CALL FOR REGISTRANT DATA ========= */
    loadRegistrantData() {
        this.isLoadingDetails = true;
        this.detailsError = null;

        fetchLeadData({ registrantId: this.selectedRegistrantId })
            .then(result => {
                this.data = result;

                this.polls = (result.pollResponses || []).map((p, index) => ({
                    key: index,
                    question: p.question,
                    answer: p.answer,
                    pollType: p.pollType,
                    date_time: p.date_time,
                    isOpen: false,
                    iconName: 'utility:chevronright'
                }));

                this.totalPages = Math.max(
                    1,
                    Math.ceil(this.polls.length / PAGE_SIZE)
                );

                this.currentPage = 1;
                this.setPageData();
                this.isLoadingDetails = false;
            })
            .catch(err => {
                this.detailsError = err?.body?.message || err.message || 'Unknown error';
                this.isLoadingDetails = false;
            });
    }

    /* ========= PAGINATION ========= */
    setPageData() {
        const start = (this.currentPage - 1) * PAGE_SIZE;
        const end = start + PAGE_SIZE;
        this.pagedPolls = this.polls.slice(start, end);
    }

    nextPage() {
        if (this.currentPage < this.totalPages) {
            this.currentPage++;
            this.setPageData();
        }
    }

    prevPage() {
        if (this.currentPage > 1) {
            this.currentPage--;
            this.setPageData();
        }
    }

    get isFirstPage() {
        return this.currentPage === 1;
    }

    get isLastPage() {
        return this.currentPage === this.totalPages;
    }

    /* ========= CARD TOGGLE (IMMUTABLE) ========= */
    toggleCard(event) {
        const index = Number(event.currentTarget.dataset.index);

        this.pagedPolls = this.pagedPolls.map((poll, i) => {
            if (i === index) {
                const isOpen = !poll.isOpen;
                return {
                    ...poll,
                    isOpen,
                    iconName: isOpen
                        ? 'utility:chevrondown'
                        : 'utility:chevronright'
                };
            }
            return poll;
        });
    }

    /* ========= BACK TO WEBINAR SELECTION ========= */
    handleBack() {
        this.showDetails = false;
        this.data = null;
        this.polls = [];
        this.pagedPolls = [];
        this.detailsError = null;
    }

    /* ========= GETTERS ========= */
    get hasWebinars() {
        return this.webinarOptions && this.webinarOptions.length > 0;
    }

    get isViewDetailsDisabled() {
        return !this.selectedWebinarId;
    }

    get selectedWebinar() {
        return this.webinarOptions.find(wm => wm.value === this.selectedWebinarId);
    }

    /* ========= MODAL CLOSE ========= */
    closeModal() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }
}