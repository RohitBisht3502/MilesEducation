import { LightningElement, api } from 'lwc';
import getInitData from '@salesforce/apex/EligibilityEmailQuickActionController.getInitData';
import sendEligibilityEmail from '@salesforce/apex/EligibilityEmailQuickActionController.sendEligibilityEmail';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';

export default class EligibilityEmailQuickAction extends LightningElement {
    _recordId;
    _initRequested = false;

    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        this._recordId = value || null;
        this.queueInit();
    }

    isLoading = true;
    isSending = false;
    currentStep = 'details';

    recordType = '';
    recordName = '';
    candidateName = '';
    uuid = '';
    eligibilityStatus = '';
    gpStatus = '';
    score = null;
    eligibilityCode = '';
    email = '';
    ownerName = '';
    gpOwnerName = '';
    totalFiles = 0;
    fileStatusCounts = [];

    templates = [];
    templateOptions = [];
    templateMap = {};
    selectedTemplateId;
    selectedTemplateName = '';
    emailSubject = '';
    emailBody = '';

    connectedCallback() {
        this.queueInit();
    }

    queueInit() {
        if (this._initRequested || !this._recordId) return;
        this._initRequested = true;
        this.loadInitData();
    }

    async loadInitData() {
        this.isLoading = true;
        try {
            const data = await getInitData({ recordId: this.recordId });
            this.applyInitData(data);
        } catch (e) {
            // eslint-disable-next-line no-console
            console.error(e);
            this.showToast('Error', this.reduceError(e) || 'Unable to load eligibility email details.', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    applyInitData(data) {
        const payload = data || {};
        this.recordType = payload.recordType || '';
        this.recordName = payload.recordName || '';
        this.candidateName = payload.candidateName || payload.recordName || '';
        this.uuid = payload.uuid || '';
        this.eligibilityStatus = payload.eligibilityStatus || '';
        this.gpStatus = payload.gpStatus || '';
        this.score = payload.score;
        this.eligibilityCode = payload.eligibilityCode || '';
        this.email = payload.email || '';
        this.ownerName = payload.ownerName || '';
        this.gpOwnerName = payload.gpOwnerName || '';
        this.totalFiles = payload.totalFiles || 0;

        this.fileStatusCounts = (payload.fileStatusCounts || []).map(stat => ({
            ...stat,
            className: this.statusClassForFile(stat.status)
        }));

        this.templates = payload.templates || [];
        this.templateOptions = this.templates.map(t => ({
            label: t.name,
            value: t.id
        }));

        this.templateMap = {};
        this.templates.forEach(t => {
            this.templateMap[t.id] = t;
        });
    }

    get isDetailsStep() {
        return this.currentStep === 'details';
    }

    get isTemplateStep() {
        return this.currentStep === 'template';
    }

    get detailsStepClass() {
        return this.isDetailsStep ? 'path-step path-current' : 'path-step path-completed';
    }

    get templateStepClass() {
        return this.isTemplateStep ? 'path-step path-current' : 'path-step';
    }

    get recordTypeLabel() {
        return this.recordType || 'Record';
    }

    get recordNameDisplay() {
        return this.recordName || '--';
    }

    get uuidDisplay() {
        return this.uuid || '--';
    }

    get eligibilityStatusDisplay() {
        return this.eligibilityStatus || '--';
    }

    get gpStatusDisplay() {
        return this.gpStatus || '--';
    }

    get scoreDisplay() {
        return this.score === null || this.score === undefined ? '--' : this.score;
    }

    get eligibilityCodeDisplay() {
        return this.eligibilityCode || '--';
    }

    get emailDisplay() {
        return this.email || '--';
    }

    get ownerNameDisplay() {
        return this.ownerName || '--';
    }

    get gpOwnerNameDisplay() {
        return this.gpOwnerName || '--';
    }

    get totalFilesDisplay() {
        return this.totalFiles || 0;
    }

    get hasFileCounts() {
        return this.fileStatusCounts && this.fileStatusCounts.length > 0;
    }

    get hasTemplateSelected() {
        return !!this.selectedTemplateId;
    }

    get isEmailMissing() {
        return !this.email;
    }

    get isNextDisabled() {
        return this.isLoading;
    }

    get isSendDisabled() {
        return this.isSending || !this.selectedTemplateId || !this.email;
    }

    get selectedTemplateNameDisplay() {
        return this.selectedTemplateName || '--';
    }

    handleNext() {
        this.currentStep = 'template';
    }

    handleBack() {
        this.currentStep = 'details';
    }

    handleCancel() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    handleTemplateChange(event) {
        this.selectedTemplateId = event.detail.value;
        const tmpl = this.templateMap[this.selectedTemplateId];
        this.selectedTemplateName = tmpl ? tmpl.name : '';
        const rawSubject = tmpl ? tmpl.subject : '';
        const rawBody = tmpl ? tmpl.content : '';
        this.emailSubject = this.applyTemplatePlain(rawSubject);
        this.emailBody = this.applyTemplate(rawBody);
    }

    handleSubjectChange(event) {
        this.emailSubject = event.detail.value;
    }

    handleBodyChange(event) {
        this.emailBody = event.detail.value;
    }

    async handleSend() {
        if (this.isSendDisabled) {
            return;
        }
        this.isSending = true;
        try {
            await sendEligibilityEmail({
                recordId: this.recordId,
                templateId: this.selectedTemplateId,
                subject: this.emailSubject,
                body: this.emailBody
            });
            this.showToast('Success', 'Eligibility email sent successfully.', 'success');
            this.dispatchEvent(new CloseActionScreenEvent());
        } catch (e) {
            // eslint-disable-next-line no-console
            console.error(e);
            this.showToast('Error', this.reduceError(e) || 'Unable to send email.', 'error');
        } finally {
            this.isSending = false;
        }
    }

    applyTemplate(content) {
        let output = content || '';
        output = output.split('XXX').join(this.escapeHtml(this.candidateName || this.recordName));
        output = output.split('YYY').join(this.escapeHtml(this.ownerName));
        output = output.split('ZZZ').join(this.escapeHtml(this.gpOwnerName));
        return output;
    }

    applyTemplatePlain(content) {
        let output = content || '';
        output = output.split('XXX').join(this.candidateName || this.recordName || '');
        output = output.split('YYY').join(this.ownerName || '');
        output = output.split('ZZZ').join(this.gpOwnerName || '');
        return output;
    }

    escapeHtml(value) {
        if (!value) return '';
        return String(value)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/\"/g, '&quot;')
            .replace(/'/g, '&#39;');
    }

    statusClassForFile(status) {
        let base = 'status-pill';
        const normalized = status ? status.toLowerCase() : '';
        if (normalized === 'verified') return `${base} status-verified`;
        if (normalized === 'recheck/reupload' || normalized === 'not applicable' || normalized === 'not application') {
            return `${base} status-recheck`;
        }
        if (normalized === 'rejected') return `${base} status-rejected`;
        if (normalized === 'submitted') return `${base} status-submitted`;
        return `${base} status-pending`;
    }

    reduceError(error) {
        if (error && error.body) {
            if (Array.isArray(error.body)) {
                return error.body.map(e => e.message).join(', ');
            }
            if (error.body.message) {
                return error.body.message;
            }
        }
        return error && error.message ? error.message : null;
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}