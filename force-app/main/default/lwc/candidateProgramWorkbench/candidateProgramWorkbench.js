import { LightningElement, track } from 'lwc';
import getWorkbenchData from '@salesforce/apex/CandidateProgramWorkbenchController.getWorkbenchData';
import reallocateCandidates from '@salesforce/apex/CandidateProgramWorkbenchController.reallocateCandidates';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

const BASE_FILTER_SECTIONS = [
    { id: 'leadCreatedDate', label: 'Lead Created Date', step: 1, open: false, isCreatedDate: true },
    { id: 'lastInquiryDate', label: 'Last Inquiry Date', step: 2, open: false, isLastInquiryDate: true },
    { id: 'firstInquiryDate', label: 'First Inquiry Date', step: 3, open: false, isFirstInquiryDate: true },
    { id: 'firstInquirySource', label: 'First Inquiry Source', step: 4, open: false, isFirstInquirySource: true },
    { id: 'lastInquirySource', label: 'Last Inquiry Source', step: 5, open: false, isLastInquirySource: true },
    { id: 'leadLevel', label: 'Lead Level', step: 6, open: false, isLeadLevel: true },
    { id: 'callActivity', label: 'Call Activity', step: 7, open: false, isCallActivity: true },
    { id: 'spocName', label: 'SPOC Name', step: 8, open: false, isSpoc: true },
    { id: 'city', label: 'City', step: 9, open: false, isCity: true }
];

const CALL_ACTIVITY_OPTIONS = [
    { label: 'All', value: '' },
    { label: 'Not Dialed in Timeframe', value: 'notDialed' },
    { label: 'Dialed in Timeframe (Connected)', value: 'connected' },
    { label: 'Dialed in Timeframe (Not Connected)', value: 'notConnected' }
];

function buildSections() {
    return BASE_FILTER_SECTIONS.map((section) => ({
        ...section,
        caretClass: section.open ? 'caret caret-open' : 'caret'
    }));
}

export default class CandidateProgramWorkbench extends LightningElement {
    pageSize = 10;
    selectedCandidateIds = new Set();

    @track filtersOpen = true;
    @track filterSections = buildSections();
    @track rows = [];
    allRows = [];
    @track spocOptions = [];
    @track levelGroups = [];
    @track enquirySourceOptions = [];
    @track cityOptions = [];
    @track isLoading = false;
    @track errorMessage = '';
    @track showReallocateModal = false;
    @track selectedReallocationUserId = '';
    @track reallocationComment = '';
    @track reallocationError = '';
    @track selectionMessage = '';
    @track reallocationUserSearch = '';

    filters = {
        createdFrom: '',
        createdTo: '',
        firstInquiryFrom: '',
        firstInquiryTo: '',
        lastInquiryFrom: '',
        lastInquiryTo: '',
        firstInquirySources: [],
        lastInquirySources: [],
        levelKeys: [],
        spocIds: [],
        cities: [],
        callActivityType: '',
        callFrom: '',
        callTo: '',
        page: 1
    };

    connectedCallback() {
        this.loadData();
    }

    async loadData() {
        this.isLoading = true;
        this.errorMessage = '';
        try {
            const response = await getWorkbenchData({ request: this.filters });
            this.allRows = (response?.rows || []).map((row) => ({
                ...row,
                selected: this.selectedCandidateIds.has(row.id),
                expanded: row.expanded === true
            }));
            this.rows = this.applyClientSideFilters(this.allRows);
            this.spocOptions = response?.spocOptions || [];
            this.levelGroups = response?.levelGroups || [];
            this.enquirySourceOptions = response?.enquirySourceOptions || [];
            this.cityOptions = response?.cityOptions || [];
        } catch (error) {
            this.errorMessage = error?.body?.message || error?.message || 'Failed to load workbench data.';
            this.rows = [];
            this.allRows = [];
            this.spocOptions = [];
            this.levelGroups = [];
            this.enquirySourceOptions = [];
            this.cityOptions = [];
            this.selectionMessage = '';
        } finally {
            this.isLoading = false;
        }
    }

    get filterToggleLabel() {
        return this.filtersOpen ? 'Hide Filters' : 'Show Filters';
    }

    get filterPanelClass() {
        return this.filtersOpen ? 'layout-shell' : 'layout-shell filters-collapsed';
    }

