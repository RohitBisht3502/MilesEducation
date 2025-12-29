// file: force-app/main/default/lwc/leadEligibilityReview/leadEligibilityReview.js
import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';

import getFolderTree from '@salesforce/apex/EligibilityReviewController.getFolderTree';
import saveFileApex from '@salesforce/apex/EligibilityReviewController.saveFile';
import getFileFieldPicklists from '@salesforce/apex/EligibilityReviewController.getFileFieldPicklists';
import getLeadEligibilitySnapshot from '@salesforce/apex/EligibilityReviewController.getLeadEligibilitySnapshot';
import saveFolderCommentApex from '@salesforce/apex/EligibilityReviewController.saveFolderComment';
import updateFolderStatusApex from '@salesforce/apex/EligibilityReviewController.updateFolderStatus';
import getDownloadUrlApex from '@salesforce/apex/EligibilityReviewController.getDownloadUrl';
import calculateCreditScore from '@salesforce/apex/EligibilityReviewController.calculateCreditScore';
import saveEligibilitySnapshotApex from '@salesforce/apex/EligibilityReviewController.saveEligibilitySnapshot';

export default class LeadEligibilityReview extends LightningElement {
    @api recordId;

    @track folderTree = [];
    @track isModalOpen = false;
    @track editFile = {};
    @track leadStatus;
    @track universityOptions = [];
    @track gradeOptions = [];
    @track rankOptions = [];
    @track yearOptions = [];
    @track totalFilesOverall = 0;
    @track creditScore;
    @track cpaEligibilityStatus;
    @track statusOptions = [];
    @track folderStatusOptions = [];
    @track leadStatusOptions = [];
    @track isCalculating = false;
    @track isEditModalOpen = false;
    @track editCreditScore;
    @track editCpaStatus;
    @track editLeadStatus;
    @track allDegreesApproved = false;
    @track statusCountsSummary = [];
    @track viewLoadingId;

    @track isFolderModalOpen = false;
    @track activeFolder = {};
    @track folderCommentText = '';

    wiredTreeResult;
    wiredLeadSnapshotResult;

    connectedCallback() {
        this.initYearOptions();
    }

    get defaultFileStatuses() {
        return ['Submitted', 'Verified', 'Recheck/Reupload', 'Not Applicable', 'Not application'];
    }

    get defaultFolderStatuses() {
        return ['Pending review', 'Pending Review', 'Approved', 'Recheck'];
    }

    get defaultLeadStatuses() {
        return [
            'Yet to Initiate',
            'Initiated',
            'Under Verification',
            'Verified',
            'Not Eligible',
            'Eligibility report generated'
        ];
    }

    get fileStatusOptionsForUi() {
        return (this.statusOptions && this.statusOptions.length)
            ? this.statusOptions
            : this.defaultFileStatuses.map(v => ({ label: v, value: v }));
    }

    get folderStatusOptionsForUi() {
        return (this.folderStatusOptions && this.folderStatusOptions.length)
            ? this.folderStatusOptions
            : this.defaultFolderStatuses.map(v => ({ label: v, value: v }));
    }

    get cpaStatusOptions() {
        return [
            { label: 'Eligible for Exemption/License', value: 'Eligible for Exemption/License' },
            { label: 'Eligible for Exams', value: 'Eligible for Exams' },
            { label: 'Conditional Eligible', value: 'Conditional Eligible' },
            { label: 'Not Eligible', value: 'Not Eligible' }
        ];
    }

    get leadStatusOptionsForUi() {
        return (this.leadStatusOptions && this.leadStatusOptions.length)
            ? this.leadStatusOptions
            : this.defaultLeadStatuses.map(v => ({ label: v, value: v }));
    }

    get creditScoreDisplay() {
        return this.creditScore !== undefined && this.creditScore !== null ? this.creditScore : '--';
    }

    get cpaStatusDisplay() {
        return this.cpaEligibilityStatus || '--';
    }

