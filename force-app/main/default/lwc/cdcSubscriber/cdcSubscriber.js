import { LightningElement, track } from 'lwc';
import { subscribe, unsubscribe, onError } from 'lightning/empApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';

export default class CdcSubscriber extends NavigationMixin(LightningElement) {
    @track channelName = '/data/AccountChangeEvent';
    @track selectedObject = 'Account';
    @track isSubscribed = false;
    @track events = [];
    subscription = {};

    // Object options for quick selection
    objectOptions = [
        { label: 'Account', value: 'Account', channel: '/data/AccountChangeEvent' },
        { label: 'Contact', value: 'Contact', channel: '/data/ContactChangeEvent' },
        { label: 'Opportunity', value: 'Opportunity', channel: '/data/OpportunityChangeEvent' },
        { label: 'Lead', value: 'Lead', channel: '/data/LeadChangeEvent' },
        { label: 'Case', value: 'Case', channel: '/data/CaseChangeEvent' },
        { label: 'Custom Object', value: 'Custom', channel: '' }
    ];

    // Computed getters for button states
    get subscribeDisabled() {
        return this.isSubscribed || !this.channelName;
    }

    get unsubscribeDisabled() {
        return !this.isSubscribed;
    }

    get clearEventsDisabled() {
        return this.events.length === 0;
    }

    connectedCallback() {
        this.registerErrorListener();
    }

    disconnectedCallback() {
        if (this.isSubscribed) {
            this.handleUnsubscribe();
        }
    }

    handleObjectChange(event) {
        this.selectedObject = event.detail.value;
        const selectedOption = this.objectOptions.find(opt => opt.value === this.selectedObject);
        if (selectedOption && selectedOption.channel) {
            this.channelName = selectedOption.channel;
        }
    }

    handleChannelChange(event) {
        this.channelName = event.detail.value;
    }

    handleSubscribe() {
        if (!this.channelName) {
            this.showToast('Error', 'Please enter a channel name', 'error');
            return;
        }

        const messageCallback = (response) => {
            console.log('Received CDC event: ', JSON.stringify(response));
            this.processEvent(response);
        };

        subscribe(this.channelName, -1, messageCallback)
            .then(response => {
                this.subscription = response;
                this.isSubscribed = true;
                this.showToast('Success', `Subscribed to ${this.channelName}`, 'success');
            })
            .catch(error => {
                console.error('Subscription error: ', error);
                this.showToast('Subscription Failed', error.body?.message || error.message, 'error');
            });
    }

    handleUnsubscribe() {
        unsubscribe(this.subscription, response => {
            this.isSubscribed = false;
            this.showToast('Unsubscribed', `Stopped listening to ${this.channelName}`, 'info');
        });
    }

    registerErrorListener() {
        onError(error => {
            console.error('Streaming API Error: ', error);
            this.showToast('Streaming Error', 'Check console for details', 'warning');
        });
    }

    processEvent(response) {
        if (response.data && response.data.payload) {
            const payload = response.data.payload;
            const header = payload.ChangeEventHeader;
            
            if (!header) return;

            // Extract field values from payload
            const fieldValues = this.extractFieldValues(payload);
            
            const newEvent = {
                id: Date.now() + Math.random(),
                recordId: header.recordIds ? header.recordIds[0] : 'N/A',
                changeType: header.changeType,
                changedFields: header.changedFields ? header.changedFields.join(', ') : 'N/A',
                commitUser: header.commitUser || 'System',
                commitTimestamp: header.commitTimestamp,
                timestamp: new Date().toLocaleString(),
                payload: JSON.stringify(payload, null, 2),
                badgeClass: this.getBadgeClass(header.changeType),
                fieldValues: fieldValues
            };

            this.events = [newEvent, ...this.events.slice(0, 49)]; // Keep last 50 events
        }
    }

    extractFieldValues(payload) {
        const fieldValues = [];
        const fieldLabels = {
            'Name': 'Name',
            'Type': 'Type', 
            'Industry': 'Industry',
            'Phone': 'Phone',
            'Website': 'Website',
            'FirstName': 'First Name',
            'LastName': 'Last Name',
            'Email': 'Email',
            'Title': 'Title',
            'Department': 'Department'
        };
        
        // Remove metadata fields from payload
        const payloadCopy = {...payload};
        delete payloadCopy.ChangeEventHeader;
        
        // Extract each field value
        Object.keys(payloadCopy).forEach(fieldName => {
            if (fieldName && payloadCopy[fieldName] !== undefined && payloadCopy[fieldName] !== null) {
                const label = fieldLabels[fieldName] || fieldName;
                fieldValues.push({
                    name: fieldName,
                    label: label,
                    value: this.formatValue(payloadCopy[fieldName])
                });
            }
        });
        
        return fieldValues;
    }

    formatValue(value) {
        if (value === null || value === undefined) return '';
        if (typeof value === 'object') return JSON.stringify(value);
        return String(value);
    }

    getBadgeClass(changeType) {
        const classMap = {
            'CREATE': 'slds-theme_success',
            'UPDATE': 'slds-theme_warning', 
            'DELETE': 'slds-theme_error',
            'UNDELETE': 'slds-theme_alt-inverse'
        };
        return classMap[changeType] || 'slds-theme_default';
    }

    clearEvents() {
        this.events = [];
        this.showToast('Cleared', 'All events cleared', 'info');
    }

    handleRecordClick(event) {
        const recordId = event.currentTarget.dataset.recordid;
        if (recordId) {
            // Determine object type from record ID prefix
            let objectApiName = 'Account';
            if (recordId.startsWith('003')) objectApiName = 'Contact';
            if (recordId.startsWith('006')) objectApiName = 'Opportunity';
            if (recordId.startsWith('00Q')) objectApiName = 'Lead';
            if (recordId.startsWith('500')) objectApiName = 'Case';
            
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: recordId,
                    objectApiName: objectApiName,
                    actionName: 'view'
                }
            });
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({
            title,
            message,
            variant
        }));
    }
}