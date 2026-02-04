import { LightningElement, track, wire } from 'lwc';
import getFilters from '@salesforce/apex/RoundRobinMatrixController.getFilters';
import getMatrix from '@salesforce/apex/RoundRobinMatrixController.getMatrix';
import saveAssignedWeights from '@salesforce/apex/RoundRobinMatrixController.saveAssignedWeights';
import getBucketConfiguration from '@salesforce/apex/RoundRobinMatrixController.getBucketConfiguration';
import saveSequences from '@salesforce/apex/RoundRobinMatrixController.saveSequences';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getBusinessVerticals from '@salesforce/apex/RoundRobinMatrixController.getBusinessVerticals';
import getCityStatuses from '@salesforce/apex/RoundRobinToggleOnOff.getCityStatuses';
import updateCityStatuses from '@salesforce/apex/RoundRobinToggleOnOff.updateCityStatuses';

const DEFAULT_TYPE = 'Round Robin';
const DEFAULT_VERTICAL = 'Accounting Vertical';
const AUTO_BUCKETS = ['Bucket 1', 'Bucket 2'];

export default class RoundRobinManagmentSystem extends LightningElement {
  @track cities = [];
  @track buckets = [];
  @track leadSources = [];
  @track businessVerticals = [];
  @track selectedBusinessVertical = null;
  @track types = [];
  @track selectedType = null;
  @track selectedTypeUi = '';
  @track citySalesRepCount = {};

  @track showRoundRobinModal = false;
  @track cityRoundRobinState = {};

  @track cityStatusList = [];

  @track selectedCity = '';
  @track selectedBucket = '';
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
  @track bucketSourcesMap = {};
  @track availableSourcesForSelectedBucket = [];
  _matrixWire;
  _cityStatusWire;

  @track selectedRole = '';
  @track roles = [];

  get roleOptions() {
    return (this.roles || []).map((r) => ({
      label: r === 'CC'
        ? 'CC - Pre Enrollment'
        : r === 'SR'
          ? 'SR - Post Enrollment'
          : r,
      value: r,
      selected: r === this.selectedRole
    }));
  }

  handleRoleChange(event) {
    this.selectedRole = event.target.value;
    this.resetMatrixView();
    this.loadMatrix(); // reload table
  }



  connectedCallback() {
    this.initFilters();
    this.loadSourceMetadata();
    this.loadBusinessVerticalMetadata();
    // this.loadCityRoundRobinStatuses();
  }

  async loadSourceMetadata() {
    const res = await getBucketConfiguration({ type: 'Source' });
    this.buckets = res.buckets || [];
    this.bucketSourcesMap = res.bucketSourcesMap || {};
    this.leadSources = res.allSources || []; 
  }

  async loadBusinessVerticalMetadata() {
    const res = await getBucketConfiguration({ type: 'BusinessVertical' });
    this.businessVerticals = res.businessVerticals || []; // ✅ FIX
  }

  
@wire(getCityStatuses)
wiredCityStatuses(result) {
  this._cityStatusWire = result;

  const { data, error } = result;
  if (data) {
    const map = {};
    const countMap = {};

    data.forEach((r) => {
      map[r.city] = r.status === 'ON';
      countMap[r.city] = r.salesRepCount;
    });

    this.cityRoundRobinState = map;
    this.citySalesRepCount = countMap;
  } else if (error) {
    console.error('City status error', error);
  }
}
  get effectiveCity() {
    if (!this.selectedCity) return null;
    return this.selectedCity;
  }

  onTypeChange(e) {
    const uiValue = e.target.value;
    this.selectedTypeUi = uiValue;

    if (uiValue === 'RR_CC') {
      this.selectedType = 'Round Robin';
      this.selectedRole = 'CC';
    } else if (uiValue === 'RR_SR') {
      this.selectedType = 'Round Robin';
      this.selectedRole = 'SR';
    } else if (uiValue === 'ELIGIBILITY_GP') {
      this.selectedType = 'Eligibility criteria';
      this.selectedRole = '';
    } else if (uiValue === 'MCOM') {
      this.selectedType = 'MCOM';
      this.selectedRole = '';
    } else {
      this.selectedType = '';
      this.selectedRole = this.roles.includes('CC') ? 'CC' : (this.roles[0] || '');
    }

    this.resetMatrixView();
    this.loadMatrix();
  }

  get roundRobinCities() {
    return (this.cities || []).map((city) => ({
      name: city,
      enabled: this.cityRoundRobinState[city] !== false
    }));
  }

