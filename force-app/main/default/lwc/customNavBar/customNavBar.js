import { LightningElement, api, track, wire } from 'lwc';
import getNavData from '@salesforce/apex/SobjectNavBarController.getNavData';
import ROADMAP_IMG from '@salesforce/resourceUrl/Roadmap';
import GMEET_IMG from '@salesforce/resourceUrl/Gmeet';
import OFFICE_VISIT_IMG from '@salesforce/resourceUrl/OfficeVisitLight';

const BLINK_DURATION = 5000; // ⏱ 5 seconds

export default class CustomNavBar extends LightningElement {
    @api recordId;

    @track enquiryTabs = [];
    @track webinarTabs = [];
    @track eventTabs = [];
    @track latestSource = 'Sources';
    @track blinkActive = false;

    blinkTimeout;

    @wire(getNavData, { recordId: '$recordId' })
    wiredNav({ data, error }) {
        if (!this.recordId) return;

        if (data) {
            const latestSource = data.latestSource;
            this.latestSource = this.formatSourceLabel(latestSource || 'Sources');

            // 🔔 Enable blinking only if a real latest source exists
            this.blinkActive = !!latestSource;

            const mapTabs = (arr, type) =>
                (arr || [])
                    .filter(i => i && i.source && i.source.trim() !== '')
                    .map(i => {
                        const isNew = this.blinkActive && i.source === latestSource;
                        let label = i.source;
                        let iconName = 'utility:record';
                        let iconUrl = null;
                        if (type === 'event') {
                            const isOffline = (i.source || '').toLowerCase() === 'offline';
                            iconName = isOffline ? 'utility:company' : 'utility:video';
                            iconUrl = isOffline ? OFFICE_VISIT_IMG : GMEET_IMG;
                            label = isOffline ? 'Office Visit' : 'GMEET';
                        } else if (type === 'webinar') {
                            iconName = 'utility:trail';
                            iconUrl = ROADMAP_IMG;
                        }
                        return {
                            name: i.source,
                            label,
                            count: i.count,
                            iconName,
                            iconUrl,
                            useImage: !!iconUrl,
                            isNew,
                            tabClass: isNew
                                ? (iconUrl ? 'tab-icon-only blink-tab' : 'tab-pill blink-tab')
                                : (iconUrl ? 'tab-icon-only' : 'tab-pill')
                        };
                    });

            this.enquiryTabs = mapTabs(data.enquiry, 'enquiry');
            this.webinarTabs = mapTabs(data.webinar, 'webinar');
            this.eventTabs = mapTabs(data.events, 'event');

            // ⏱ Stop blinking after X seconds
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

        const clearBlink = (tabs) =>
            tabs.map(tab => ({
                ...tab,
                isNew: false,
                tabClass: tab.useImage ? 'tab-icon-only' : 'tab-pill'
            }));

        this.enquiryTabs = clearBlink(this.enquiryTabs);
        this.webinarTabs = clearBlink(this.webinarTabs);
        this.eventTabs = clearBlink(this.eventTabs);
    }

    get navTitleClass() {
        return this.blinkActive ? 'nav-title blink-nav' : 'nav-title';
    }

    get navHeader() {
        return this.recordId && this.recordId.startsWith('001') ? 'Account Sources' : 'Lead Sources';
    }

    formatSourceLabel(source) {
        const normalized = (source || '').toLowerCase();
        if (normalized === 'online') return 'GMEET';
        if (normalized === 'offline') return 'Office Visit';
        return source;
    }

    handleImageError(event) {
        const group = event.target.dataset.group;
        const tabName = event.target.dataset.name;
        if (!group || !tabName) return;

        const hideBrokenImage = (tabs) =>
            tabs.map(tab => (tab.name === tabName ? { ...tab, useImage: false } : tab));

        if (group === 'enquiry') {
            this.enquiryTabs = hideBrokenImage(this.enquiryTabs);
        } else if (group === 'webinar') {
            this.webinarTabs = hideBrokenImage(this.webinarTabs);
        } else if (group === 'event') {
            this.eventTabs = hideBrokenImage(this.eventTabs);
        }
    }




    renderedCallback() {
        if (this._hasRenderedOnce) return;
        this._hasRenderedOnce = true;

        console.log('recordId:', this.recordId);

        const navTitle = this.template.querySelector('.nav-title');
        if (navTitle && (this.enquiryTabs.length > 0 || this.webinarTabs.length > 0 || this.eventTabs.length > 0)) {
            navTitle.classList.add('blink-nav');
        }

        const tabButtons = this.template.querySelectorAll('.tab-pill');
        tabButtons.forEach((btn) => btn.classList.add('blink-tab'));
    }
}