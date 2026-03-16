import { api, LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import createLead from '@salesforce/apex/CreateNewLeadController.createLead';
import getAvailableCourseTypes from '@salesforce/apex/CreateNewLeadController.getAvailableCourseTypes';

export default class CreateNewLead extends LightningElement {
    _recordId;
    isLoading = false;
    selectedCourseType = '';
    courseTypeOptions = [];
    
    @api
    get recordId() {
        return this._recordId;
    }

    set recordId(value) {
        this._recordId = value;
        if (value) {
            this.loadCourseTypes();
        }
    }

    get headerLabel() {
        return this.selectedCourseType ? `Create ${this.selectedCourseType} Lead` : 'Create Lead';
    }

    async loadCourseTypes() {
        if (!this.recordId) {
            return;
        }
        this.isLoading = true;
        try {
            const courseTypes = await getAvailableCourseTypes({ recordId: this.recordId });
            this.courseTypeOptions = (courseTypes || []).map((course) => ({
                label: course,
                value: course
            }));
            this.selectedCourseType = this.courseTypeOptions.length ? this.courseTypeOptions[0].value : '';
        } catch (e) {
            const message =
                e?.body?.message ||
                e?.message ||
                'Failed to load course types.';
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message,
                    variant: 'error'
                })
            );
        } finally {
            this.isLoading = false;
        }
    }

    handleCourseTypeChange(event) {
        this.selectedCourseType = event.detail.value;
    }

    get isCreateDisabled() {
        return this.isLoading || !this.selectedCourseType;
    }

    async handleCreate() {
        if (this.isCreateDisabled) return;
        this.isLoading = true;

        try {
            await createLead({
                recordId: this.recordId,
                courseType: this.selectedCourseType
            });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Success',
                    message: `${this.selectedCourseType} Lead created successfully.`,
                    variant: 'success'
                })
            );
            this.dispatchEvent(new CloseActionScreenEvent());
        } catch (e) {
            const message =
                e?.body?.message ||
                e?.message ||
                'Failed to create lead.';
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message,
                    variant: 'error'
                })
            );
        } finally {
            this.isLoading = false;
        }
    }

    handleCancel() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }
}