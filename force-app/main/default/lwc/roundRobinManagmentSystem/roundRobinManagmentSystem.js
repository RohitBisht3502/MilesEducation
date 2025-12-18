import { LightningElement, track, wire } from 'lwc';
import getFilters from '@salesforce/apex/RoundRobinMatrixController.getFilters';
import getMatrix from '@salesforce/apex/RoundRobinMatrixController.getMatrix';
import saveAssignedWeights from '@salesforce/apex/RoundRobinMatrixController.saveAssignedWeights';
import saveSequences from '@salesforce/apex/RoundRobinMatrixController.saveSequences';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';

export default class RoundRobinManagmentSystem extends LightningElement {
  @track cities = [];
  @track buckets = [];

  @track selectedCity = '';
  @track selectedSources = [];
  @track columns = [];
  @track rows = [];
  @track displayRows = [];
  @track pageNumber = 1;
  pageSize = 10;
  totalRows = 0;
  staged = {};
  @track showModal = false;
  @track tempSelectedSources = [];
  @track displayLeadSourcesTemp = [];
  poolIndex = {};
  @track showSeqModal = false;
  @track seqColIndex = -1;
  @track seqColLabel = '';
  @track columnTotals = [];
  @track seqRows = [];
  _matrixWire;

  connectedCallback() {
    this.initFilters();
  }

  get saveDisabled() {
    return Object.keys(this.staged).length === 0;
  }

  async initFilters() {
    try {
      const res = await getFilters({ objectApiName: 'Lead' });
      this.cities = res?.cities || [];
      this.leadSources = res?.leadSources || [];
      if (!this.selectedCity && this.cities.length) this.selectedCity = this.cities[0];
      await this.loadMatrix();
    } catch {
      this.showToast('Error', 'Failed to load filters', 'error');
    }
  }

  @wire(getMatrix, {
    objectApiName: 'Lead',
    city: '$selectedCity',
    leadSources: '$selectedSources',
    pageNumber: '$pageNumber',
    pageSize: '$pageSize'
  })
  wiredMatrix(result) {
    this._matrixWire = result;
    const { data, error } = result || {};
    if (data) {
      this.columns = data.columnsLeadSources || [];
      this.rows = data.rows || [];
      this.totalRows = data.totalRows || 0;
      this.buildDisplayRows();
    } else if (error) {
      this.showToast('Error', 'Failed to load matrix data', 'error');
    }
  }

  async loadMatrix() {
    if (this._matrixWire) {
      await refreshApex(this._matrixWire);
    }
  }

  buildDisplayRows() {
    this.poolIndex = {};
    this.displayRows = (this.rows || []).map((r, ri) => {
      let total = 0;
      const cells = (this.columns || []).map((col, ci) => {
        let val = '—', poolId = null, seq = null;
        if (r.byLeadSource && r.byLeadSource[col]) {
          const node = r.byLeadSource[col];
          poolId = node.poolId || null;
          if (node.assignedWeight != null) {
            val = node.assignedWeight;
            total += node.assignedWeight;
          }
          if (node.sequence != null) seq = node.sequence;
        }
        if (poolId) this.poolIndex[poolId] = { ri, ci, poolId };
        return { key: `${r.salesRepId}-${col}`, value: val, poolId, sequence: seq };
      });
      return { key: r.salesRepId, salesRepName: r.salesRepName, cells, total };
    });
    this.recalcColumnTotals();
  }

  recalcColumnTotals() {
    const cols = this.columns || [];
    const rows = this.displayRows || [];
    this.columnTotals = cols.map((_, ci) => {
      let sum = 0;
      rows.forEach(r => {
        const n = Number(r.cells?.[ci]?.value);
        if (Number.isFinite(n)) sum += n;
      });
      return sum;
    });
  }

  openSeqModal = e => {
    const label = e.currentTarget?.dataset?.ci;
    const ci = this.columns.findIndex(c => c === label);
    if (ci < 0) return;
    const rows = [];
    (this.displayRows || []).forEach(r => {
      const cell = r.cells?.[ci];
      if (cell && cell.poolId) {
        const n = Number(cell.sequence);
        rows.push({ salesRepName: r.salesRepName, poolId: cell.poolId, sequence: Number.isFinite(n) ? n : '' });
      }
    });
    this.seqColIndex = ci;
    this.seqColLabel = label;
    this.seqRows = rows;
    this.showSeqModal = true;
  };

  closeSeqModal = () => {
    this.showSeqModal = false;
    this.seqRows = [];
    this.seqColIndex = -1;
    this.seqColLabel = '';
  };

  onSeqInputChange = e => {
    const poolId = e.target?.dataset?.poolid;
    const v = e.target.value;
    const seq = v === '' ? '' : Math.max(1, Math.floor(Number(v)));
    this.seqRows = this.seqRows.map(r => (r.poolId === poolId ? { ...r, sequence: seq } : r));
  };

