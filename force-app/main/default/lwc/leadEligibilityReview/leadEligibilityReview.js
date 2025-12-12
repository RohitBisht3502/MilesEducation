// file: force-app/main/default/lwc/leadEligibilityReview/leadEligibilityReview.js
import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';

import getFolderTree from '@salesforce/apex/EligibilityReviewController.getFolderTree';
import saveFileApex from '@salesforce/apex/EligibilityReviewController.saveFile';
import getFileFieldPicklists from '@salesforce/apex/EligibilityReviewController.getFileFieldPicklists';
import getLeadEligibilityStatus from '@salesforce/apex/EligibilityReviewController.getLeadEligibilityStatus';
import saveFolderCommentApex from '@salesforce/apex/EligibilityReviewController.saveFolderComment';
import updateFolderStatusApex from '@salesforce/apex/EligibilityReviewController.updateFolderStatus';
import getDownloadUrlApex from '@salesforce/apex/EligibilityReviewController.getDownloadUrl';

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

    folderStatusOptions = [
        { label: 'Pending Review', value: 'Pending Review' },
        { label: 'All Good', value: 'All Good' },
        { label: 'Recheck', value: 'Recheck' }
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
                cls += ' path-current';
            }
            return {
                label,
                value: label,
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

        // Folder status display (only for degree level)
        decorated.showStatus = decorated.folderType === 'Degree' && !!decorated.status;
        decorated.statusClass = this.statusClassForFolder(decorated.status);

        // Build a human-readable summary for top-level folders
        const summaryParts = [];
        if (counts.Verified > 0) summaryParts.push(`Verified: ${counts.Verified}`);
        if (counts.Recheck > 0) summaryParts.push(`Recheck: ${counts.Recheck}`);
        if (counts.Reupload_Required > 0) summaryParts.push(`Reupload: ${counts.Reupload_Required}`);
        if (counts.Submitted > 0) summaryParts.push(`Submitted: ${counts.Submitted}`);
        if (counts.Rejected > 0) summaryParts.push(`Rejected: ${counts.Rejected}`);

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

    statusClassForFile(status) {
        let base = 'status-pill file-status';
        if (status === 'Verified') return base + ' status-verified';
        if (status === 'Recheck' || status === 'Reupload_Required') return base + ' status-recheck';
        if (status === 'Rejected') return base + ' status-rejected';
        return base + ' status-submitted';
    }

    statusClassForFolder(status) {
        let base = 'status-pill folder-status';
        if (status === 'All Good') return base + ' status-verified';
        if (status === 'Recheck') return base + ' status-recheck';
        if (status === 'Pending Review') return base + ' status-pending';
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
        const needsComment = s === 'Recheck' || s === 'Rejected' || s === 'Reupload_Required';
        if (needsComment) {
            const c = (this.editFile.comment || '').trim();
            if (!c) {
                this.showToast('Error', 'Comment is required for Recheck / Rejected / Reupload.', 'error');
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
            if (this.wiredLeadStatusResult) {
                await refreshApex(this.wiredLeadStatusResult);
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