  getSalesRepCount(city) {
    return this.citySalesRepCount?.[city] || 0;
  }

  openRoundRobinModal = () => {
    this.showRoundRobinModal = true;
  };

  closeRoundRobinModal = () => {
    this.showRoundRobinModal = false;
  };

  toggleCityRoundRobin(event) {
    const city = event.target.dataset.city;
    const enabled = event.target.checked;

    this.cityRoundRobinState = {
      ...this.cityRoundRobinState,
      [city]: enabled
    };
  }

  get enabledCityCount() {
    return Object.values(this.cityRoundRobinState).filter((v) => v === true).length;
  }

  get totalCityCount() {
    return this.cities.length;
  }

  openBusinessVerticalModal() {
    if (this.isBusinessVerticalDisabled) return;
    this.showBusinessVerticalModal = true;
  }

  handleBusinessVerticalSelect(event) {
    this.selectedBusinessVertical = event.detail.value;
    this.selectedBusinessVerticalDisplay = event.detail.label;
    this.showBusinessVerticalModal = false;
  }

  get saveDisabled() {
    return Object.keys(this.staged).length === 0;
  }

  get totalSalesRepsInCity() {
    const rows = this.displayRows || [];
    const roleScopedCount = rows.filter((r) =>
      (r.cells || []).some((c) => !!c.poolId)
    ).length;
    return roleScopedCount > 0 ? roleScopedCount : rows.length;
  }

  get isSourceDisabled() {
    return !this.selectedCity;
  }

  get sourceTriggerTitle() {
    return this.selectedCity ? 'Select Lead Sources' : 'Select City first';
  }

 get selectedSourcesDisplay() {
  if (!this.selectedCity) return 'Select City first';

  if (!this.selectedSources || this.selectedSources.length === 0) {
    return 'Select Sources';
  }

  // If all sources selected
  if (
    this.availableSourcesForSelectedBucket.length &&
    this.selectedSources.length === this.availableSourcesForSelectedBucket.length
  ) {
    return 'All Sources Selected';
  }

 return `${this.selectedSources.length} source(s) selected`;
}

  get isCityWiseOnlyMode() {
    return this.selectedTypeUi === 'RR_SR'
      || this.selectedTypeUi === 'ELIGIBILITY_GP'
      || this.selectedTypeUi === 'MCOM';
  }

  get showSourceFilter() {
    return this.selectedTypeUi === 'RR_CC';
  }


  get typeOptions() {
    return [
      {
        label: 'CC - Pre Enrollment',
        value: 'RR_CC',
        selected: this.selectedTypeUi === 'RR_CC'
      },
      {
        label: 'SR - Post Enrollment',
        value: 'RR_SR',
        selected: this.selectedTypeUi === 'RR_SR'
      },
      {
        label: 'GP',
        value: 'ELIGIBILITY_GP',
        selected: this.selectedTypeUi === 'ELIGIBILITY_GP'
      },
      {
        label: 'MCOM',
        value: 'MCOM',
        selected: this.selectedTypeUi === 'MCOM'
      }
    ];
  }

  get businessVerticalOptions() {
    return (this.businessVerticals || []).map((v) => ({
      label: v,
      value: v,
      selected: v === this.selectedBusinessVertical
    }));
  }

  async initFilters() {
  try {
    const res = await getFilters({ objectApiName: 'Lead__c' });

    this.cities = res?.cities || [];
    this.leadSources = res?.leadSources || [];
    this.buckets = res?.buckets || [];
    this.roles = res?.roles || [];

    // ✅ AUTO-SELECT CC ROLE BY DEFAULT
    if (this.roles.includes('CC')) {
      this.selectedRole = 'CC';
    } else if (this.roles.length > 0) {
      this.selectedRole = this.roles[0]; // fallback
    }

    const rawTypes = res?.types || [];
    this.types = rawTypes.map(t => t?.value ?? t).filter(Boolean);

    const rawVerticals = await getBusinessVerticals();
    this.businessVerticals = (rawVerticals || [])
      .map(v => v?.value ?? v)
      .filter(Boolean);

    this.resetMatrixView();
    this.loadMatrix(); 
  } catch (e) {
    console.error(e);
    this.showToast('Error', 'Failed to load filters', 'error');
  }
}