    @wire(getFolderTree, { leadId: '$recordId' })
    wiredTree(result) {
        this.wiredTreeResult = result;
        const { data, error } = result;
        if (data) {
            const clean = JSON.parse(JSON.stringify(data || []));
            let decorated = this.decorateTree(clean, 1);
            decorated = this.filterNodesWithFiles(decorated);
            this.folderTree = decorated;
            this.totalFilesOverall = this.computeTotalFiles(this.folderTree);
            this.statusCountsSummary = this.computeStatusSummary(this.folderTree);
            this.allDegreesApproved = this.checkAllDegreesApproved(this.folderTree);
        } else if (error) {
            // eslint-disable-next-line no-console
            console.error(error);
            this.showToast('Error', 'Error loading eligibility folders', 'error');
        }
    }

    @wire(getLeadEligibilitySnapshot, { leadId: '$recordId' })
    wiredLeadSnapshot(result) {
        this.wiredLeadSnapshotResult = result;
        const { data, error } = result;
        if (data) {
            this.leadStatus = data.leadStatus;
            this.creditScore = data.creditScore;
            this.cpaEligibilityStatus = data.cpaEligibilityStatus;
            this.editCreditScore = data.creditScore;
            this.editCpaStatus = data.cpaEligibilityStatus;
            this.editLeadStatus = data.leadStatus;
        } else if (error) {
            // eslint-disable-next-line no-console
            console.error(error);
        }
    }

    @wire(getFileFieldPicklists)
    wiredPicklists({ data, error }) {
        if (data) {
            const u = data.universityValues || [];
            const g = data.gradeValues || [];
            const r = data.rankValues || [];
            const fStatuses = data.fileStatusValues && data.fileStatusValues.length
                ? data.fileStatusValues
                : this.defaultFileStatuses;
            const folderStatuses = data.folderStatusValues && data.folderStatusValues.length
                ? data.folderStatusValues
                : this.defaultFolderStatuses;
            const leadStatuses = data.leadStatusValues && data.leadStatusValues.length
                ? data.leadStatusValues
                : this.defaultLeadStatuses;

            this.universityOptions = u.map(v => ({ label: v, value: v }));
            this.gradeOptions = g.map(v => ({ label: v, value: v }));
            this.rankOptions = r.map(v => ({ label: v, value: v }));
            this.statusOptions = fStatuses.map(v => ({ label: v, value: v }));
            this.folderStatusOptions = folderStatuses.map(v => ({ label: v, value: v }));
            this.leadStatusOptions = leadStatuses.map(v => ({ label: v, value: v }));
        } else if (error) {
            // eslint-disable-next-line no-console
            console.error(error);
        }
    }

    initYearOptions() {
        const now = new Date().getFullYear();
        const start = now - 50;
        const years = [];
        for (let y = now; y >= start; y--) {
            years.push({ label: String(y), value: String(y) });
        }
        this.yearOptions = years;
    }

    get hasData() {
        return !!this.folderTree && this.folderTree.length > 0;
    }

    get hasAnyFile() {
        return this.computeTotalFiles(this.folderTree) > 0;
    }

    get totalFolders() {
        return this.countFolders(this.folderTree);
    }

    get totalFiles() {
        return this.computeTotalFiles(this.folderTree);
    }

    get isCalculateDisabled() {
        return !this.allDegreesApproved || this.isCalculating;
    }

    get pathItems() {
        const options = (this.leadStatusOptions && this.leadStatusOptions.length)
            ? this.leadStatusOptions
            : this.defaultLeadStatuses.map(v => ({ label: v, value: v }));

        const order = {};
        options.forEach((opt, idx) => {
            order[opt.value] = idx + 1;
        });

        const current = this.leadStatus || (options.length ? options[0].value : null);
        const currentOrder = current ? order[current] : null;

        return options.map(opt => {
            const stepOrder = order[opt.value];
            let cls = 'path-step';
            if (currentOrder && stepOrder < currentOrder) {
                cls += ' path-completed';
            } else if (currentOrder && stepOrder === currentOrder) {
                cls += ' path-current';
            }
            return {
                label: opt.label || opt.value,
                value: opt.value,
                className: cls
            };
        });
    }

    decorateTree(nodes, level) {
        if (!nodes) return [];
        return nodes.map(node => this.decorateNode(node, level));
    }

