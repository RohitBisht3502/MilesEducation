import { LightningElement, api, wire, track } from 'lwc';
import fetchLeadData from '@salesforce/apex/Webservice_RegistantAttendee.fetchLeadData';
import { getRecord } from 'lightning/uiRecordApi';
import { CloseActionScreenEvent } from 'lightning/actions';

const PAGE_SIZE = 5;
const REGISTRANT_FIELD = 'Webinar_Member__c.Registrant_Id__c';

export default class RegistrantDetailsModal extends LightningElement {

    /* ===== INPUT ===== */
    @api recordId;

    /* ===== STATE ===== */
    @track registrantId;
    @track data;
    @track polls = [];
    @track pagedPolls = [];
    @track isLoading = true;
    @track error;

    currentPage = 1;
    totalPages = 0;
    hasLoaded = false; // 🔒 prevents duplicate API calls

    /* ========= FETCH REGISTRANT ID ========= */
    @wire(getRecord, { recordId: '$recordId', fields: [REGISTRANT_FIELD] })
    wiredRecord({ error, data }) {

        if (data && !this.hasLoaded) {
            const field = data.fields?.Registrant_Id__c;

            if (!field || !field.value) {
                this.error = 'Registrant Id not found on record';
                this.isLoading = false;
                return;
            }

            this.registrantId = field.value;
            this.hasLoaded = true;
            this.loadData();
        }

        if (error) {
            this.error = 'Unable to load record data';
            this.isLoading = false;
        }
    }

    /* ========= API CALL ========= */
    loadData() {
        this.isLoading = true;

        fetchLeadData({ registrantId: this.registrantId })
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
                this.isLoading = false;
            })
            .catch(err => {
                this.error = err?.body?.message || err.message || 'Unknown error';
                this.isLoading = false;
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

    /* ========= MODAL ========= */
    closeModal() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }
}