  // ✅ ONLY THIS METHOD WAS ALIGNED/CLEANED (NO LOGIC CHANGE)
  async applyRoundRobinSettings() {
    debugger;
    this.showRoundRobinModal = false;

    // Build payload (only what Apex needs)
    const updates = Object.keys(this.cityRoundRobinState || {}).map((city) => ({
      city,
      status: this.cityRoundRobinState[city] ? 'ON' : 'OFF',
      salesRepCount: this.citySalesRepCount?.[city] || 0
    }));

    console.log('Updates to send:', JSON.stringify(updates, null, 2));

    if (!updates.length) {
      this.showToast('Info', 'No Round Robin settings to save', 'info');
      return;
    }

    try {
      
      await updateCityStatuses({ updatesJson: JSON.stringify(updates) });

      // metadata update is async; keep local toggle state and refresh matrix only
      await Promise.all([
        this._matrixWire && refreshApex(this._matrixWire)
      ]);

       this.showToast('Success', 'Round Robin updated successfully', 'success');
    } catch (e) {
      console.error('UpdateCityStatuses error:', e);
      this.showToast(
        'Error',
        `Failed to save Round Robin settings: ${e?.body?.message || e?.message || 'Unknown error'}`,
        'error'
      );
      return;
    }

    this.loadMatrix();
  }

  resetMatrixView() {
    this.columns = [];
    this.rows = [];
    this.displayRows = [];
    this.totalRows = 0;
    this.staged = {};
    this.columnTotals = [];
    this.poolIndex = {};
  }

  async loadBucketConfiguration() {
    try {
      const config = await getBucketConfiguration({ type: 'BusinessVertical' });

      this.bucketSourcesMap = config.bucketSourcesMap || {};
      this.businessVerticals = config.businessVerticals || [];
    } catch (error) {
      console.error('Error loading bucket configuration:', error);
    }
  }

  onBusinessVerticalChange(e) {
    this.selectedBusinessVertical = e.target.value;
    this.resetMatrixView();
    this.loadMatrix();
  }

  @wire(getMatrix, {
    objectApiName: 'Lead__c',
    city: '$effectiveCity',
    bucket: '$selectedBucket',
    leadSources: '$selectedSources',
    businessVertical: '$selectedBusinessVertical',
    typeVal: '$selectedType',
      role: '$selectedRole',  
    pageNumber: '$pageNumber',
    pageSize: '$pageSize'
  })
  wiredMatrix(result) {
    debugger;
    this._matrixWire = result;
    const { data, error } = result || {};

    if (data) {
      this.columns = data.columnsLeadSources || [];
      this.rows = data.rows || [];
      this.totalRows = data.totalRows || 0;
      this.buildDisplayRows();

      if (
        !this.selectedBusinessVertical &&
        Array.isArray(data.rows) &&
        data.rows.length > 0 &&
        Array.isArray(data.columnsLeadSources) &&
        data.columnsLeadSources.length > 0
      ) {
        const firstCell = data.rows[0]?.byLeadSource?.[data.columnsLeadSources[0]];
        if (firstCell?.poolId) {
          // no-op
        }
      }
    } else if (error) {
      console.error('Matrix wire error', error);
      this.showToast('Error', 'Failed to load matrix data', 'error');
    }
  }

  moveSeqUp(event) {
    const index = Number(event.currentTarget.dataset.index);
    if (index <= 0) return;
    this.swapSeqRows(index, index - 1);
  }

  moveSeqDown(event) {
    const index = Number(event.currentTarget.dataset.index);
    if (index >= this.seqRows.length - 1) return;
    this.swapSeqRows(index, index + 1);
  }

  swapSeqRows(i, j) {
    const rows = [...this.seqRows];
    [rows[i], rows[j]] = [rows[j], rows[i]];
    this.seqRows = rows;
  }

  async loadMatrix() {
    if (!this.selectedCity) {
      this.resetMatrixView();
      return;
    }

    if (this._matrixWire) {
      await refreshApex(this._matrixWire);
    }
  }

