import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getRecord } from 'lightning/uiRecordApi';
import getUploadUuid from '@salesforce/apex/Callout_AWSFileUploader.getUploadUuid';
import getPresignedUrlForUpload from '@salesforce/apex/Callout_AWSFileUploader.getPresignedUrlForUpload';
import getPathOptions from '@salesforce/apex/EligibilityUploadPathService.getPathOptions';
import handleNewQualification from '@salesforce/apex/EligibilityFileService.handleNewQualification';
import handleMainFolderFilesJson from '@salesforce/apex/EligibilityFileService.handleMainFolderFilesJson';
import { CloseActionScreenEvent } from 'lightning/actions';
import { NavigationMixin } from 'lightning/navigation';

const ALLOWED_MIME_TO_EXT = {
  'application/pdf': 'pdf',
  'application/msword': 'doc',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document': 'docx',
  'image/jpeg': 'jpg',
  'image/jpg': 'jpg',
  'image/png': 'png',
  'text/plain': 'txt'
};

const ALLOWED_EXTENSIONS = new Set(['pdf', 'doc', 'docx', 'jpg', 'jpeg', 'png', 'txt']);

const EXTENSION_TO_MIME = {
  pdf: 'application/pdf',
  doc: 'application/msword',
  docx: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  jpg: 'image/jpeg',
  jpeg: 'image/jpeg',
  png: 'image/png',
  txt: 'text/plain'
};

const ALLOWED_EXTENSIONS_LABEL = 'pdf, doc, docx, jpg, jpeg, png, txt';

export default class FileUploader extends NavigationMixin(LightningElement) {
  @api recordId;
  @api objectApiName;
  @api uuidFieldApiName = 'UUID__c';

  @track uploading = false;
  @track lastResultMessage = '';
  @track errorMessage = '';
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
      const msg = this.getApexErrorMessage(error) || 'Failed to load folder options for upload.';
      this.toast('Error', msg, 'error');
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
      return this.joinPath(['eligibility_docs', this.flatTypeKey]).toLowerCase();
    }
    return this.joinPath([
      'eligibility_docs',
      this.selectedQualificationType,
      this.selectedQualificationTitle,
      this.selectedCategory
    ]).toLowerCase();
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
    const incoming = Array.from(e.target.files || []);
    if (!incoming.length) return;
    const invalid = [];
    const validIncoming = [];
    incoming.forEach((file) => {
      const allowedExt = this.getAllowedExtension(file);
      if (!allowedExt) {
        invalid.push(file.name);
      } else {
        validIncoming.push(file);
      }
    });

    if (invalid.length) {
      this.toast(
        'Error',
        `Unsupported file type: ${invalid.join(', ')}. Allowed: ${ALLOWED_EXTENSIONS_LABEL}.`,
        'error'
      );
    }

    const merged = [...this.files, ...validIncoming];
    const seen = new Set();
    const unique = [];
    merged.forEach((file) => {
      const key = `${file.name}:${file.size}:${file.lastModified}`;
      if (seen.has(key)) return;
      seen.add(key);
      unique.push(file);
    });
    this.files = unique;
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
    this.errorMessage = '';
    const successItems = [];
    const errorMessages = [];
    let success = 0, failed = 0;
    const folderPath = this.folderPath;
    const isFlat = this.isFlatTypeSelected;
    const logicalType = isFlat ? null : this.resolveLogicalType(this.selectedCategory);
    if (!isFlat && !logicalType) {
      this.uploading = false;
      this.toast('Error', 'Invalid document category selection.', 'error');
      return;
    }

    const invalidUploads = [];
    for (const file of this.files) {
      try {
        const extension = this.getAllowedExtension(file);
        if (!extension) {
          invalidUploads.push(file.name);
          failed += 1;
          continue;
        }
        const contentType = this.resolveContentType(extension, file.type);
        const fileUuid = await getUploadUuid();

        const presignedUrl = await getPresignedUrlForUpload({
          studentUuid: this.uuid,
          contentType,
          fileUuid,
          folderPath
        });
        console.log('preassinged urlllllll>', presignedUrl);
        await this.putToS3(presignedUrl, file, contentType);

        const storageFileName = `${fileUuid}.${extension}`;
        const filePath = this.joinPath([this.uuid, folderPath, storageFileName]);
        const fileName = file && file.name ? file.name : storageFileName;
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
        const msg = (e && e.body && e.body.message) || e.message || 'S3 upload failed.';
        errorMessages.push(`${file.name}: ${msg}`);
        // eslint-disable-next-line no-console
        console.error('Upload failed:', e);
      }
    }

    if (invalidUploads.length) {
      this.toast(
        'Error',
        `Unsupported file type: ${invalidUploads.join(', ')}. Allowed: ${ALLOWED_EXTENSIONS_LABEL}.`,
        'error'
      );
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
          // local validation already handled
        } else if (!result || result.success !== true) {
          const msg = result && result.message ? result.message : 'Files uploaded but failed to sync in Salesforce.';
          errorMessages.push(`Salesforce Sync: ${msg}`);
        } else {
          syncSucceeded = true;
        }
      } catch (error) {
        if (!syncSucceeded) {
          const msg = this.getApexErrorMessage(error) || 'Files uploaded but failed to sync in Salesforce.';
          errorMessages.push(`Sync Error: ${msg}`);
          this.toast('Warning', msg, 'warning');
        }
      }
    }

    this.uploading = false;
    this.lastResultMessage = `Uploaded: ${success} | Failed: ${failed}`;

    if (errorMessages.length > 0) {
      this.errorMessage = `Failure details: ${errorMessages.join('; ')}`;
    }

    // Modal Closing Strategy: Only close if 100% of files succeeded
    if (failed === 0 && (syncSucceeded || successItems.length === 0)) {
      this.toast('Success', 'All files uploaded and saved successfully.', 'success');
      this.closeAndNavigate();
    } else {
      this.toast('Partial Success', this.lastResultMessage, 'warning');
    }
  }

  async putToS3(url, file, contentType) {
    const response = await fetch(url, {
      method: 'PUT',
      headers: {
        'Content-Type': contentType || 'application/octet-stream'
      },
      body: file
    });

    if (!response.ok) {
      let responseText = '';
      try {
        responseText = await response.text();
      } catch (e) {
        // best effort only, not all responses return a readable body
      }
      throw new Error(
        `S3 upload failed. Status: ${response.status}${responseText ? ` | ${responseText}` : ''}`
      );
    }

    return response.status;
  }

  resolveContentType(extension, mimeType) {
    if (mimeType && ALLOWED_MIME_TO_EXT[mimeType.toLowerCase()]) {
      return mimeType;
    }
    if (extension && EXTENSION_TO_MIME[extension]) {
      return EXTENSION_TO_MIME[extension];
    }
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
    const normalized = contentType.toLowerCase();
    if (ALLOWED_MIME_TO_EXT[normalized]) {
      return ALLOWED_MIME_TO_EXT[normalized];
    }
    const parts = normalized.split('/');
    if (parts.length < 2 || !parts[1]) return '';
    return parts[1].toLowerCase();
  }

  getAllowedExtension(file) {
    if (!file) return '';
    const mime = file.type ? file.type.toLowerCase() : '';
    if (mime && ALLOWED_MIME_TO_EXT[mime]) {
      return ALLOWED_MIME_TO_EXT[mime];
    }
    const ext = this.getFileExtension(file.name);
    if (ext && ALLOWED_EXTENSIONS.has(ext)) {
      return ext;
    }
    return '';
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