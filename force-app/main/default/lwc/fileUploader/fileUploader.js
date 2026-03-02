import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getRecord } from 'lightning/uiRecordApi';
import getUploadUuid from '@salesforce/apex/Callout_AWSFileUploader.getUploadUuid';
import getPresignedUrlForUpload from '@salesforce/apex/Callout_AWSFileUploader.getPresignedUrlForUpload';
import uploadFileToS3 from '@salesforce/apex/Callout_AWSFileUploader.uploadFileToS3';
import getPathOptions from '@salesforce/apex/EligibilityUploadPathService.getPathOptions';
import handleNewQualification from '@salesforce/apex/EligibilityFileService.handleNewQualification';
import handleMainFolderFilesJson from '@salesforce/apex/EligibilityFileService.handleMainFolderFilesJson';
import { CloseActionScreenEvent } from 'lightning/actions';
import { NavigationMixin } from 'lightning/navigation';

export default class FileUploader extends NavigationMixin(LightningElement) {
  @api recordId;
  @api objectApiName;
  @api uuidFieldApiName = 'UUID__c';

  @track uploading = false;
  @track lastResultMessage = '';
  @track qualificationTypeOptions = [];
  @track qualificationTitleOptions = [];
  @track categoryOptions = [];
  @track degreeOptions = [];
  files = [];
  uuid;
  allQualificationTitleOptions = [];
  selectedQualificationType = '';
  selectedQualificationTitle = '';
  selectedCategory = '';

  @wire(getRecord, { recordId: '$recordId', fields: '$computedFields' })
  wiredRecord({ data }) {
    if (data) this.uuid = data.fields[this.uuidFieldApiName]?.value ?? null;
  }

  @wire(getPathOptions, { recordId: '$recordId', uuid: '$uuid' })
  wiredPathOptions({ data, error }) {
    if (data) {
      if (!this.uuid && data.uuid) {
        this.uuid = data.uuid;
      }
      this.degreeOptions = data.degreeOptions || [];
      this.allQualificationTitleOptions = data.qualificationTitles || [];
      this.qualificationTypeOptions = this.buildTypeOptions(data.qualificationTypes || []);
      this.categoryOptions = this.sortOptions(data.categories || []);
      this.refreshTitleOptions();
    } else if (error) {
      // eslint-disable-next-line no-console
      console.error('Failed to load path options', error);
      this.toast('Error', 'Failed to load folder options for upload.', 'error');
    }
  }

  get computedFields() {
    if (!this.objectApiName || !this.uuidFieldApiName) return [];
    return [`${this.objectApiName}.${this.uuidFieldApiName}`];
  }

  get hasPathSelection() {
    if (this.isFlatTypeSelected) {
      return !!this.selectedQualificationType;
    }
    return !!(this.selectedQualificationType && this.selectedQualificationTitle && this.selectedCategory);
  }

  get folderPath() {
    if (!this.hasPathSelection) return '';
    if (this.isFlatTypeSelected) {
      return this.joinPath(['eligibility_docs', this.flatTypeKey]);
    }
    return this.joinPath([
      'eligibility_docs',
      this.selectedQualificationType,
      this.selectedQualificationTitle,
      this.selectedCategory
    ]);
  }

  get isUploadDisabled() {
    return !this.uuid || this.files.length === 0 || this.uploading || !this.hasPathSelection;
  }

  get hasFiles() {
    return this.files && this.files.length > 0;
  }

  openFilePicker() {
    this.template.querySelector('.hidden-file-input').click();
  }

  handleFileChange(e) {
    this.files = Array.from(e.target.files || []);
    this.lastResultMessage = '';
  }

  handleQualificationTypeChange(e) {
    this.selectedQualificationType = e.detail.value;
    this.selectedQualificationTitle = '';
    if (this.isFlatTypeSelected) {
      this.selectedCategory = '';
    }
    this.refreshTitleOptions();
  }

  handleQualificationTitleChange(e) {
    this.selectedQualificationTitle = e.detail.value;
  }

  handleCategoryChange(e) {
    this.selectedCategory = e.detail.value;
  }

  removeFile(event) {
    const index = event.currentTarget.dataset.index;
    this.files.splice(index, 1);
    this.files = [...this.files];

    // Reset file input so same file can be selected again
    if (this.files.length === 0) {
      this.template.querySelector('.hidden-file-input').value = null;
    }
  }

