import { LightningElement, api, track, wire } from 'lwc';
import getSourceCounts from '@salesforce/apex/CandidateEnquirySourceController.getSourceCounts';

export default class CustomNavBar extends LightningElement {
    // Auto-provided on Record Page
    @api recordId;
    @api objectApiName;

    // Provided via App Builder
    @api sourceFieldApiName;
    @api candidateFieldApiName;

    @track tabs = [];
    @track latestSource = 'Sources';

    _hasRenderedOnce = false;

    // Wire Apex only when all params are available
    @wire(getSourceCounts, {
        recordId: '$recordId',
        objectApiName: '$objectApiName',
        sourceFieldApiName: '$sourceFieldApiName',
        candidateFieldApiName: '$candidateFieldApiName'
    })
    wiredCounts({ data, error }) {

        // 🔒 Guard clause – prevents invalid Apex calls
        if (
            !this.recordId ||
            !this.objectApiName ||
            !this.sourceFieldApiName ||
            !this.candidateFieldApiName
        ) {
            return;
        }

        if (data) {
            console.log('Apex Data:', JSON.stringify(data));

            // Remove empty / blank sources
            const filteredTabs = data.filter(
                item => item.source && item.source.trim() !== ''
            );

            // Sort by latest modified
            const sortedTabs = [...filteredTabs].sort(
                (a, b) => new Date(b.lastModified) - new Date(a.lastModified)
            );

            // Map to UI model
            this.tabs = sortedTabs.map(item => ({
                name: item.source,
                label: item.source,
                count: item.count,
                isNew: true
            }));

            // Set latest source title
            this.latestSource = sortedTabs.length
                ? sortedTabs[0].source
                : 'Sources';

        } else if (error) {
            console.error('Apex Error:', error);
        }
    }

    // Runs after DOM is ready
    renderedCallback() {
        if (this._hasRenderedOnce) return;
        this._hasRenderedOnce = true;

        // Debug logs (safe here)
        console.log('recordId:', this.recordId);
        console.log('objectApiName:', this.objectApiName);
        console.log('sourceFieldApiName:', this.sourceFieldApiName);
        console.log('candidateFieldApiName:', this.candidateFieldApiName);

        // Animate title
        const navTitle = this.template.querySelector('.nav-title');
        if (navTitle && this.tabs.length > 0) {
            navTitle.classList.add('blink-nav');
        }

        // Animate tabs
        const tabButtons = this.template.querySelectorAll('.tab-pill');
        tabButtons.forEach((btn, index) => {
            if (this.tabs[index]?.isNew) {
                btn.classList.add('blink-tab');
            }
        });
    }

    // Dynamic title class
    get navTitleClass() {
        return this.tabs.length > 0
            ? 'nav-title blink-nav'
            : 'nav-title';
    }

    // Dynamic tab class (used in HTML)
    getTabClass(tab) {
        return tab.isNew
            ? 'tab-pill blink-tab'
            : 'tab-pill';
    }
}