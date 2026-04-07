import { api, LightningElement } from 'lwc';
import getUntrackedMissedCallLogs from '@salesforce/apex/RunoMissedCallLogService.getUntrackedMissedCallLogs';

export default class RunoMissedCallPanel extends LightningElement {
    missedCallRows = [];
    _refreshToken;

    connectedCallback() {
        this.loadMissedCalls();
    }

    @api
    get refreshToken() {
        return this._refreshToken;
    }

    set refreshToken(value) {
        this._refreshToken = value;
        if (value !== undefined) {
            this.loadMissedCalls();
        }
    }

    get missedCalls() {
        return this.missedCallRows;
    }

    get groupedMissedCalls() {
        const groups = [];
        const groupMap = new Map();

        this.missedCallRows.forEach(row => {
            const key = `${row.recordId || 'NA'}::${row.candidateName || 'Unknown Candidate'}::${row.relatedCourses || 'No related courses'}`;

            if (!groupMap.has(key)) {
                const group = {
                    key,
                    candidateName: row.candidateName,
                    relatedCourses: row.relatedCourses,
                    recordId: row.recordId,
                    rows: []
                };
                groupMap.set(key, group);
                groups.push(group);
            }

            groupMap.get(key).rows.push(row);
        });

        groups.forEach(group => {
            group.rows.sort((firstRow, secondRow) => {
                const firstDate = new Date(firstRow.sortDate || 0).getTime();
                const secondDate = new Date(secondRow.sortDate || 0).getTime();
                return secondDate - firstDate;
            });
            group.latestRow = group.rows[0];
            group.count = group.rows.length;
        });

        return groups;
    }

    get hasMissedCalls() {
        return this.missedCalls.length > 0;
    }

    get missedCallCountLabel() {
        return String(this.missedCalls.length);
    }

    findRowById(rowId) {
        return (this.missedCallRows || []).find(row => String(row.id) === String(rowId)) || null;
    }

    async loadMissedCalls() {
        try {
            const rows = await getUntrackedMissedCallLogs();
            const seenKeys = new Set();

            const dateFmt = new Intl.DateTimeFormat('en-US', {
                month: 'short',
                day: '2-digit',
                year: 'numeric'
            });

            const timeFmt = new Intl.DateTimeFormat('en-US', {
                hour: '2-digit',
                minute: '2-digit'
            });

            this.missedCallRows = (rows || []).reduce((acc, row) => {
                const dedupeKey = row.callId || row.id;
                if (seenKeys.has(dedupeKey)) {
                    return acc;
                }
                seenKeys.add(dedupeKey);

                const dt = row.startTime || row.createdDate;
                const parsedDate = dt ? new Date(dt) : null;

                acc.push({
                    id: row.id,
                    recordId: row.recordId || null,
                    callId: row.callId || null,
                    candidateName: row.candidateName || 'Unknown Candidate',
                    canId: row.canId || '',
                    relatedCourses: row.relatedCourses || 'No related courses',
                    status: row.status || 'NA',
                    l1: row.l1 || '',
                    l2: row.l2 || '',
                    stage: row.stage || '',
                    hasRecordLink: !!row.recordId,
                    recordUrl: row.recordId ? `/${row.recordId}` : null,
                    sortDate: dt,
                    dateLabel: parsedDate ? dateFmt.format(parsedDate) : 'NA',
                    timeLabel: parsedDate ? timeFmt.format(parsedDate) : ''
                });

                return acc;
            }, []);
        } catch (error) {
            console.error('Failed to load missed calls:', error);
            this.missedCallRows = [];
        }
    }

    handleFillFeedback(event) {
        const row = this.findRowById(event.target?.value);
        if (!row) {
            return;
        }

        this.dispatchEvent(new CustomEvent('fillfeedback', {
            detail: {
                recordId: row.recordId || null,
                callLogId: row.id,
                callId: row.callId || null
            }
        }));
    }

    handleCallCandidate(event) {
        const row = this.findRowById(event.target?.value);
        if (!row) {
            return;
        }

        this.dispatchEvent(new CustomEvent('callcandidate', {
            detail: {
                recordId: row.recordId || null,
                callLogId: row.id,
                callId: row.callId || null
            }
        }));
    }
}