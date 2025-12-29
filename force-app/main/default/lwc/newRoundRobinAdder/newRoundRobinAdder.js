import { LightningElement, api, wire } from 'lwc';
import getPicklists from '@salesforce/apex/RoundRobinMatrixController.getPicklists';
import getSalesReps from '@salesforce/apex/RoundRobinMatrixController.getSalesReps';
import createRoundRobinEntry from '@salesforce/apex/RoundRobinMatrixController.createRoundRobinEntry';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class NewRoundRobinAdder extends LightningElement {

    @api objectApiName;

    showModal = false;

    // dropdown data
    cities = [];
    leadSources = [];
    courses = [];
    types = [];
    salesReps = [];

    // selected values
    selectedCity;
    selectedSource;
    selectedRep;
    selectedCourse;
    selectedType;
    weight;

    /* ================= OPEN / CLOSE ================= */

    @api open() {
        this.showModal = true;
    }

    close() {
        this.showModal = false;
    }

    stopPropagation(event) {
        event.stopPropagation();
    }

    /* ================= LOAD PICKLISTS ================= */

    @wire(getPicklists)
    wiredPicklists({ data, error }) {
        if (data) {
            this.cities = data.cities || [];
            this.leadSources = data.leadSources || [];
            this.courses = data.courses || [];
            this.types = data.types || [];
        } else if (error) {
            this.showError(error);
        }
    }

    /* ================= LOAD SALES REPS ================= */

    @wire(getSalesReps)
    wiredSalesReps({ data, error }) {
        if (data) {
            this.salesReps = data.map(user => ({
                label: user.Name,
                value: user.Id
            }));
        } else if (error) {
            this.showError(error);
        }
    }

    /* ================= HANDLERS ================= */

    handleCityChange(e) { this.selectedCity = e.target.value; }
    handleSourceChange(e) { this.selectedSource = e.target.value; }
    handleRepChange(e) { this.selectedRep = e.target.value; }
    handleCourseChange(e) { this.selectedCourse = e.target.value; }
    handleTypeChange(e) { this.selectedType = e.target.value; }
    handleWeightChange(e) { this.weight = e.target.value; }

    /* ================= SAVE ================= */

    save() {
        createRoundRobinEntry({
            city: this.selectedCity,
            leadSource: this.selectedSource,
            salesRepId: this.selectedRep,
            course: this.selectedCourse,
            typeVal: this.selectedType,
            weight: this.weight,
            objectApiName: this.objectApiName
        })
        .then(() => {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Success',
                    message: 'Round Robin entry created successfully',
                    variant: 'success'
                })
            );

            this.dispatchEvent(new CustomEvent('success'));
            this.close();
        })
        .catch(error => {
            this.showError(error);
        });
    }

    /* ================= ERROR HANDLER ================= */

    showError(error) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Error',
                message: error.body?.message || 'Something went wrong',
                variant: 'error'
            })
        );
    }
}