  async upload() {
    if (!this.uuid) {
      this.toast('Error', `UUID field "${this.uuidFieldApiName}" is empty on this ${this.objectApiName} record.`, 'error');
      return;
    }
    if (!this.hasPathSelection) {
      this.toast('Error', 'Please select the qualification type, title, and document category.', 'error');
      return;
    }
    if (!this.files.length) return;

    this.uploading = true;
    this.lastResultMessage = '';
    const successItems = [];
    let success = 0, failed = 0;
    const folderPath = this.folderPath;
    const isFlat = this.isFlatTypeSelected;
    const logicalType = isFlat ? null : this.resolveLogicalType(this.selectedCategory);
    if (!isFlat && !logicalType) {
      this.uploading = false;
      this.toast('Error', 'Invalid document category selection.', 'error');
      return;
    }

    for (const file of this.files) {
      try {
        const extension =
          this.getFileExtension(file.name) ||
          this.getExtensionFromContentType(file.type) ||
          'bin';
        const contentType = this.buildContentType(extension);
        const fileUuid = await getUploadUuid();

        const presignedUrl = await getPresignedUrlForUpload({
          studentUuid: this.uuid,
          contentType,
          fileUuid,
          folderPath
        });

        await this.putToS3(presignedUrl, file, contentType, fileUuid);

        const fileName = `${fileUuid}.${extension}`;
        const filePath = this.joinPath([this.uuid, folderPath, fileName]);
        successItems.push({
          uuid: fileUuid,
          path: filePath,
          format: extension,
          fileType: logicalType,
          fileName
        });
        success += 1;
      } catch (e) {
        failed += 1;
        // eslint-disable-next-line no-console
        console.error('Upload failed:', e);
      }
    }

    let syncSucceeded = false;
    if (successItems.length) {
      let result;
      try {
        if (isFlat) {
          const incoming = successItems.map((item) => ({
            uuid: item.uuid,
            path: item.path,
            format: item.format,
            fileType: item.fileType,
            fileName: item.fileName
          }));
          const hasMissing = incoming.some((item) => !item.uuid || !item.path);
          if (hasMissing) {
            const msg = 'Upload metadata missing (uuid/path).';
            this.toast('Error', msg, 'error');
            result = { success: false, message: msg, _localError: true };
          } else {
            result = await handleMainFolderFilesJson({
              salesforceId: this.recordId || this.uuid,
              flatFolderKey: this.flatTypeKey,
              incomingJson: JSON.stringify(incoming)
            });
          }
        } else {
          const payload = {
            salesforceId: this.recordId || this.uuid,
            qualificationType: this.selectedQualificationType,
            qualificationTitle: this.selectedQualificationTitle,
            qualificationMonthYear: null,
            certificateFiles: logicalType === 'Certificate' ? successItems : [],
            marksheetFiles: logicalType === 'Marksheet' ? successItems : []
          };
          result = await handleNewQualification({ inputJson: JSON.stringify(payload) });
          console.log('Upload sync result:', result);
        }
        // eslint-disable-next-line no-console
        console.log('Upload sync result:', result);
        if (result && result._localError) {
          // local validation already handled via toast
        } else if (!result || result.success !== true) {
            const msg = result && result.message ? result.message : 'Files uploaded but failed to sync in Salesforce.';
            //this.toast('Warning', msg, 'warning');
          } else {
            syncSucceeded = true;
            this.toast('Success', 'Files uploaded and saved successfully.', 'success');
            this.closeAndNavigate();
          }
        } catch (error) {
          if (!syncSucceeded) {
            const msg = this.getApexErrorMessage(error) || 'Files uploaded but failed to sync in Salesforce.';
            this.toast('Warning', msg, 'warning');
          }
        }
    }

    this.uploading = false;
    this.lastResultMessage = `Uploaded: ${success} | Failed: ${failed}`;
    this.toast(failed === 0 ? 'Success' : 'Partial Success', this.lastResultMessage, failed === 0 ? 'success' : 'warning');
  }

  async putToS3(url, file, contentType, fileUuid) {
    const base64Body = await this.readFileAsBase64(file);
    if (!base64Body) throw new Error('File read failed (empty body).');
    return uploadFileToS3({ presignedUrl: url, base64Body, contentType, fileUuid });
  }