    decorateNode(node, level) {
        const decorated = { ...node };

        decorated.level = level;
        decorated.expanded = false;
        decorated.allowFolderEdit = decorated.folderType === 'Degree';

        if (level === 1) {
            if (decorated.qualificationType === 'UG' || decorated.name === 'UG') {
                decorated.subtitle = 'Undergraduate Degree';
            } else if (decorated.qualificationType === 'PG' || decorated.name === 'PG') {
                decorated.subtitle = 'Postgraduate Degree';
            } else if (decorated.name === 'Certificates') {
                decorated.subtitle = 'Additional Certificates';
            } else {
                decorated.subtitle = decorated.folderType === 'Certificates'
                    ? 'Additional Certificates'
                    : (decorated.folderType || '');
            }
        } else if (level === 2) {
            decorated.subtitle = decorated.degreeTitle || decorated.folderType || '';
        } else if (level === 3) {
        decorated.subtitle = decorated.folderType || '';
        }

        decorated.displayDate = decorated.monthYear || decorated.createdDate || '';
        decorated.comments = decorated.folderType === 'Degree' ? (decorated.comments || null) : null;

        // Children first (so we can aggregate their counts)
        if (decorated.children && decorated.children.length) {
            decorated.children = this.decorateTree(decorated.children, level + 1);
        }

        if (decorated.files && decorated.files.length) {
            decorated.files = decorated.files.map(f => {
                const file = { ...f };
                file.id = file.id || file.Id;
                file.statusClass = this.statusClassForFile(file.status);
                file.iconName = this.iconNameForFile(file.fileFormat || file.name);
                file.comment = file.comment || null;
                return file;
            });
        }

        // Aggregate status counts & total files (this node + descendants)
        const countKeys = (this.statusOptions && this.statusOptions.length)
            ? this.statusOptions.map(opt => opt.value)
            : this.defaultFileStatuses;
        const counts = {};
        countKeys.forEach(k => { counts[k] = 0; });
        const defaultCountKey = countKeys.length ? countKeys[0] : 'Submitted';

        if (decorated.children && decorated.children.length) {
            decorated.children.forEach(ch => {
                if (ch.statusCounts) {
                    Object.keys(ch.statusCounts).forEach(key => {
                        if (!counts.hasOwnProperty(key)) {
                            counts[key] = 0;
                        }
                        counts[key] += ch.statusCounts[key];
                    });
                }
            });
        }

        if (decorated.files && decorated.files.length) {
            decorated.files.forEach(file => {
                const st = file.status;
                if (st && counts.hasOwnProperty(st)) {
                    counts[st] = counts[st] + 1;
                } else if (counts.hasOwnProperty(defaultCountKey)) {
                    counts[defaultCountKey] = counts[defaultCountKey] + 1;
                }
            });
        }

        decorated.statusCounts = counts;
        const totalFiles = Object.keys(counts).reduce((sum, key) => sum + counts[key], 0);

        decorated.totalFiles = totalFiles;

        // Folder status display (only for degree level)
        decorated.showStatus = decorated.folderType === 'Degree' && !!decorated.status;
        decorated.statusClass = this.statusClassForFolder(decorated.status);

        // Build a human-readable summary for top-level folders
        const summaryParts = [];
        const summaryOrder = ['Verified', 'Recheck/Reupload', 'Not Applicable', 'Not application', 'Submitted'];
        summaryOrder.forEach(key => {
            if (counts[key] > 0) {
                const label = key === 'Recheck/Reupload' ? 'Recheck/Reupload' : key;
                summaryParts.push(`${label}: ${counts[key]}`);
            }
        });

        decorated.statusSummary = summaryParts.join(' | ');

        return decorated;
    }


    iconNameForFile(raw) {
        if (!raw) {
            return 'doctype:attachment';
        }

        let ext = String(raw).toLowerCase();

        // If it's a full filename, extract extension
        const dotIndex = ext.lastIndexOf('.');
        if (dotIndex !== -1 && dotIndex < ext.length - 1) {
            ext = ext.substring(dotIndex + 1);
        }

        if (ext === 'pdf') {
            return 'doctype:pdf';
        }

        if (['png', 'jpg', 'jpeg', 'gif', 'bmp', 'tiff', 'svg', 'webp'].includes(ext)) {
            return 'doctype:image';
        }

        if (['doc', 'docx'].includes(ext)) {
            return 'doctype:word';
        }

        if (['xls', 'xlsx', 'csv'].includes(ext)) {
            return 'doctype:excel';
        }

        if (['ppt', 'pptx'].includes(ext)) {
            return 'doctype:ppt';
        }

        return 'doctype:attachment';
    }


