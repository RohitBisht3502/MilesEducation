import { LightningElement, api, track, wire } from 'lwc';
import getNavData from '@salesforce/apex/SobjectNavBarController.getNavData';

const BLINK_DURATION = 5000; // ⏱ 5 seconds

export default class CustomNavBar extends LightningElement {
    @api recordId;

    @track enquiryTabs = [];
    @track webinarTabs = [];
    @track latestSource = 'Sources';
    @track blinkActive = false;

    blinkTimeout;

    @wire(getNavData, { recordId: '$recordId' })
    wiredNav({ data, error }) {
        if (!this.recordId) return;

        if (data) {
            const latestSource = data.latestSource;
            this.latestSource = latestSource || 'Sources';

            // 🔔 Enable blinking only if a real latest source exists
            this.blinkActive = !!latestSource;

            const mapTabs = (arr) =>
                (arr || [])
                    .filter(i => i && i.source && i.source.trim() !== '')
                    .map(i => {
                        const isNew = this.blinkActive && i.source === latestSource;
                        return {
                            name: i.source,
                            label: i.source,
                            count: i.count,
                            isNew,
                            tabClass: isNew
                                ? 'tab-pill blink-tab'
                                : 'tab-pill'
                        };
                    });

            this.enquiryTabs = mapTabs(data.enquiry);
            this.webinarTabs = mapTabs(data.webinar);

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
                tabClass: 'tab-pill'
            }));

        this.enquiryTabs = clearBlink(this.enquiryTabs);
        this.webinarTabs = clearBlink(this.webinarTabs);
    }

    get navTitleClass() {
        return this.blinkActive ? 'nav-title blink-nav' : 'nav-title';
    }



  renderedCallback() {
        if (this._hasRenderedOnce) return;
        this._hasRenderedOnce = true;

        console.log('recordId:', this.recordId);

        const navTitle = this.template.querySelector('.nav-title');
        if (navTitle && (this.enquiryTabs.length > 0 || this.webinarTabs.length > 0)) {
            navTitle.classList.add('blink-nav');
        }

        const tabButtons = this.template.querySelectorAll('.tab-pill');
        tabButtons.forEach((btn) => btn.classList.add('blink-tab'));
    }
}