  buildDisplayRows() {
    this.poolIndex = {};

    const rows = Array.isArray(this.rows) ? [...this.rows] : [];
    const cols = Array.isArray(this.columns) ? [...this.columns] : [];

    rows.sort((a, b) => {
      const col = cols[0];
      const sa = a?.byLeadSource?.[col]?.sequence ?? 9999;
      const sb = b?.byLeadSource?.[col]?.sequence ?? 9999;
      return sa - sb;
    });

    this.displayRows = rows.map((r, ri) => {
      let total = 0;

      const cells = cols.map((col, ci) => {
        let value = 1;
        let poolId = null;
        let sequence = null;

        const node = r?.byLeadSource?.[col];

        if (node) {
          poolId = node.poolId || null;

          if (Number.isFinite(node.assignedWeight)) {
            value = node.assignedWeight;
          }

          if (Number.isFinite(node.sequence)) {
            sequence = node.sequence;
          }
        }

        if (poolId) {
          this.poolIndex[poolId] = { ri, ci, poolId };
        }

        total += value;

        return {
          key: `cell-${ri}-${ci}`,
          value,
          poolId,
          sequence,
          src: col
        };
      });

      return {
        key: `row-${ri}`,
        salesRepId: r.salesRepId,
        salesRepName: r.salesRepName,
        cells,
        total
      };
    });

    this.recalcColumnTotals();
  }

  validateColumnTotals() {
    const expected = this.totalSalesRepsInCity;

    for (let i = 0; i < this.columnTotals.length; i++) {
      if (this.columnTotals[i] !== expected) {
        return {
          valid: false,
          leadSource: this.columns[i],
          total: this.columnTotals[i],
          expected
        };
      }
    }
    return { valid: true };
  }

  recalcColumnTotals() {
    const cols = this.columns || [];
    const rows = this.displayRows || [];
    this.columnTotals = cols.map((_, ci) => {
      let sum = 0;
      rows.forEach((r) => {
        const n = Number(r.cells?.[ci]?.value);
        if (Number.isFinite(n)) sum += n;
      });
      return sum;
    });

    this.displayRows = [...this.displayRows];
  }