    filterNodesWithFiles(nodes) {
        if (!nodes) return [];
        return nodes
            .map(n => {
                const clone = { ...n };
                if (clone.children && clone.children.length) {
                    clone.children = this.filterNodesWithFiles(clone.children);
                }
                return clone;
            })
            .filter(n => {
                const hasFilesHere = n.files && n.files.length > 0;
                const hasChildren = n.children && n.children.length > 0;
                return hasFilesHere || hasChildren;
            });
    }

    computeTotalFiles(nodes) {
        if (!nodes) return 0;
        let sum = 0;
        nodes.forEach(n => {
            sum += n.totalFiles || 0;
            if (n.children && n.children.length) {
                sum += this.computeTotalFiles(n.children);
            }
        });
        return sum;
    }

    countFolders(nodes) {
        if (!nodes) return 0;
        let count = 0;
        nodes.forEach(n => {
            count += 1;
            if (n.children && n.children.length) {
                count += this.countFolders(n.children);
            }
        });
        return count;
    }

    checkAllDegreesApproved(nodes) {
        let allApproved = true;
        const traverse = (list) => {
            if (!list) return;
            list.forEach(item => {
                if (item.folderType === 'Degree' && item.status && item.status.toLowerCase() !== 'approved') {
                    allApproved = false;
                }
                if (item.children && item.children.length) traverse(item.children);
            });
        };
        traverse(nodes);
        return allApproved && nodes && nodes.length > 0;
    }

    computeStatusSummary(nodes) {
        const counts = {};
        const walk = (list) => {
            if (!list) return;
            list.forEach(n => {
                if (n.files && n.files.length) {
                    n.files.forEach(f => {
                        const key = f.status || 'Submitted';
                        counts[key] = (counts[key] || 0) + 1;
                    });
                }
                if (n.children && n.children.length) walk(n.children);
            });
        };
        walk(nodes);
        const order = [...this.defaultFileStatuses];
        Object.keys(counts).forEach(k => {
            if (!order.includes(k)) {
                order.push(k);
            }
        });
        return order
            .filter(k => counts[k])
            .map(k => ({ label: k, count: counts[k] }));
    }

    updateViewState(activeId) {
        const markNode = (node) => {
            const clone = { ...node };
            if (clone.files && clone.files.length) {
                clone.files = clone.files.map(f => ({
                    ...f,
                    isViewing: activeId && (f.id === activeId || f.Id === activeId)
                }));
            }
            if (clone.children && clone.children.length) {
                clone.children = clone.children.map(ch => markNode(ch));
            }
            return clone;
        };
        this.folderTree = (this.folderTree || []).map(n => markNode(n));
    }

    statusClassForFile(status) {
        let base = 'status-pill file-status';
        const normalized = status ? status.toLowerCase() : '';
        if (normalized === 'verified') return base + ' status-verified';
        if (normalized === 'recheck/reupload' || normalized === 'not applicable' || normalized === 'not application') return base + ' status-recheck';
        return base + ' status-submitted';
    }

    statusClassForFolder(status) {
        let base = 'status-pill folder-status';
        const normalized = status ? status.toLowerCase() : '';
        if (normalized === 'approved') return base + ' status-verified';
        if (normalized === 'recheck') return base + ' status-recheck';
        if (normalized === 'pending review') return base + ' status-pending';
        return base;
    }

    // ----- FOLDER EXPAND/COLLAPSE -----
    handleToggleFolder(event) {
        const folderId = event.currentTarget.dataset.id;
        const updated = this.toggleInTree(this.folderTree, folderId);
        this.folderTree = [...updated];
    }

    toggleInTree(nodes, folderId) {
        if (!nodes) return [];
        return nodes.map(n => {
            const clone = { ...n };
            if (clone.id === folderId) {
                clone.expanded = !clone.expanded;
            }
            if (clone.children && clone.children.length) {
                clone.children = this.toggleInTree(clone.children, folderId);
            }
            return clone;
        });
    }

