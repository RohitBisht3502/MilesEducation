import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import loadDashboard from '@salesforce/apex/WorkdayManagementService.loadDashboard';
import startDay from '@salesforce/apex/WorkdayManagementService.startDay';
import startBreak from '@salesforce/apex/WorkdayManagementService.startBreak';
import endBreak from '@salesforce/apex/WorkdayManagementService.endBreak';
import endDay from '@salesforce/apex/WorkdayManagementService.endDay';

export default class WorkdayManagement extends LightningElement {
    @track dashboard;
    @track isLoading = false;
    @track liveTimerLabel = '00:00:00';

    timerIntervalId;

    connectedCallback() {
        this.startLiveTimer();
        this.refreshDashboard(true);
    }

    disconnectedCallback() {
        this.stopLiveTimer();
    }

    get state() {
        return this.dashboard?.state || 'NOT_STARTED';
    }

    get today() {
        return this.dashboard?.today;
    }

    get employeeName() {
        return this.dashboard?.employeeName || 'Workday User';
    }

    get stateLabel() {
        return this.dashboard?.stateLabel || 'Not Started';
    }

    get motivationalLine() {
        return (
            this.dashboard?.motivationalLine ||
            'Start your day to begin attendance tracking.'
        );
    }

    get todayBreaks() {
        return this.dashboard?.todayBreaks || [];
    }

    get hasTodayBreaks() {
        return this.todayBreaks.length > 0;
    }

    get canStartDay() {
        return this.state === 'NOT_STARTED';
    }

    get canStartBreak() {
        return this.state === 'ACTIVE';
    }

    get canEndBreak() {
        return this.state === 'ON_BREAK';
    }

    get canEndDay() {
        return this.state === 'ACTIVE';
    }

    get actionsDisabled() {
        return this.isLoading || !this.dashboard?.employeeActive;
    }

    get statePillClass() {
        if (this.state === 'ACTIVE') {
            return 'state-pill state-pill-active';
        }
        if (this.state === 'ON_BREAK') {
            return 'state-pill state-pill-break';
        }
        if (this.state === 'NOT_STARTED') {
            return 'state-pill state-pill-not-started';
        }
        return 'state-pill state-pill-ended';
    }

    get teamLabel() {
        const team = this.dashboard?.team ? this.dashboard.team : 'Unassigned Team';
        return `Team: ${team}`;
    }

    refreshDashboard(showSpinner) {
        if (showSpinner) {
            this.isLoading = true;
        }
        loadDashboard()
            .then(response => {
                this.dashboard = this.decorateResponse(response);
                this.updateLiveTimer();
            })
            .catch(error => {
                this.handleError(error);
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    decorateResponse(response) {
        const normalized = { ...(response || {}) };
        normalized.today = normalized.today
            ? {
                  ...normalized.today,
                  totalBreakLabel: this.formatMinutes(normalized.today.totalBreakMinutes),
                  grossHoursLabel: this.formatHours(normalized.today.grossWorkHours),
                  netHoursLabel: this.formatHours(normalized.today.netWorkHours)
              }
            : null;

        normalized.todayBreaks = (normalized.todayBreaks || []).map(item => ({
            ...item,
            rowClass: item.isOpen ? 'break-row break-open' : 'break-row',
            durationLabel: this.formatMinutes(item.durationMinutes)
        }));

        normalized.lastSevenDays = (normalized.lastSevenDays || []).map(row => ({
            ...row,
            rowBadgeClass: `history-badge ${row.statusClass || 'status-ended'}`,
            totalBreakLabel: this.formatMinutes(row.totalBreakMinutes),
            grossHoursLabel: this.formatHours(row.grossWorkHours),
            netHoursLabel: this.formatHours(row.netWorkHours)
        }));

        return normalized;
    }

    formatMinutes(value) {
        const parsed = Number(value || 0);
        if (Number.isNaN(parsed)) {
            return '0';
        }
        return String(Math.round(parsed));
    }

    formatHours(value) {
        const parsed = Number(value || 0);
        if (Number.isNaN(parsed)) {
            return '0m';
        }
        const totalMinutes = Math.round(parsed * 60);
        const hours = Math.floor(totalMinutes / 60);
        const minutes = totalMinutes % 60;
        if (hours <= 0) {
            return `${minutes}m`;
        }
        return `${hours}h ${minutes}m`;
    }

    startLiveTimer() {
        if (this.timerIntervalId) {
            return;
        }
        this.updateLiveTimer();
        this.timerIntervalId = setInterval(() => {
            this.updateLiveTimer();
        }, 1000);
    }

    stopLiveTimer() {
        if (!this.timerIntervalId) {
            return;
        }
        clearInterval(this.timerIntervalId);
        this.timerIntervalId = null;
    }

    updateLiveTimer() {
        this.liveTimerLabel = this.computeLiveTimerLabel();
    }

    computeLiveTimerLabel() {
        const today = this.today;
        if (!today) {
            return '00:00:00';
        }

        if (this.state === 'NOT_STARTED' || this.state === 'LEAVE' || this.state === 'INACTIVE') {
            return '00:00:00';
        }

        if (this.state === 'ENDED') {
            return this.formatSecondsAsClock(Math.round(Number(today.netWorkMinutes || 0) * 60));
        }

        if (!today.startTime) {
            return '00:00:00';
        }

        const startMs = new Date(today.startTime).getTime();
        if (Number.isNaN(startMs)) {
            return '00:00:00';
        }

        const nowMs = Date.now();
        let effectiveMs = Math.max(0, nowMs - startMs);
        (this.todayBreaks || []).forEach(item => {
            if (!item || !item.breakStart) {
                return;
            }
            const breakStartMs = new Date(item.breakStart).getTime();
            if (Number.isNaN(breakStartMs)) {
                return;
            }
            const breakEndMs = item.breakEnd ? new Date(item.breakEnd).getTime() : nowMs;
            if (Number.isNaN(breakEndMs)) {
                return;
            }
            effectiveMs -= Math.max(0, breakEndMs - breakStartMs);
        });
        if (effectiveMs < 0) {
            effectiveMs = 0;
        }
        return this.formatSecondsAsClock(Math.floor(effectiveMs / 1000));
    }

    formatSecondsAsClock(seconds) {
        const total = Math.max(0, Number(seconds || 0));
        const hrs = Math.floor(total / 3600);
        const mins = Math.floor((total % 3600) / 60);
        const secs = Math.floor(total % 60);
        return `${String(hrs).padStart(2, '0')}:${String(mins).padStart(2, '0')}:${String(secs).padStart(2, '0')}`;
    }

    handleStartDay() {
        this.runAction(startDay, 'Day started.');
    }

    handleStartBreak() {
        this.runAction(startBreak, 'Break started.');
    }

    handleEndBreak() {
        this.runAction(endBreak, 'Break ended.');
    }

    handleEndDay() {
        this.runAction(endDay, 'Day ended and summary captured.');
    }

    runAction(actionMethod, successMessage) {
        this.isLoading = true;
        actionMethod()
            .then(response => {
                this.dashboard = this.decorateResponse(response);
                this.updateLiveTimer();
                this.showToast('Success', successMessage, 'success');
            })
            .catch(error => {
                this.handleError(error);
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleError(error) {
        let message = 'Something went wrong.';
        if (error?.body?.message) {
            message = error.body.message;
        } else if (error?.message) {
            message = error.message;
        }
        this.showToast('Error', message, 'error');
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }
}