  openSeqModal = (e) => {
    const label = e.currentTarget?.dataset?.ci;
    const ci = this.columns.findIndex((c) => c === label);
    if (ci < 0) return;

    const rows = [];
    (this.displayRows || []).forEach((r) => {
      const cell = r.cells?.[ci];
      if (cell && cell.poolId) {
        const n = Number(cell.sequence);
        rows.push({
          salesRepName: r.salesRepName,
          poolId: cell.poolId,
          sequence: Number.isFinite(n) ? n : ''
        });
      }
    });

    rows.sort((a, b) => {
      let sa = typeof a.sequence === 'number' ? a.sequence : 999999;
      let sb = typeof b.sequence === 'number' ? b.sequence : 999999;
      if (sa === 0) sa = 999999;
      if (sb === 0) sb = 999999;
      return sa - sb;
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

  onSeqInputChange = (e) => {
    const poolId = e.target?.dataset?.poolid;
    const v = e.target.value;
    const seq = v === '' ? '' : Math.max(1, Math.floor(Number(v)));
    this.seqRows = this.seqRows.map((r) => (r.poolId === poolId ? { ...r, sequence: seq } : r));
    debugger;
  };

  async saveSeqEdits() {
    console.log('🔵 saveSeqEdits START');
    console.log('🔵 seqRows:', JSON.stringify(this.seqRows, null, 2));

    const validation = this.validateColumnTotals();
    if (!validation.valid) {
      this.showToast(
        'Validation Error',
        `Lead source "${validation.leadSource}" total is ${validation.total}. It must be ${validation.expected} (number of users in city).`,
        'error'
      );
      return;
    }

    if (!this.seqRows.length) {
      this.showToast('Info', 'No sequence changes to save.', 'info');
      return;
    }

    const payload = this.seqRows.map((r) => ({
      poolId: r.poolId,
      sequence: Number(r.sequence)
    }));

    const requestPayload = {
      leadSource: this.isCityWiseOnlyMode ? null : this.columns[this.seqColIndex],
      city: this.selectedCity,
      bucket: this.isCityWiseOnlyMode ? null : this.selectedBucket,
      businessVertical: this.isCityWiseOnlyMode ? null : (this.selectedBusinessVertical || null),
      typeVal: this.selectedType || 'Round Robin',
      role: this.selectedRole,
      updates: payload
    };

    console.log('📤 Full Request Payload:', JSON.stringify(requestPayload, null, 2));

    try {
      await saveSequences({
        updatesJson: JSON.stringify(requestPayload)
      });

      console.log('✅ saveSequences Apex call completed');

      this.showToast('Success', 'Sequence order updated successfully.', 'success');
      this.closeSeqModal();

      console.log('🔄 Refreshing matrix...');
      await this.loadMatrix();
      console.log('✅ Matrix refresh completed');
    } catch (e) {
      console.error('❌ saveSeqEdits ERROR:', e);
      console.error('❌ Error body:', e?.body);
      console.error('❌ Error message:', e?.message);
      console.error('❌ Full error:', JSON.stringify(e, null, 2));

      const message = e?.body?.message || e?.message || 'Unknown error';
      this.showToast('Error', `Failed to save sequences: ${message}`, 'error');
    }
  }

  onCellBlur = (e) => {
    const el = e.currentTarget;
    const poolId = el?.dataset?.poolid;
    const repId = el?.dataset?.repid;
    const src = el?.dataset?.src;

    let stageKey = poolId;
    if (!/^[a-zA-Z0-9]{15,18}$/.test(poolId || '')) {
      if (!repId || !src) return;
      stageKey = `${repId}|${src}`;
    }

    let raw = (el.textContent || '').trim();
    let num = 1;

    if (raw !== '' && raw !== '—') {
      const parsed = Number(raw);
      if (Number.isFinite(parsed) && parsed >= 0) num = Math.floor(parsed);
    }

    el.textContent = String(num);
    this.updateDisplayCellValue(poolId, repId, src, num);

    const stagedCopy = { ...this.staged };
    stagedCopy[stageKey] = { value: num, leadSource: src, salesRepId: repId };

    this.staged = stagedCopy;
    this.recalcColumnTotals();
  };

  updateDisplayCellValue(poolId, repId, src, num) {
    const nextValue = num === null ? 1 : num;
    this.displayRows = (this.displayRows || []).map((row) => {
      if (row.salesRepId !== repId) return row;

      const cells = (row.cells || []).map((cell) => {
        const matchesPool = poolId && cell.poolId === poolId;
        const matchesSrc = cell.src === src;
        if (matchesPool || matchesSrc) {
          return { ...cell, value: nextValue };
        }
        return cell;
      });

      const total = cells.reduce((sum, cell) => {
        const v = Number(cell.value);
        return sum + (Number.isFinite(v) ? v : 0);
      }, 0);

      return { ...row, cells, total };
    });
  }

  async saveEdits() {
    this.recalcColumnTotals();
    const validation = this.validateColumnTotals();
    if (!validation.valid) {
      this.showToast(
        'Validation Error',
        `Lead source "${validation.leadSource}" total must be exactly ${validation.expected}. Current total is ${validation.total}.`,
        'error'
      );
      return;
    }

    const updates = [];

    Object.entries(this.staged).forEach(([key, data]) => {
      const value = data.value;
      const leadSource = data.leadSource;

      if (!Number.isFinite(value)) return;

      if (/^[a-zA-Z0-9]{15,18}$/.test(key)) {
        updates.push({
          poolId: key,
          assignedWeight: value,
          salesRepId: data.salesRepId || null,
          city: this.selectedCity,
          leadSource: this.isCityWiseOnlyMode ? null : leadSource,
          bucket: this.isCityWiseOnlyMode ? null : (this.selectedBucket || null),
          businessVertical: this.isCityWiseOnlyMode ? null : (this.selectedBusinessVertical || null),
          visibleUserCount: this.displayRows.length,
          typeVal: this.selectedType,
          role: this.selectedRole
        });
        return;
      }

      const parts = key.split('|');
      if (parts.length === 2) {
        updates.push({
          poolId: null,
          assignedWeight: value,
          salesRepId: parts[0],
          leadSource: this.isCityWiseOnlyMode ? null : leadSource,
          city: this.selectedCity,
          bucket: this.isCityWiseOnlyMode ? null : (this.selectedBucket || null),
          course: 'CMA',
          businessVertical: this.isCityWiseOnlyMode ? null : (this.selectedBusinessVertical || null),
          visibleUserCount: this.displayRows.length,
          typeVal: this.selectedType || 'Round Robin',
          role: this.selectedRole
        });
      }
    });

    if (!updates.length) {
      this.showToast('Info', 'No valid changes to save', 'info');
      return;
    }

    try {
      await saveAssignedWeights({ updatesJson: JSON.stringify(updates) });
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
    if (!this.selectedCity) {
      this.showToast('Info', 'Please select a City first.', 'info');
      return;
    }
    this.tempSelectedSources = [...this.selectedSources];
    this.rebuildTempDisplaySources();
    this.showModal = true;
  };

  closeModal = () => {
    this.showModal = false;
  };

  handleModalClick = (e) => e.stopPropagation();

  handleCheckboxChange = (e) => {
    const value = e.target.dataset.value;
    const isChecked = e.target.checked;

    if (isChecked && !this.tempSelectedSources.includes(value)) {
      this.tempSelectedSources = [...this.tempSelectedSources, value];
    } else if (!isChecked) {
      this.tempSelectedSources = this.tempSelectedSources.filter((v) => v !== value);
    }

    this.rebuildTempDisplaySources();
  };

  rebuildTempDisplaySources() {
    let sourcesToShow = this.leadSources || [];
    if (this.selectedBucket && this.bucketSourcesMap[this.selectedBucket]) {
      sourcesToShow = this.bucketSourcesMap[this.selectedBucket];
    }

    const sel = new Set(this.tempSelectedSources || []);
    this.displayLeadSourcesTemp = (sourcesToShow || []).map((s) => ({
      key: s,
      value: s,
      label: s,
      checked: sel.has(s)
    }));
  }

  applySelection = () => {
    if (!this.selectedBucket) return;
    if (!this.selectedBucket) return;

    this.selectedSources = [...this.tempSelectedSources];
    this.showModal = false;
    this.resetMatrixView();
    this.loadMatrix();
  };

  onCellKeydown = (e) => {
    if (e.key === 'Enter') {
      e.preventDefault();
      e.target.blur();
    }
  };

  onCityChange(e) {
    this.selectedCity = e.target.value;
    this.resetMatrixView();

    this.selectedSources = [...(this.leadSources || [])];

    if (this.selectedCity) {
      this.selectedType = DEFAULT_TYPE;
      this.selectedRole = this.roles.includes('CC') ? 'CC' : (this.roles[0] || '');
      this.selectedTypeUi = this.selectedRole === 'SR' ? 'RR_SR' : 'RR_CC';
      this.selectedBusinessVertical = DEFAULT_VERTICAL;

      const defaultBucket = 'Bucket 1';
      if (this.buckets.includes(defaultBucket)) {
        this.selectedBucket = defaultBucket;
        setTimeout(() => {
          const bucketEl = this.template.querySelector('.bucket-select');
          if (bucketEl) bucketEl.value = defaultBucket;
        }, 0);
      } else {
        this.selectedBucket = '';
      }

      if (this.selectedBucket && this.bucketSourcesMap[this.selectedBucket]) {
        const sources = this.bucketSourcesMap[this.selectedBucket] || [];
        this.availableSourcesForSelectedBucket = [...sources];
        this.selectedSources = [...sources];
      }
    }

    this.rebuildTempDisplaySources();
    this.loadMatrix();
  }

  onBucketChange(e) {
    this.selectedBucket = e.target.value;
    this.resetMatrixView();
    debugger;

    if (AUTO_BUCKETS.includes(this.selectedBucket)) {
      this.selectedType = DEFAULT_TYPE;
      this.selectedRole = this.roles.includes('CC') ? 'CC' : (this.roles[0] || '');
      this.selectedTypeUi = this.selectedRole === 'SR' ? 'RR_SR' : 'RR_CC';
      this.selectedBusinessVertical = DEFAULT_VERTICAL;
    }

    if (this.selectedBucket && this.bucketSourcesMap[this.selectedBucket]) {
      const sources = this.bucketSourcesMap[this.selectedBucket] || [];
      this.availableSourcesForSelectedBucket = [...sources];
      this.selectedSources = [...sources];
    } else {
      this.availableSourcesForSelectedBucket = [];
      this.selectedSources = [...(this.leadSources || [])];
    }

    this.rebuildTempDisplaySources();
    this.loadMatrix();
  }

  reload = () => this.loadMatrix();

  clearFilters = () => {
    this.selectedCity = '';
    this.selectedBucket = '';
    this.selectedSources = [];
    this.availableSourcesForSelectedBucket = [];
    this.selectedType = '';
    this.selectedTypeUi = '';
    this.selectedBusinessVertical = '';
  this.selectedRole = this.roles.includes('CC')
  ? 'CC'
  : (this.roles[0] || '');

    const cityEl = this.template.querySelector('.city-select');
    if (cityEl) cityEl.value = '';

    const bucketEl = this.template.querySelector('.bucket-select');
    if (bucketEl) bucketEl.value = '';

    this.resetMatrixView();
  };

  get colspan() {
    return 1 + (this.columns?.length || 0);
  }

  openNewPresence() {
    this.template.querySelector('c-new-round-robin-adder').open();
  }

//   renderedCallback() {
//   const el = this.template.querySelector('select');
//   if (el && this.selectedRole && el.value !== this.selectedRole) {
//     el.value = this.selectedRole;
//   }
// }

}
