// file: force-app/main/default/lwc/gPFolderFilesView/gPFolderFilesView.js
import { LightningElement, api, wire, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getStudentFileTree from '@salesforce/apex/StudentGPFileController.getStudentFileTree';
import getDownloadUrlForLwc from '@salesforce/apex/EligibilityDatalakeClient.getDownloadUrlForLwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class GPFolderFilesView extends NavigationMixin(LightningElement) {
    @api recordId;
    @track courseNodes = [];
    isLoading = false;
    isViewingFile = false;
    error;

    @wire(getStudentFileTree, { accountId: '$recordId' })
    wiredTree({ data, error }) {
        this.isLoading = true;
        if (data) {
            // changes by rohit - 2026-04-07: flatten nested GP folders into a simple file list per step/course
            this.courseNodes = (data || []).map(course => ({
                ...course,
                folderLabel: this.buildFolderLabel(course),
                files: this.collectFiles(course.folderTree || []).map(file => this.decorateFile(file)),
                isExpanded: true,
                toggleIcon: 'utility:chevrondown'
            }));
            this.isLoading = false;
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.isLoading = false;
            this.courseNodes = [];
        }
    }

    // changes by rohit - 2026-04-07: show only step + course in the GP folder heading
    buildFolderLabel(course) {
        const step = course?.step || '';
        const courseName = course?.courseName || '';
        return [step, courseName].filter(Boolean).join(' + ');
    }

    // changes by rohit - 2026-04-07: hide intermediate gp_tool/course/step folders and show student files directly
    collectFiles(nodes = []) {
        let files = [];

        (nodes || []).forEach(node => {
            if (node?.files?.length) {
                files = files.concat(node.files);
            }
            if (node?.children?.length) {
                files = files.concat(this.collectFiles(node.children));
            }
        });

        return files;
    }

    // changes by rohit - 2026-04-07: normalize file status for compact badge UI
    decorateFile(file) {
        const status = String(file?.status || '').toLowerCase();
        let badgeClass = 'status-badge status-under-review';
        let badgeLabel = 'Under Review';

        if (status.includes('approve') || status.includes('verif')) {
            badgeClass = 'status-badge status-approved';
            badgeLabel = 'Approved';
        } else if (status.includes('reject')) {
            badgeClass = 'status-badge status-rejected';
            badgeLabel = 'Rejected';
        }

        return {
            ...file,
            badgeClass,
            badgeLabel
        };
    }

    // changes by rohit - 2026-04-07: allow folder-level toggle in simplified GP view
    handleToggleFolder(event) {
        const courseName = event.currentTarget?.dataset?.course;
        if (!courseName) return;

        this.courseNodes = (this.courseNodes || []).map(course => (
            course.courseName === courseName
                ? {
                    ...course,
                    isExpanded: !course.isExpanded,
                    toggleIcon: course.isExpanded ? 'utility:chevronright' : 'utility:chevrondown'
                }
                : course
        ));
    }

    handleNavigateRecord(event) {
        const recordId = event.detail?.recordId || event.currentTarget?.dataset?.recordId;
        if (!recordId) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: recordId,
                actionName: 'view'
            }
        });
    }

    async handleViewFile(event) {
        const filePath = event.detail?.filePath || event.currentTarget?.dataset?.filePath;
        if (!filePath) return;

        try {
            // changes by rohit - 2026-04-07: show spinner while file url is being fetched
            this.isViewingFile = true;
            const url = await getDownloadUrlForLwc({ filePath });
            if (url) {
                window.open(url, '_blank', 'noopener');
            } else {
                this.showToast('Error', 'File URL not available.', 'error');
            }
        } catch (e) {
            this.showToast('Error', 'Failed to fetch file URL.', 'error');
        } finally {
            this.isViewingFile = false;
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    get hasData() {
        return this.courseNodes && this.courseNodes.length > 0;
    }

    get totalDocuments() {
        return (this.courseNodes || []).reduce((count, course) => count + ((course.files || []).length), 0);
    }
}