  async saveSeqEdits() {
    const filled = this.seqRows.filter(r => r.sequence !== '' && Number.isFinite(Number(r.sequence)));
    for (const r of filled) {
      const n = Number(r.sequence);
      if (!Number.isInteger(n) || n < 1) {
        this.showToast('Error', 'Sequence must be a positive integer.', 'error');
        return;
      }
    }
    const seen = new Set();
    for (const r of filled) {
      const n = Number(r.sequence);
      if (seen.has(n)) {
        this.showToast('Error', 'Sequence values must be unique.', 'error');
        return;
      }
      seen.add(n);
    }
    if (!filled.length) {
      this.showToast('Info', 'No sequence changes to save.', 'info');
      this.closeSeqModal();
      return;
    }
    try {
      const payload = filled.map(r => ({ poolId: r.poolId, sequence: Number(r.sequence) }));
      await saveSequences({
        updatesJson: JSON.stringify({
          leadSource: this.columns[this.seqColIndex],
          city: this.selectedCity || null,
          updates: payload
        })
      });
      this.showToast('Success', 'Sequences updated.', 'success');
      this.closeSeqModal();
      await this.loadMatrix();
    } catch (e) {
      const message = e?.body?.message || e?.message || 'Unknown error';
      this.showToast('Error', `Failed to save sequences: ${message}`, 'error');
    }
  }

  onCellBlur = e => {
    const el = e.currentTarget;
    const poolId = el?.dataset?.poolid;
    if (!/^[a-zA-Z0-9]{15,18}$/.test(poolId || '')) return;
    const pos = this.poolIndex[poolId];
    if (!pos) return;
    let raw = (el.textContent || '').trim();
    let num = null;
    if (raw !== '' && raw !== '—') {
      const parsed = Number(raw);
      if (Number.isFinite(parsed) && parsed >= 0) num = Math.floor(parsed);
    }
    const maxPeople = (this.displayRows || []).reduce((n, r) => {
      return n + (r.cells?.[pos.ci]?.poolId ? 1 : 0);
    }, 0);
    if (num !== null && num > maxPeople) {
      num = maxPeople;
      this.showToast('Warning', `Value cannot exceed ${maxPeople}.`, 'warning');
    }
    let columnSum = 0;
    this.displayRows.forEach(r => {
      const v = r.cells?.[pos.ci]?.value;
      const n = Number(v);
      if (Number.isFinite(n)) columnSum += n;
    });
    const prevVal = this.displayRows[pos.ri].cells[pos.ci].value;
    const oldVal = Number(prevVal) || 0;
    const newTotal = columnSum - oldVal + (num || 0);
    if (newTotal > maxPeople) {
      this.showToast('Error', `Total for "${this.columns[pos.ci]}" cannot exceed ${maxPeople}.`, 'error');
      const revertVal = this.staged[poolId] ?? (oldVal || '—');
      this.displayRows[pos.ri].cells[pos.ci].value = revertVal;
      el.textContent = revertVal;
      return;
    }
    const displayValue = num === null ? '—' : String(num);
    el.textContent = displayValue;
    this.displayRows[pos.ri].cells[pos.ci].value = displayValue;
    if (num === null) delete this.staged[poolId];
    else this.staged = { ...this.staged, [poolId]: num };
    this.recalcColumnTotals();
  };

  async saveEdits() {
    const payload = Object.entries(this.staged)
      .filter(([id, v]) => /^[a-zA-Z0-9]{15,18}$/.test(id) && Number.isFinite(v))
      .map(([id, v]) => ({ poolId: id, assignedWeight: v }));
    if (!payload.length) {
      this.showToast('Info', 'No valid changes to save', 'info');
      return;
    }
    try {
      await saveAssignedWeights({ updatesJson: JSON.stringify(payload) });
      this.showToast('Success', 'Weights saved successfully', 'success');
      this.staged = {};
      await this.loadMatrix();
    } catch (e) {
      const message = e?.body?.message || e?.message || 'Unknown error';
      this.showToast('Error', `Failed to save weights: ${message}`, 'error');
    }
  }

  showToast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant, mode: 'dismissable' }));
  }

  openModal = () => {
    this.tempSelectedSources = [...this.selectedSources];
    this.rebuildTempDisplaySources();
    this.showModal = true;
  };

  closeModal = () => {
    this.showModal = false;
  };

  handleModalClick = e => e.stopPropagation();

  handleCheckboxChange = e => {
    const value = e.target.dataset.value;
    const isChecked = e.target.checked;
    if (isChecked && !this.tempSelectedSources.includes(value))
      this.tempSelectedSources = [...this.tempSelectedSources, value];
    else if (!isChecked)
      this.tempSelectedSources = this.tempSelectedSources.filter(v => v !== value);
    this.rebuildTempDisplaySources();
  };

  rebuildTempDisplaySources() {
    const sel = new Set(this.tempSelectedSources || []);
    this.displayLeadSourcesTemp = (this.leadSources || []).map(s => ({
      key: s,
      value: s,
      label: s,
      checked: sel.has(s)
    }));
  }

  applySelection = () => {
    this.selectedSources = [...this.tempSelectedSources];
    this.showModal = false;
    this.loadMatrix();
  };

  get selectedSourcesDisplay() {
  return this.selectedSources.length ? this.selectedSources.join(', ') : '— Select Bucket —';
}


  onCellKeydown = e => {
    if (e.key === 'Enter') {
      e.preventDefault();
      e.target.blur();
    }
  };

  onCityChange(e) {
    this.selectedCity = e.target.value;
  }

  reload = () => this.loadMatrix();
  clearFilters = () => {
    this.selectedCity = '';
    this.selectedSources = [];
    this.loadMatrix();
  };
  get colspan() {
    return 1 + (this.columns?.length || 0);
  }
}