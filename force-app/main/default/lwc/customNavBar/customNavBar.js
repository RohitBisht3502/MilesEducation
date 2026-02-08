import { LightningElement, api, track, wire } from 'lwc';
import getNavData from '@salesforce/apex/SobjectNavBarController.getNavData';
import ROADMAP_IMG from '@salesforce/resourceUrl/Roadmap';
import GMEET_IMG from '@salesforce/resourceUrl/Gmeet';
import OFFICE_VISIT_IMG from '@salesforce/resourceUrl/OfficeVisitLight';
import MILES_ONE_IMG from '@salesforce/resourceUrl/MILES_ONE_IMG';

const BLINK_DURATION = 5000;

export default class CustomNavBar extends LightningElement {
    @api recordId;

    @track enquiryTabs = [];
    @track latestSource = 'Sources';
    @track blinkActive = false;

    blinkTimeout;

    @wire(getNavData, { recordId: '$recordId' })
    wiredNav({ data, error }) {
        if (!this.recordId) return;

        if (data) {
            const latestSource = data.latestSource;
            this.latestSource = this.formatSourceLabel(latestSource || 'Sources');
            this.blinkActive = !!latestSource;

            this.enquiryTabs = (data.enquiry || [])
                .filter((item) => item && item.source && item.source.trim() !== '')
                .map((item) => {
                    const source = item.source || '';
                    const normalized = source.toLowerCase();
                    const isNew = this.blinkActive && source === latestSource;

                    let label = this.formatSourceLabel(source);
                    let iconUrl = null;

                    if (normalized === 'zoom webinar') {
                        iconUrl = ROADMAP_IMG;
                        label = 'Zoom Webinar';
                    } else if (normalized === 'gmeet online') {
                        iconUrl = GMEET_IMG;
                        label = 'Gmeet Online';
                    } else if (normalized === 'gmeet visit') {
                        iconUrl = OFFICE_VISIT_IMG;
                        label = 'Gmeet Visit';
                    } else if (normalized === 'miles one app') {
                        iconUrl = MILES_ONE_IMG;
                        label = 'Miles One App';
                    }

                    return {
                        name: source,
                        label,
                        count: item.count,
                        iconUrl,
                        useImage: !!iconUrl,
                        isNew,
                        tabClass: isNew
                            ? (iconUrl ? 'tab-icon-only blink-tab' : 'tab-pill blink-tab')
                            : (iconUrl ? 'tab-icon-only' : 'tab-pill')
                    };
                });

            clearTimeout(this.blinkTimeout);
            if (this.blinkActive) {
                this.blinkTimeout = setTimeout(() => {
                    this.stopBlinking();
                }, BLINK_DURATION);
            }
        } else if (error) {
            console.error('Apex Error:', error);
        }
    }

    stopBlinking() {
        this.blinkActive = false;
        this.enquiryTabs = this.enquiryTabs.map((tab) => ({
            ...tab,
            isNew: false,
            tabClass: tab.useImage ? 'tab-icon-only' : 'tab-pill'
        }));
    }

    get navTitleClass() {
        return this.blinkActive ? 'nav-title blink-nav' : 'nav-title';
    }

    formatSourceLabel(source) {
        const normalized = (source || '').toLowerCase();
        if (normalized === 'online') return 'GMEET';
        if (normalized === 'offline') return 'GVISIT';
        return source;
    }

    handleImageError(event) {
        const tabName = event.target.dataset.name;
        if (!tabName) return;

        this.enquiryTabs = this.enquiryTabs.map((tab) =>
            tab.name === tabName ? { ...tab, useImage: false } : tab
        );
    }
}