    // ----- FILE EDIT -----
    handleEditFile(event) {
        const fileId = event.currentTarget.dataset.id;
        const file = this.findFileById(fileId, this.folderTree);
        if (!file) {
            this.showToast('Error', 'File not found.', 'error');
            return;
        }
        this.editFile = { ...file };
        this.isModalOpen = true;
    }

    findFileById(fileId, nodes) {
        if (!nodes) return null;
        for (let n of nodes) {
            if (n.files) {
                const found = n.files.find(f => f.id === fileId || f.Id === fileId);
                if (found) return found;
            }
            if (n.children) {
                const child = this.findFileById(fileId, n.children);
                if (child) return child;
            }
        }
        return null;
    }

    async handleViewFile(event) {
        const fileId = event.currentTarget.dataset.id;
        if (!fileId) return;
        this.viewLoadingId = fileId;
        this.updateViewState(fileId);
        try {
            const url = await getDownloadUrlApex({ fileId });
            if (url) {
                window.open(url, '_blank');
            } else {
                this.showToast('Error', 'Download link unavailable.', 'error');
            }
        } catch (e) {
            // eslint-disable-next-line no-console
            console.error('handleViewFile error', e);
            this.showToast(
                'Error',
                (e && e.body && e.body.message) || e.message || 'Unable to fetch download link.',
                'error'
            );
        } finally {
            this.viewLoadingId = null;
            this.updateViewState(null);
        }
    }

    async handleCalculateScore() {
        if (!this.recordId) return;
        this.isCalculating = true;
        try {
            const result = await calculateCreditScore({ leadId: this.recordId });
            if (result) {
                this.creditScore = result.creditScore;
                this.cpaEligibilityStatus = result.cpaEligibilityStatus;
                this.leadStatus = result.leadStatus || this.leadStatus;
                this.editCreditScore = result.creditScore;
                this.editCpaStatus = result.cpaEligibilityStatus;
                this.editLeadStatus = result.leadStatus || this.leadStatus;
            }
            this.showToast('Success', 'Eligibility score calculated.', 'success');
            await this.refreshTree();
        } catch (e) {
            // eslint-disable-next-line no-console
            console.error('Error calculating credit score', e);
            this.showToast(
                'Error',
                (e && e.body && e.body.message) || e.message || 'Unable to calculate eligibility score.',
                'error'
            );
        } finally {
            this.isCalculating = false;
        }
    }

    // ----- FOLDER COMMENT / STATUS -----
    handleFolderCommentClick(event) {
        const folderId = event.currentTarget.dataset.id;
        const folder = this.findFolderById(folderId, this.folderTree);

        if (!folder || !folder.allowFolderEdit) {
            this.showToast('Error', 'This folder cannot be edited.', 'error');
            return;
        }

        this.activeFolder = {
            id: folderId,
            name: folder ? folder.name : '',
            comment: folder ? folder.comments : '',
            status: folder ? folder.status : null
        };
        this.folderCommentText = this.activeFolder.comment || '';
        this.isFolderModalOpen = true;
    }

    handleFolderStatusChange(event) {
        if (!this.activeFolder) {
            this.activeFolder = {};
        }
        this.activeFolder = {
            ...this.activeFolder,
            status: event.detail.value
        };
    }

    findFolderById(folderId, nodes) {
        if (!nodes) return null;
        for (let n of nodes) {
            if (n.id === folderId) return n;
            if (n.children) {
                const child = this.findFolderById(folderId, n.children);
                if (child) return child;
            }
        }
        return null;
    }

    handleFolderCommentChange(event) {
        this.folderCommentText = event.target.value;
    }

    closeFolderModal() {
        this.isFolderModalOpen = false;
        this.activeFolder = {};
        this.folderCommentText = '';
    }

    async saveFolderComment() {
        if (!this.activeFolder || !this.activeFolder.id) {
            this.showToast('Error', 'Folder not found.', 'error');
            return;
        }

        const statusToSend = this.activeFolder.status || null;

        try {
            const res = await updateFolderStatusApex({
                folderId: this.activeFolder.id,
                status: statusToSend,
                comment: this.folderCommentText
            });

            if (res && res.success) {
                this.showToast('Success', 'Folder updated successfully.', 'success');
                this.closeFolderModal();
                await this.refreshTree();
            } else {
                this.showToast('Error', (res && res.message) || 'Error updating folder.', 'error');
            }
        } catch (e) {
            // eslint-disable-next-line no-console
            console.error('Unexpected error in saveFolderComment:', e);
            this.showToast(
                'Error',
                (e && e.body && e.body.message) || e.message || 'Unexpected error while saving folder details.',
                'error'
            );
        }
    }