    get selectedCount() {
        return this.selectedCandidateIds.size;
    }

    get rowsWithComputedLeads() {
        return this.paginatedRows.map((row) => ({
            ...row,
            initial: row.name ? row.name.charAt(0) : '',
            candidateUrl: row.id ? `/${row.id}` : '#',
            relatedLeadLabel: (row.relatedLeads || []).map((lead) => `${lead.course} - ${lead.level}`),
            relatedLeadKeys: (row.relatedLeads || []).map((lead) =>
                this.buildLevelKey(lead.course, lead.level)
            )
        }));
    }

    get currentPage() {
        return this.filters.page || 1;
    }

    get totalPages() {
        return Math.max(1, Math.ceil(this.rows.length / this.pageSize));
    }

    get paginatedRows() {
        const startIndex = (this.currentPage - 1) * this.pageSize;
        return this.rows.slice(startIndex, startIndex + this.pageSize);
    }

    get pageStatus() {
        return `Page ${this.currentPage} of ${this.totalPages}`;
    }

    get isPreviousDisabled() {
        return this.currentPage <= 1;
    }

    get isNextDisabled() {
        return this.currentPage >= this.totalPages;
    }

    get levelGroupsView() {
        return this.levelGroups.map((group) => ({
            ...group,
            options: (group.options || []).map((option) => ({
                ...option,
                checked: this.filters.levelKeys.includes(option.value)
            }))
        }));
    }

    get callActivityOptions() {
        return CALL_ACTIVITY_OPTIONS;
    }

    get showEmptyState() {
        return !this.isLoading && !this.errorMessage && this.rows.length === 0;
    }

    get canReallocate() {
        return this.selectedCount > 0;
    }

    get isAllSelected() {
    return this.paginatedRows.length > 0 &&
           this.paginatedRows.every(row => this.selectedCandidateIds.has(row.id));
}

    get reallocationUserOptions() {
        const searchKey = this.normalizeFilterValue(this.reallocationUserSearch);
        const options = this.spocOptions || [];

        if (!searchKey) {
            return options;
        }

        return options.filter((option) =>
            this.normalizeFilterValue(option.label).includes(searchKey)
        );
    }

    handleToggleFilters() {
        this.filtersOpen = !this.filtersOpen;
    }

handleSelectAll(event) {
    const checked = event.target.checked;
    this.selectionMessage = '';

    let updatedSelectedIds = new Set(this.selectedCandidateIds);

    this.paginatedRows.forEach(row => {
        if (checked) {
            updatedSelectedIds.add(row.id);
        } else {
            updatedSelectedIds.delete(row.id);
        }
    });

    this.selectedCandidateIds = updatedSelectedIds;

    // update UI rows
    this.rows = this.rows.map(row =>
        this.paginatedRows.some(r => r.id === row.id)
            ? { ...row, selected: checked }
            : row
    );

    this.allRows = this.allRows.map(row =>
        this.paginatedRows.some(r => r.id === row.id)
            ? { ...row, selected: checked }
            : row
    );
}




    async handleReset() {
        this.selectedCandidateIds = new Set();
        this.filterSections = buildSections();
        this.filters = {
            createdFrom: '',
            createdTo: '',
            firstInquiryFrom: '',
            firstInquiryTo: '',
            lastInquiryFrom: '',
            lastInquiryTo: '',
            firstInquirySources: [],
            lastInquirySources: [],
            levelKeys: [],
            spocIds: [],
            cities: [],
            callActivityType: '',
            callFrom: '',
            callTo: '',
            page: 1
        };
        await this.loadData();
    }

    handleToggleSection(event) {
        const sectionId = event.currentTarget.dataset.id;
        this.filterSections = this.filterSections.map((section) => {
            const open = section.id === sectionId ? !section.open : section.open;
            return {
                ...section,
                open,
                caretClass: open ? 'caret caret-open' : 'caret'
            };
        });
    }

    handleCreatedDateChange(event) {
        const field = event.target.dataset.field;
        this.filters = {
            ...this.filters,
            [field]: event.target.value
        };
    }

    handleInquiryDateChange(event) {
        const field = event.target.dataset.field;
        this.filters = {
            ...this.filters,
            [field]: event.target.value
        };
    }

    handleFirstInquirySourceChange(event) {
        this.filters = {
            ...this.filters,
            firstInquirySources: event.detail.value
        };
    }

