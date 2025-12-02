import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';

import getFolderTree from '@salesforce/apex/EligibilityReviewController.getFolderTree';
import saveFileApex from '@salesforce/apex/EligibilityReviewController.saveFile';
import getFileFieldPicklists from '@salesforce/apex/EligibilityReviewController.getFileFieldPicklists';
import getLeadEligibilityStatus from '@salesforce/apex/EligibilityReviewController.getLeadEligibilityStatus';
import saveFolderCommentApex from '@salesforce/apex/EligibilityReviewController.saveFolderComment';

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

    @track isFolderModalOpen = false;
    @track activeFolder = {};
    @track folderCommentText = '';

    wiredTreeResult;
    wiredLeadStatusResult;

    statusOptions = [
        { label: 'Submitted', value: 'Submitted' },
        { label: 'Verified', value: 'Verified' },
        { label: 'Reupload Required', value: 'Reupload_Required' },
        { label: 'Recheck', value: 'Recheck' },
        { label: 'Rejected', value: 'Rejected' }
    ];

    connectedCallback() {
        this.initYearOptions();
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
        } else if (error) {
            // eslint-disable-next-line no-console
            console.error(error);
            this.showToast('Error', 'Error loading eligibility folders', 'error');
        }
    }

    @wire(getLeadEligibilityStatus, { leadId: '$recordId' })
    wiredLeadStatus(result) {
        this.wiredLeadStatusResult = result;
        const { data, error } = result;
        if (data) {
            this.leadStatus = data;
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
            this.universityOptions = u.map(v => ({ label: v, value: v }));
            this.gradeOptions = g.map(v => ({ label: v, value: v }));
            this.rankOptions = r.map(v => ({ label: v, value: v }));
        } else if (error) {
            // eslint-disable-next-line no-console
            console.error(error);
        }
    }

    initYearOptions() {
        const currentYear = new Date().getFullYear();
        const years = [];
        for (let y = currentYear; y >= currentYear - 50; y--) {
            const s = String(y);
            years.push({ label: s, value: s });
        }
        this.yearOptions = years;
    }

    get hasData() {
        return this.folderTree && this.folderTree.length > 0;
    }

    get hasAnyFile() {
        return this.totalFilesOverall > 0;
    }

    get showCommentField() {
        const s = this.editFile?.status;
        return s === 'Recheck' || s === 'Rejected' || s === 'Reupload_Required';
    }

    // PATH ITEMS FOR GP_Lead_Status__c
    get pathItems() {
        const labels = [
            'New lead',
            'Verification',
            'Verified',
            'Recheck',
            'Crosscheck (USP Process)',
            'Not eligible',
            'Refund'
        ];

        const order = {
            'New lead': 1,
            'Verification': 2,
            'Verified': 3,
            'Recheck': 4,
            'Crosscheck (USP Process)': 5,
            'Not eligible': 6,
            'Refund': 7
        };

        const current = this.leadStatus || 'New lead';
        const currentOrder = order[current] || order['New lead'];

        return labels.map(label => {
            const stepOrder = order[label];
            let cls = 'path-step';
            if (stepOrder < currentOrder) {
                cls += ' path-completed';
            } else if (stepOrder === currentOrder) {
                cls += ' path-active';
            }
            return {
                label,
                value: label,
                className: cls
            };
        });
    }

    // ----- DECORATION / FLAGS -----
    decorateTree(nodes, level) {
        if (!nodes) return [];
        return nodes.map(node => this.decorateNode(node, level));
    }

    decorateNode(node, level) {
        const decorated = { ...node };

        decorated.level = level;
        decorated.expanded = false;

        if (level === 1) {
            if (decorated.qualificationType === 'UG' || decorated.name === 'UG') {
                decorated.subtitle = 'Undergraduate Degree';
            } else if (decorated.qualificationType === 'PG' || decorated.name === 'PG') {
                decorated.subtitle = 'Postgraduate Degree';
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
        decorated.comments = decorated.comments || null;

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
        const counts = {
            Verified: 0,
            Recheck: 0,
            Reupload_Required: 0,
            Submitted: 0,
            Rejected: 0
        };

        if (decorated.children && decorated.children.length) {
            decorated.children.forEach(ch => {
                if (ch.statusCounts) {
                    counts.Verified += ch.statusCounts.Verified;
                    counts.Recheck += ch.statusCounts.Recheck;
                    counts.Reupload_Required += ch.statusCounts.Reupload_Required;
                    counts.Submitted += ch.statusCounts.Submitted;
                    counts.Rejected += ch.statusCounts.Rejected;
                }
            });
        }

        if (decorated.files && decorated.files.length) {
            decorated.files.forEach(file => {
                const st = file.status;
                if (st && counts.hasOwnProperty(st)) {
                    counts[st] = counts[st] + 1;
                } else {
                    counts.Submitted = counts.Submitted + 1;
                }
            });
        }

        decorated.statusCounts = counts;
        const totalFiles =
            counts.Verified +
            counts.Recheck +
            counts.Reupload_Required +
            counts.Submitted +
            counts.Rejected;

        decorated.totalFiles = totalFiles;
        decorated.showStatus = totalFiles > 0;

        // Status pill class (based on folder status)
        decorated.statusClass = this.statusClassForFolder(decorated.status);

        // Status summary string
        const summaryParts = [];
        if (counts.Verified > 0) summaryParts.push(`Verified: ${counts.Verified}`);
        if (counts.Recheck > 0) summaryParts.push(`Recheck: ${counts.Recheck}`);
        if (counts.Reupload_Required > 0) summaryParts.push(`Reupload: ${counts.Reupload_Required}`);
        if (counts.Submitted > 0) summaryParts.push(`Submitted: ${counts.Submitted}`);
        if (counts.Rejected > 0) summaryParts.push(`Rejected: ${counts.Rejected}`);

        decorated.statusSummary = summaryParts.join(' | ');

        return decorated;
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
        });
        return sum;
    }

    statusClassForFolder(status) {
        const base = 'status-pill ';
        switch (status) {
            case 'All Good':
                return base + 'status-good';
            case 'Recheck':
                return base + 'status-recheck';
            default:
                return base + 'status-pending';
        }
    }

    statusClassForFile(status) {
        const base = 'status-pill status-small ';
        switch (status) {
            case 'Verified':
                return base + 'status-good';
            case 'Recheck':
                return base + 'status-recheck';
            case 'Reupload_Required':
            case 'Rejected':
                return base + 'status-reupload';
            default:
                return base + 'status-pending';
        }
    }

    iconNameForFile(formatOrName) {
        if (!formatOrName) {
            return 'doctype:attachment';
        }

        let val = String(formatOrName).toLowerCase();

        if (val.includes('.')) {
            const parts = val.split('.');
            val = parts[parts.length - 1];
        }

        if (val === 'pdf') {
            return 'doctype:pdf';
        }
        if (val === 'png' || val === 'jpg' || val === 'jpeg' || val === 'gif' || val === 'bmp') {
            return 'doctype:image';
        }
        if (val === 'xls' || val === 'xlsx' || val === 'csv') {
            return 'doctype:excel';
        }
        if (val === 'doc' || val === 'docx') {
            return 'doctype:word';
        }
        return 'doctype:attachment';
    }

    // ----- EXPAND / COLLAPSE -----
    handleToggleFolder(event) {
        const folderId = event.currentTarget.dataset.id;
        if (!folderId) return;
        this.folderTree = this.toggleInNodes(this.folderTree, folderId);
    }

    toggleInNodes(nodes, folderId) {
        return nodes.map(n => this.toggleInNode(n, folderId));
    }

    toggleInNode(node, folderId) {
        const updated = { ...node };
        if (updated.id === folderId) {
            updated.expanded = !updated.expanded;
        }
        if (updated.children && updated.children.length) {
            updated.children = updated.children.map(child => this.toggleInNode(child, folderId));
        }
        return updated;
    }

    // ----- FILE VIEW & EDIT -----
    handleViewFile(event) {
        const fileId = event.currentTarget.dataset.id;
        const file = this.findFileById(fileId);
        if (file && file.storageKey) {
            window.open(file.storageKey, '_blank');
        } else {
            this.showToast('Info', 'File link not available.', 'info');
        }
    }

    handleEditFile(event) {
        const fileId = event.currentTarget.dataset.id;
        const file = this.findFileById(fileId);
        if (!file) {
            this.showToast('Error', 'File not found.', 'error');
            return;
        }
        this.editFile = {
            ...file,
            id: file.id || file.Id
        };
        this.isModalOpen = true;
        // eslint-disable-next-line no-console
        console.log('Edit file opened:', JSON.stringify(this.editFile));
    }

    findFileById(fileId) {
        if (!this.folderTree) return null;

        const search = (nodes) => {
            for (let n of nodes) {
                if (n.files) {
                    const found = n.files.find(f => f.id === fileId || f.Id === fileId);
                    if (found) return found;
                }
                if (n.children) {
                    const inChild = search(n.children);
                    if (inChild) return inChild;
                }
            }
            return null;
        };

        return search(this.folderTree);
    }

    // ----- FOLDER COMMENT -----
    handleFolderCommentClick(event) {
        const folderId = event.currentTarget.dataset.id;
        const folder = this.findFolderById(folderId, this.folderTree);
        this.activeFolder = {
            id: folderId,
            name: folder ? folder.name : '',
            comment: folder ? folder.comments : ''
        };
        this.folderCommentText = this.activeFolder.comment || '';
        this.isFolderModalOpen = true;
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
        try {
            const res = await saveFolderCommentApex({
                folderId: this.activeFolder.id,
                comment: this.folderCommentText
            });

            if (res && res.success) {
                this.showToast('Success', 'Comment saved successfully.', 'success');
                this.closeFolderModal();
                await this.refreshTree();
            } else {
                this.showToast('Error', (res && res.message) || 'Error saving comment.', 'error');
            }
        } catch (e) {
            // eslint-disable-next-line no-console
            console.error('Unexpected error in saveFolderComment:', e);
            this.showToast(
                'Error',
                (e && e.body && e.body.message) || e.message || 'Unexpected error while saving comment.',
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
        const needsComment = s === 'Recheck' || s === 'Rejected' || s === 'Reupload_Required';
        if (needsComment) {
            const c = (this.editFile.comment || '').trim();
            if (!c) {
                this.showToast('Error', 'Comment is required for Recheck / Rejected / Reupload.', 'error');
                return;
            }
        }

        try {
            const payload = {
                fileId: fileId,
                status: this.editFile.status,
                comment: this.editFile.comment
            };

            // eslint-disable-next-line no-console
            console.log('Save payload:', JSON.stringify(payload));

            const result = await saveFileApex({ inputJson: JSON.stringify(payload) });

            // eslint-disable-next-line no-console
            console.log('Save result:', JSON.stringify(result));

            if (result && result.success) {
                this.showToast('Success', 'File updated successfully.', 'success');
                this.isModalOpen = false;
                this.editFile = {};
                await this.refreshTree();
                if (this.wiredLeadStatusResult) {
                    await refreshApex(this.wiredLeadStatusResult);
                }
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
        } catch (e) {
            // eslint-disable-next-line no-console
            console.error(e);
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}