    // ----- MODAL FORM (FILE) -----
    handleFieldChange(event) {
        const field = event.target.name;
        let value = event.target.value;

        this.editFile = {
            ...this.editFile,
            [field]: value
        };
    }

    closeModal() {
        this.isModalOpen = false;
        this.editFile = {};
    }

    async saveFile() {
        const fileId = this.editFile.id || this.editFile.Id;
        if (!fileId) {
            this.showToast('Error', 'Missing fileId on editFile.', 'error');
            // eslint-disable-next-line no-console
            console.error('saveFile called with invalid editFile:', JSON.stringify(this.editFile));
            return;
        }

        const s = this.editFile.status;
        const needsComment = s === 'Recheck/Reupload' || s === 'Not Applicable' || s === 'Not application';
        if (needsComment) {
            const c = (this.editFile.comment || '').trim();
            if (!c) {
                this.showToast('Error', 'Comment is required for Recheck/Reupload or Not Applicable.', 'error');
                return;
            }
        }

        const payload = {
            fileId: fileId,
            status: this.editFile.status,
            comment: this.editFile.comment
        };

        // eslint-disable-next-line no-console
        console.log('Save payload:', JSON.stringify(payload));

        try {
            const result = await saveFileApex({ inputJson: JSON.stringify(payload) });
            if (result && result.success) {
                this.showToast('Success', 'File updated successfully.', 'success');
                this.closeModal();
                await this.refreshTree();
            } else {
                this.showToast('Error', result ? result.message : 'Error saving file.', 'error');
            }
        } catch (e) {
            // eslint-disable-next-line no-console
            console.error('Unexpected error in saveFile:', e);
            this.showToast(
                'Error',
                (e && e.body && e.body.message) || e.message || 'Unexpected error while saving file.',
                'error'
            );
        }
    }

    async refreshTree() {
        try {
            if (this.wiredTreeResult) {
                await refreshApex(this.wiredTreeResult);
            }
            if (this.wiredLeadSnapshotResult) {
                await refreshApex(this.wiredLeadSnapshotResult);
            }
        } catch (e) {
            // eslint-disable-next-line no-console
            console.error(e);
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    openEditModal() {
        this.editCreditScore = this.creditScore;
        this.editCpaStatus = this.cpaEligibilityStatus;
        this.editLeadStatus = this.leadStatus;
        this.isEditModalOpen = true;
    }

    closeEditModal() {
        this.isEditModalOpen = false;
    }

    handleEditFieldChange(event) {
        const { name, value } = event.target;
        if (name === 'editCreditScore') {
            this.editCreditScore = value;
        } else if (name === 'editCpaStatus') {
            this.editCpaStatus = value;
        } else if (name === 'editLeadStatus') {
            this.editLeadStatus = value;
        }
    }

    async saveEligibilitySnapshot() {
        if (!this.recordId) return;
        const creditScoreValue = this.editCreditScore === '' || this.editCreditScore === undefined || this.editCreditScore === null
            ? null
            : Number(this.editCreditScore);

        try {
            const result = await saveEligibilitySnapshotApex({
                leadId: this.recordId,
                creditScore: creditScoreValue,
                cpaEligibilityStatus: this.editCpaStatus,
                leadStatus: this.editLeadStatus
            });

            if (result) {
                this.creditScore = result.creditScore;
                this.cpaEligibilityStatus = result.cpaEligibilityStatus;
                this.leadStatus = result.leadStatus;
                this.showToast('Saved', 'Eligibility details updated.', 'success');
            }
            this.isEditModalOpen = false;
            await this.refreshTree();
        } catch (e) {
            // eslint-disable-next-line no-console
            console.error('Error saving eligibility snapshot', e);
            this.showToast(
                'Error',
                (e && e.body && e.body.message) || e.message || 'Unable to save eligibility details.',
                'error'
            );
        }
    }
}