    handleLastInquirySourceChange(event) {
        this.filters = {
            ...this.filters,
            lastInquirySources: event.detail.value
        };
    }

    handleSpocChange(event) {
        this.filters = {
            ...this.filters,
            spocIds: event.detail.value
        };
    }

    handleCityChange(event) {
        this.filters = {
            ...this.filters,
            cities: event.detail.value
        };
    }

    handleLevelCheckboxChange(event) {
        const levelKey = event.target.dataset.value;
        const isChecked = event.target.checked;
        const nextLevelKeys = new Set(this.filters.levelKeys || []);

        if (isChecked) {
            nextLevelKeys.add(levelKey);
        } else {
            nextLevelKeys.delete(levelKey);
        }

        this.filters = {
            ...this.filters,
            levelKeys: Array.from(nextLevelKeys)
        };
    }

    handleCallActivityTypeChange(event) {
        this.filters = {
            ...this.filters,
            callActivityType: event.detail.value
        };
    }

    handleCallDateTimeChange(event) {
        const field = event.target.dataset.field;
        this.filters = {
            ...this.filters,
            [field]: event.target.value
        };
    }

    handleDateFieldOpen(event) {
        const input = event.target;
        if (input && typeof input.showPicker === 'function') {
            input.showPicker();
        }
    }

    async handleApplyFilters() {
        this.filters = {
            ...this.filters,
            page: 1
        };
        await this.loadData();
    }

    handleOpenReallocateModal() {
        if (!this.canReallocate) {
            this.selectionMessage = 'Select at least one candidate to reallocate.';
            return;
        }

        this.selectionMessage = '';
        this.selectedReallocationUserId = '';
        this.reallocationComment = '';
        this.reallocationUserSearch = '';
        this.reallocationError = '';
        this.showReallocateModal = true;
    }

    handleCloseReallocateModal() {
        this.showReallocateModal = false;
        this.selectedReallocationUserId = '';
        this.reallocationComment = '';
        this.reallocationUserSearch = '';
        this.reallocationError = '';
    }

    handleReallocationUserChange(event) {
        this.selectedReallocationUserId = event.detail.value;
        this.reallocationError = '';
    }

    handleReallocationUserSearch(event) {
        this.reallocationUserSearch = event.target.value;
    }

    handleReallocationCommentChange(event) {
        this.reallocationComment = event.target.value;
        this.reallocationError = '';
    }

