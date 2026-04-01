import { LightningElement, track, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { loadStyle } from 'lightning/platformResourceLoader';
import getUserLeads from '@salesforce/apex/LeadQueueManagementController.getUserLeads';
import navBarOverride from '@salesforce/resourceUrl/navBarOverride';
import openSansFont from '@salesforce/resourceUrl/openSansFont';

export default class LeadQueueManagementCopy extends LightningElement {
    @track leads = [];
    @track selectedQueue = 'All';
    @track queueList = [];
    navBarStyleLoaded = false;

    queueRunning = false;
    currentLeadId = null;
    currentIsCallLog = false;
    currentPrimaryTag = null;
    currentCandidateId = null;

    pausedLeadId = null;

    countdown = 0;
    remainingCountdown = 0;
    countdownTimerId = null;
    isWaiting = false;
    isQueuePaused = false;

    showCallUI = false;

    totalLeads = 0;
    callsCompleted = 0;
    remainingLeads = 0;
    isRefreshing = false;

    sessionTimerSeconds = 0;
    sessionTimerId = null;
    sessionStarted = false;

    inQueueRefreshTimerId = null;

    wiredResult;

    // ── Lifecycle ──

    renderedCallback() {
        if (this.navBarStyleLoaded) return;
        this.navBarStyleLoaded = true;
        loadStyle(this, navBarOverride)
            .then(() => { /* nav bar style loaded */ })
            .catch(err => console.error('Failed to load nav bar override CSS', err));
        loadStyle(this, openSansFont)
            .catch(err => console.error('Failed to load Open Sans font', err));
    }

    disconnectedCallback() {
        this.clearCountdown();
        this.stopSessionTimer();
        if (this.inQueueRefreshTimerId) {
            clearInterval(this.inQueueRefreshTimerId);
            this.inQueueRefreshTimerId = null;
        }
    }

    // ── Wire ──

    @wire(getUserLeads)
    wiredLeads(result) {
        this.wiredResult = result;
        const { data, error } = result;

        if (data) {
            const seenCallLogPhones = new Set();

            const filtered = data.filter(item => {
                if (!item.iscallLog) return true;

                const raw = item.phone || '';
                const normalized = raw.replace(/\D/g, '');
                const key = normalized || item.id;

                if (seenCallLogPhones.has(key)) return false;
                seenCallLogPhones.add(key);
                return true;
            });

            this.leads = filtered.map((item, i) => ({
                ...item,
                rowNumber: i + 1,
                primaryTagLabel: item.primaryTag || 'NA',
                bucketLabel: item.bucketTag || item.source || 'NA',
                levelLabel: item.stage || '--',
                courseLabel: item.course || 'NA',
                cityLabel: item.city || 'NA',
                candidateIdDisplay: item.candidateCode || 'N/A',
                queueName: item.queueName || item.primaryTag || 'NA',
                queueLabel: item.queueName || item.primaryTag || 'NA',
                recordObjectApiName: item.iscallLog ? 'Call_Log__c' : 'Lead__c',
                queueDotClass: this.getQueueDotClass(item.primaryTag),
                bucketBadgeClass: this.getBucketBadgeClass(item.bucketTag || item.source),
                inQueueSince: this.computeInQueueSince(item.createdDate),
                inQueueClass: this.isInQueueUrgent(item.createdDate) ? 'in-queue urgent' : 'in-queue',
                primaryTagClass: this.getPrimaryTagClass(item.primaryTag),
                bucketClass: this.getBucketClass(item.source),
                levelClass: this.getLevelClass(item.stage)
            }));

            this.totalLeads = this.leads.length;
            this.remainingLeads = this.totalLeads;
            this.callsCompleted = 0;
            this.buildQueueList();
            this.startInQueueRefresh();
        }

        if (error) {
            console.error('Lead load failed', error);
        }
    }

    // ── Computed Getters ──

    get filteredLeads() {
        if (this.selectedQueue === 'All') {
            return this.leads;
        }
        return this.leads.filter(l => l.queueLabel === this.selectedQueue);
    }

    get hasFilteredLeads() {
        return this.filteredLeads && this.filteredLeads.length > 0;
    }

    get hasLeads() {
        return this.leads && this.leads.length > 0;
    }

    get showingCount() {
        return this.filteredLeads.length;
    }

    get disableStart() {
        return this.queueRunning || !this.hasLeads;
    }

    get disableEnd() {
        return !this.queueRunning;
    }

    get disablePause() {
        return !this.queueRunning;
    }

    get disableResume() {
        return this.queueRunning || !this.isQueuePaused;
    }

    get showStartButton() {
        return !this.queueRunning && !this.isQueuePaused;
    }

    get showPauseButton() {
        return this.queueRunning;
    }

    get showResumeButton() {
        return !this.queueRunning && this.isQueuePaused;
    }

    get sessionTimerDisplay() {
        const h = Math.floor(this.sessionTimerSeconds / 3600);
        const m = Math.floor((this.sessionTimerSeconds % 3600) / 60);
        return String(h).padStart(2, '0') + ':' + String(m).padStart(2, '0');
    }

    get sessionTimerClass() {
        if (this.sessionStarted && this.queueRunning) return 'ss-value green';
        if (this.sessionStarted && this.isQueuePaused) return 'ss-value amber';
        return 'ss-value gray';
    }

    get currentlyWorkingLabel() {
        if (this.currentLeadId && this.leads.length > 0) {
            const current = this.leads.find(l => l.id === this.currentLeadId);
            return current ? (current.primaryTag || 'Queue') : '--';
        }
        return '--';
    }

    get showCurrentBadge() {
        return this.queueRunning && this.currentLeadId != null;
    }

    // ── Session Timer ──

    startSessionTimer() {
        this.stopSessionTimer();
        this.sessionTimerId = setInterval(() => {
            this.sessionTimerSeconds++;
        }, 1000);
    }

    stopSessionTimer() {
        if (this.sessionTimerId) {
            clearInterval(this.sessionTimerId);
            this.sessionTimerId = null;
        }
    }

    // ── In Queue Since Refresh ──

    startInQueueRefresh() {
        if (this.inQueueRefreshTimerId) {
            clearInterval(this.inQueueRefreshTimerId);
        }
        this.inQueueRefreshTimerId = setInterval(() => {
            this.leads = this.leads.map(lead => ({
                ...lead,
                inQueueSince: this.computeInQueueSince(lead.createdDate),
                inQueueClass: this.isInQueueUrgent(lead.createdDate) ? 'in-queue urgent' : 'in-queue'
            }));
        }, 60000);
    }

    // ── Queue List Builder ──

    buildQueueList() {
        const tagCounts = {};
        this.leads.forEach(lead => {
            const tag = lead.queueLabel || 'NA';
            tagCounts[tag] = (tagCounts[tag] || 0) + 1;
        });

        if (this.selectedQueue !== 'All' && !tagCounts[this.selectedQueue]) {
            this.selectedQueue = 'All';
        }

        const order = ['Missed calls', 'Untracked calls', 'Todays', 'Delays', 'MHP', 'NE'];
        const orderedTags = [];
        order.forEach(tag => {
            if (tagCounts[tag]) orderedTags.push(tag);
        });
        Object.keys(tagCounts).forEach(tag => {
            if (!orderedTags.includes(tag)) orderedTags.push(tag);
        });

        const list = [{
            name: 'All',
            dotClass: 'queue-dot all-q',
            count: this.leads.length,
            itemClass: 'queue-item' + (this.selectedQueue === 'All' ? ' active' : ''),
            countClass: 'queue-item-count' + (this.selectedQueue === 'All' ? ' active' : '')
        }];

        orderedTags.forEach(tag => {
            list.push({
                name: tag,
                dotClass: this.getQueueDotClass(tag),
                count: tagCounts[tag],
                itemClass: 'queue-item' + (this.selectedQueue === tag ? ' active' : ''),
                countClass: 'queue-item-count' + (this.selectedQueue === tag ? ' active' : '')
            });
        });

        this.queueList = list;
    }

    handleQueueSelect(event) {
        this.selectedQueue = event.currentTarget.dataset.queue;
        this.buildQueueList();
    }

    // ── Style Helpers ──

    getQueueDotClass(tag) {
        const t = (tag || '').toLowerCase();
        if (t === 'missed calls') return 'queue-dot missed';
        if (t === 'untracked calls') return 'queue-dot untracked';
        if (t === 'todays') return 'queue-dot todays';
        if (t === 'delays') return 'queue-dot delays';
        if (t === 'mhp') return 'queue-dot mhp';
        if (t === 'ne') return 'queue-dot ne';
        return 'queue-dot default-q';
    }

    getBucketBadgeClass(bucket) {
        if (!bucket || bucket === 'NA' || bucket === 'ALL') return 'badge badge-bucket-na';
        const b = bucket.toLowerCase().replace(/[\s_]+/g, '');
        if (b.includes('bucket1') || b === '1') return 'badge badge-bucket-1';
        if (b.includes('bucket2') || b === '2') return 'badge badge-bucket-2';
        if (b.includes('bucket3') || b === '3') return 'badge badge-bucket-3';
        if (b.includes('bucket4') || b === '4') return 'badge badge-bucket-4';
        if (b.includes('bucket5') || b === '5') return 'badge badge-bucket-5';
        return 'badge badge-bucket-na';
    }

    computeInQueueSince(createdDate) {
        if (!createdDate) return '--';
        const now = new Date();
        const created = new Date(createdDate);
        let diffMs = now - created;
        if (diffMs < 0) diffMs = 0;
        const totalMinutes = Math.floor(diffMs / 60000);
        const d = Math.floor(totalMinutes / 1440);
        const h = Math.floor((totalMinutes % 1440) / 60);
        const m = totalMinutes % 60;
        return `${d}d ${h}h ${m}m`;
    }

    isInQueueUrgent(createdDate) {
        if (!createdDate) return false;
        const diffMs = new Date() - new Date(createdDate);
        return diffMs > 2 * 24 * 60 * 60 * 1000;
    }

    getPrimaryTagClass(tag) {
        const t = (tag || '').toLowerCase();
        if (t === 'untracked calls') return 'pill pill-blue';
        if (t === 'ne' || t === 'mhp') return 'pill pill-cyan';
        if (t === 'delays') return 'pill pill-amber';
        return 'pill pill-gray';
    }

    getBucketClass(bucket) {
        if (!bucket || bucket === 'NA') return 'pill pill-gray';
        return 'pill pill-green';
    }

    getLevelClass(level) {
        if (!level || level === 'NA' || level === '--') return 'pill pill-gray';
        return 'pill pill-slate';
    }

    // ── Refresh ──

    async handleRefresh() {
        if (this.isRefreshing) return;

        this.isRefreshing = true;
        try {
            await refreshApex(this.wiredResult);
            this.remainingLeads = this.leads.length;
            this.buildQueueList();
        } catch (e) {
            console.error('Manual refresh failed', e);
        } finally {
            this.isRefreshing = false;
        }
    }

    // ── Queue Control ──

    handleStart() {
        if (!this.hasLeads) return;
        if (this.queueRunning) return;

        this.isQueuePaused = false;
        this.pausedLeadId = null;
        this.isWaiting = false;
        this.remainingCountdown = 0;
        this.clearCountdown();

        this.sessionTimerSeconds = 0;
        this.sessionStarted = true;
        this.startSessionTimer();

        this.queueRunning = true;
        this.pickNextLead();
    }

    handleEnd() {
        this.queueRunning = false;
        this.isQueuePaused = false;
        this.clearCountdown();
        this.showCallUI = false;
        this.currentLeadId = null;
        this.currentIsCallLog = false;
        this.currentPrimaryTag = null;
        this.currentCandidateId = null;
        this.remainingCountdown = 0;
        this.pausedLeadId = null;

        this.stopSessionTimer();
        this.sessionStarted = false;
        this.sessionTimerSeconds = 0;
    }

    handlePause() {
        if (!this.queueRunning) return;

        this.queueRunning = false;
        this.isQueuePaused = true;
        this.clearCountdown();
        this.remainingCountdown = this.countdown;
        this.pausedLeadId = this.currentLeadId;

        this.stopSessionTimer();
    }

    handlePauseFromChild() {
        this.handlePause();
        this.showCallUI = false;
        this.currentLeadId = null;
        this.currentIsCallLog = false;
        this.currentPrimaryTag = null;
        this.currentCandidateId = null;
    }

    handleResumeFromChild() {
        this.handleResume();
    }

    handleResume() {
        if (this.queueRunning || this.leads.length === 0) return;

        this.queueRunning = true;
        this.isQueuePaused = false;
        this.startSessionTimer();

        if (this.pausedLeadId) {
            const row = this.leads.find(l => l.id === this.pausedLeadId);

            if (row) {
                this.currentLeadId = row.id;
                this.currentIsCallLog = row.iscallLog ? true : false;
                this.currentPrimaryTag = row.primaryTag || null;
                this.currentCandidateId = row.candidateId || null;
                this.pausedLeadId = null;
                this.showCallUI = true;

                setTimeout(() => {
                    const cmp = this.template.querySelector('c-runo-allocation-calls-copy');
                    if (cmp) {
                        cmp.startCall();
                    }
                }, 0);

                return;
            }

            this.pausedLeadId = null;
        }

        if (this.remainingCountdown > 0) {
            this.startCountdown(this.remainingCountdown);
        } else {
            this.pickNextLead();
        }
    }

    startCurrentCall() {
        const cmp = this.template.querySelector('c-runo-allocation-calls-copy');

        if (cmp && typeof cmp.startCall === 'function') {
            cmp.startCall();
        } else {
            console.error('startCall not found in child component.');
        }
    }

    async handleCallComplete(event) {
        const detail = event.detail;

        this.callsCompleted++;

        if (this.pausedLeadId === detail.recordId) {
            this.pausedLeadId = null;
        }

        this.leads = this.leads.filter(l => l.id !== detail.recordId);

        try {
            await refreshApex(this.wiredResult);
        } catch (e) {
            console.error('Apex refresh failed:', e);
        }

        this.remainingLeads = this.leads.length;
        this.buildQueueList();
        this.showCallUI = false;
        this.currentLeadId = null;
        this.currentIsCallLog = false;
        this.currentPrimaryTag = null;
        this.currentCandidateId = null;

        if (detail?.stopQueue) {
            this.queueRunning = false;
            this.isQueuePaused = true;
            this.clearCountdown();
            this.remainingCountdown = 0;
            this.stopSessionTimer();
            return;
        }

        if (this.queueRunning && !this.isQueuePaused) {
            this.remainingCountdown = 1;
            this.startCountdown(this.remainingCountdown);
        }
    }

    // ── Countdown ──

    startCountdown(sec) {
        this.isWaiting = true;
        this.countdown = sec;

        this.clearCountdown();

        this.countdownTimerId = setInterval(() => {
            this.countdown--;
            this.remainingCountdown = this.countdown;

            if (this.countdown <= 0) {
                this.clearCountdown();
                this.isWaiting = false;
                this.remainingCountdown = 0;
                this.pickNextLead();
            }
        }, 1000);
    }

    clearCountdown() {
        if (this.countdownTimerId) {
            clearInterval(this.countdownTimerId);
            this.countdownTimerId = null;
        }
    }

    // ── Queue Progression ──

    pickNextLead() {
        if (!this.queueRunning) return;

        if (this.leads.length === 0) {
            this.queueRunning = false;
            this.currentLeadId = null;
            this.currentIsCallLog = false;
            this.currentPrimaryTag = null;
            this.currentCandidateId = null;
            return;
        }

        if (this.pausedLeadId) {
            return;
        }

        if (!this.showCallUI) {
            const queueLeads = this.filteredLeads;
            if (!queueLeads.length) {
                this.queueRunning = false;
                return;
            }
            this.currentLeadId = queueLeads[0].id;
            this.currentIsCallLog = queueLeads[0].iscallLog ? true : false;
            this.currentPrimaryTag = queueLeads[0].primaryTag || null;
            this.currentCandidateId = queueLeads[0].candidateId || null;
            this.showCallUI = true;
        }

        const handler = () => {
            this.startCurrentCall();
            this.template.removeEventListener('componentready', handler);
        };

        this.template.addEventListener('componentready', handler);
    }
}