  readFileAsBase64(file) {
    return new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onerror = () => reject(new Error('Failed to read file.'));
      reader.onload = () => {
        const result = reader.result;
        if (typeof result !== 'string') {
          reject(new Error('Failed to read file.'));
          return;
        }
        const parts = result.split(',');
        resolve(parts.length > 1 ? parts[1] : '');
      };
      reader.readAsDataURL(file);
    });
  }

  buildContentType(extension) {
    if (extension) return `application/${extension}`;
    return 'application/octet-stream';
  }

  getFileExtension(fileName) {
    if (!fileName) return '';
    const idx = fileName.lastIndexOf('.');
    if (idx <= 0 || idx === fileName.length - 1) return '';
    return fileName.substring(idx + 1).toLowerCase();
  }

  getExtensionFromContentType(contentType) {
    if (!contentType || typeof contentType !== 'string') return '';
    const parts = contentType.split('/');
    if (parts.length < 2 || !parts[1]) return '';
    return parts[1].toLowerCase();
  }

  resolveLogicalType(categoryValue) {
    if (!categoryValue) return null;
    const normalized = categoryValue.toLowerCase();
    if (normalized.includes('mark')) return 'Marksheet';
    if (normalized.includes('cert')) return 'Certificate';
    return null;
  }

  get flatTypeKey() {
    return this.getFlatTypeKey(this.selectedQualificationType);
  }

  get isFlatTypeSelected() {
    return !!this.flatTypeKey;
  }

  get isTitleDisabled() {
    return this.isFlatTypeSelected;
  }

  get isCategoryDisabled() {
    return this.isFlatTypeSelected;
  }

  buildTypeOptions(fallbackOptions) {
    const map = new Map();
    (fallbackOptions || []).forEach((opt) => {
      if (!opt || !opt.value) return;
      const label = opt.label || opt.value;
      if (!map.has(opt.value)) {
        map.set(opt.value, { label, value: opt.value });
      }
    });

    if (this.degreeOptions && this.degreeOptions.length) {
      this.degreeOptions.forEach((opt) => {
        const value = opt.typeValue;
        if (!value) return;
        const label = opt.typeLabel || value;
        if (!map.has(value)) {
          map.set(value, { label, value });
        }
      });
    }

    return this.sortOptions(Array.from(map.values()));
  }

  refreshTitleOptions() {
    if (this.isFlatTypeSelected) {
      this.qualificationTitleOptions = [];
      return;
    }
    if (this.degreeOptions && this.degreeOptions.length) {
      const map = new Map();
      this.degreeOptions.forEach((opt) => {
        if (this.selectedQualificationType && opt.typeValue !== this.selectedQualificationType) return;
        const value = opt.titleValue;
        if (!value || map.has(value)) return;
        const label = opt.titleLabel || value;
        map.set(value, { label, value });
      });
      this.qualificationTitleOptions = this.sortOptions(Array.from(map.values()));
      return;
    }
    this.qualificationTitleOptions = this.sortOptions(this.allQualificationTitleOptions || []);
  }

  sortOptions(options) {
    return (options || [])
      .slice()
      .sort((a, b) => (a.label || '').toLowerCase().localeCompare((b.label || '').toLowerCase()));
  }

  getFlatTypeKey(rawValue) {
    if (!rawValue) return '';
    const normalized = String(rawValue).toLowerCase().replace(/\s+/g, '_').replace(/-/g, '_');
    if (normalized.includes('resume')) return 'resume';
    if (normalized.includes('work') && normalized.includes('experience')) return 'work_experience';
    if (normalized === 'work_experience') return 'work_experience';
    return '';
  }

  joinPath(parts) {
    return (parts || [])
      .filter((part) => part !== null && part !== undefined && String(part).trim() !== '')
      .map((part) => String(part).replace(/^\/+|\/+$/g, ''))
      .join('/');
  }

  toast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }

  closeAndNavigate() {
    try {
      this.dispatchEvent(new CloseActionScreenEvent());
    } catch (e) {
      // ignore if not running in a quick action context
    }
    if (this.recordId) {
      this[NavigationMixin.Navigate]({
        type: 'standard__recordPage',
        attributes: {
          recordId: this.recordId,
          actionName: 'view'
        }
      });
    }
  }

  getApexErrorMessage(error) {
    if (!error) return '';
    if (Array.isArray(error.body)) {
      return error.body.map((e) => e.message).filter(Boolean).join(' | ');
    }
    if (error.body && typeof error.body.message === 'string') {
      return error.body.message;
    }
    if (typeof error.message === 'string') {
      return error.message;
    }
    return '';
  }
}