    async handleConfirmReallocation() {
        const selectedCandidateIds = Array.from(this.selectedCandidateIds);

        if (!this.selectedReallocationUserId) {
            this.reallocationError = 'Please select a SPOC.';
            return;
        }

        if (!selectedCandidateIds.length) {
            this.reallocationError = 'Please select at least one candidate.';
            return;
        }
        if (!this.reallocationComment || !this.reallocationComment.trim()) {
            this.reallocationError = 'Please enter reallocation comments.';
            return;
        }

        this.isLoading = true;
        this.reallocationError = '';

        try {
            await reallocateCandidates({
                candidateIds: selectedCandidateIds,
                targetOwnerId: this.selectedReallocationUserId,
                comment: this.reallocationComment.trim()
            });

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Reallocated',
                    message: 'Selected candidates were reallocated successfully.',
                    variant: 'success'
                })
            );

            this.selectedCandidateIds = new Set();
            this.handleCloseReallocateModal();
            await this.loadData();
        } catch (error) {
            this.reallocationError = error?.body?.message || error?.message || 'Failed to reallocate candidates.';
        } finally {
            this.isLoading = false;
        }
    }

    handleSelectRow(event) {
        const rowId = event.target.dataset.id;
        const checked = event.target.checked;
        this.selectionMessage = '';

        const nextSelectedIds = new Set(this.selectedCandidateIds);
        if (checked) {
            nextSelectedIds.add(rowId);
        } else {
            nextSelectedIds.delete(rowId);
        }
        this.selectedCandidateIds = nextSelectedIds;

        this.rows = this.rows.map((row) =>
            row.id === rowId ? { ...row, selected: checked } : row
        );
        this.allRows = this.allRows.map((row) =>
            row.id === rowId ? { ...row, selected: checked } : row
        );
    }

    handlePreviousPage() {
        if (this.isPreviousDisabled) {
            return;
        }

        this.filters = {
            ...this.filters,
            page: this.currentPage - 1
        };
    }

    handleNextPage() {
        if (this.isNextDisabled) {
            return;
        }

        this.filters = {
            ...this.filters,
            page: this.currentPage + 1
        };
    }

    applyClientSideFilters(sourceRows) {
        const selectedSpocIds = new Set(this.filters.spocIds || []);
        const selectedLevelKeys = new Set((this.filters.levelKeys || []).map((value) => this.normalizeFilterValue(value)));
        const createdFrom = this.parseDateOnly(this.filters.createdFrom);
        const createdTo = this.parseDateOnly(this.filters.createdTo);
        const firstInquiryFrom = this.parseDateOnly(this.filters.firstInquiryFrom);
        const firstInquiryTo = this.parseDateOnly(this.filters.firstInquiryTo);
        const lastInquiryFrom = this.parseDateOnly(this.filters.lastInquiryFrom);
        const lastInquiryTo = this.parseDateOnly(this.filters.lastInquiryTo);
        const firstInquirySources = new Set((this.filters.firstInquirySources || []).map((value) => this.normalizeFilterValue(value)));
        const lastInquirySources = new Set((this.filters.lastInquirySources || []).map((value) => this.normalizeFilterValue(value)));
        const selectedCities = new Set((this.filters.cities || []).map((value) => this.normalizeFilterValue(value)));

        return (sourceRows || []).filter((row) => {
            const rowCreatedDate = this.parseDateOnly(row.createdDate);
            const rowFirstInquiryDate = this.parseDateOnly(row.firstInquiryDate);
            const rowLastInquiryDate = this.parseDateOnly(row.lastInquiry);
            const matchesCreatedDate =
                (!createdFrom || (rowCreatedDate && rowCreatedDate >= createdFrom)) &&
                (!createdTo || (rowCreatedDate && rowCreatedDate <= createdTo));
            const matchesFirstInquiryDate =
                (!firstInquiryFrom || (rowFirstInquiryDate && rowFirstInquiryDate >= firstInquiryFrom)) &&
                (!firstInquiryTo || (rowFirstInquiryDate && rowFirstInquiryDate <= firstInquiryTo));
            const matchesLastInquiryDate =
                (!lastInquiryFrom || (rowLastInquiryDate && rowLastInquiryDate >= lastInquiryFrom)) &&
                (!lastInquiryTo || (rowLastInquiryDate && rowLastInquiryDate <= lastInquiryTo));
            const matchesFirstInquirySource =
                !firstInquirySources.size || firstInquirySources.has(this.normalizeFilterValue(row.firstInquirySource));
            const matchesLastInquirySource =
                !lastInquirySources.size || lastInquirySources.has(this.normalizeFilterValue(row.lastInquirySource));
            const matchesSpoc = !selectedSpocIds.size || selectedSpocIds.has(row.spocId);
            const matchesCity = !selectedCities.size || selectedCities.has(this.normalizeFilterValue(row.city));
            const rowLevelKeys = (row.relatedLeads || []).map((lead) => this.buildLevelKey(lead.course, lead.level));
            const matchesLevel = !selectedLevelKeys.size || rowLevelKeys.some((key) => selectedLevelKeys.has(key));
            return matchesCreatedDate &&
                matchesFirstInquiryDate &&
                matchesLastInquiryDate &&
                matchesFirstInquirySource &&
                matchesLastInquirySource &&
                matchesSpoc &&
                matchesCity &&
                matchesLevel;
        });
    }

    buildLevelKey(course, level) {
        return `${this.normalizeFilterValue(course)}||${this.normalizeFilterValue(level)}`;
    }

    normalizeFilterValue(value) {
        return (value || '').trim().toLowerCase();
    }

    parseDateOnly(value) {
        if (!value) {
            return null;
        }

        if (/^\d{4}-\d{2}-\d{2}$/.test(value)) {
            return new Date(`${value}T00:00:00`);
        }

        if (/^\d{2}\/\d{2}\/\d{4}$/.test(value)) {
            const [month, day, year] = value.split('/');
            return new Date(`${year}-${month}-${day}T00:00:00`);
        }

        const parsedDate = new Date(value);
        return Number.isNaN(parsedDate.getTime()) ? null : parsedDate;
    }
}