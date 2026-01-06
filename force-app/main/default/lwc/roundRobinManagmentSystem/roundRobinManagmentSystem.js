import { LightningElement, track, wire } from 'lwc';
import getFilters from '@salesforce/apex/RoundRobinMatrixController.getFilters';
import getMatrix from '@salesforce/apex/RoundRobinMatrixController.getMatrix';
import saveAssignedWeights from '@salesforce/apex/RoundRobinMatrixController.saveAssignedWeights';
import getBucketConfiguration from '@salesforce/apex/RoundRobinMatrixController.getBucketConfiguration';
import saveSequences from '@salesforce/apex/RoundRobinMatrixController.saveSequences';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getBusinessVerticals from '@salesforce/apex/RoundRobinMatrixController.getBusinessVerticals';


export default class RoundRobinManagmentSystem extends LightningElement {
  @track cities = [];
  @track buckets = [];
  @track leadSources = [];
@track businessVerticals = [];
@track selectedBusinessVertical = null;
@track types = [];
@track selectedType = null;



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

  connectedCallback() {
    this.selectedType = 'Round Robin';

    this.initFilters();
    this.loadSourceMetadata();
    this.loadBusinessVerticalMetadata();
}

async loadSourceMetadata() {
    const res = await getBucketConfiguration({ type: 'Source' });
    this.buckets = res.buckets || [];
    this.bucketSourcesMap = res.bucketSourcesMap || {};
    this.leadSources = res.allSources || []; // ✅ FIX
}

async loadBusinessVerticalMetadata() {
    const res = await getBucketConfiguration({ type: 'BusinessVertical' });
    this.businessVerticals = res.businessVerticals || []; // ✅ FIX
}



onTypeChange(e) {
    this.selectedType = e.target.value;
    this.resetMatrixView();
    this.loadMatrix();
}

// isColumnValid(colIndex) {
//     const total = this.columnTotals[colIndex] || 0;
//     return total === this.totalSalesRepsInCity;
// }


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
    return this.displayRows.length || 0;
}


  get isSourceDisabled() {
    return !this.selectedCity; 
   // return !this.selectedBucket;
  }

  get sourceTriggerTitle() {
    return this.selectedCity ? 'Select Lead Sources' : 'Select City first';
   // return this.selectedBucket ? 'Select Lead Sources' : 'Select Bucket first';
  }

  get selectedSourcesDisplay() {
    if (!this.selectedCity) return 'Select City first';
    return this.selectedSources.length ? this.selectedSources.join(', ') : 'Select Sources';
    // if (!this.selectedBucket) return 'Select Bucket first';
    // return this.selectedSources.length ? this.selectedSources.join(', ') : 'Select Sources';
  }

 async initFilters() {
  try {
    const res = await getFilters({ objectApiName: 'Lead__c' });

    this.cities = res?.cities || [];
    this.leadSources = res?.leadSources || [];
    this.buckets = res?.buckets || [];
    this.types = res?.types || []; // ✅ ADD THIS

      if (!this.selectedType && this.types.includes('Round Robin')) {
        this.selectedType = 'Round Robin';
    }

    const verticals = await getBusinessVerticals();
    this.businessVerticals = verticals || [];

    if (!this.selectedCity && this.cities.length)
      this.selectedCity = this.cities[0];

    this.resetMatrixView();
     this.loadMatrix();
  } catch (e) {
    console.error(e);
    this.showToast('Error', 'Failed to load filters', 'error');
  }
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
  city: '$selectedCity',
  bucket: '$selectedBucket',
  leadSources: '$selectedSources',
  businessVertical: '$selectedBusinessVertical',
typeVal: '$selectedType',

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

        // ✅ SAFE businessVertical logic
        if (
            !this.selectedBusinessVertical &&
            Array.isArray(data.rows) &&
            data.rows.length > 0 &&
            Array.isArray(data.columnsLeadSources) &&
            data.columnsLeadSources.length > 0
        ) {
            const firstCell =
                data.rows[0]?.byLeadSource?.[data.columnsLeadSources[0]];

            if (firstCell?.poolId) {
                // no-op, backend already filtered
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

  // swap positions only
  [rows[i], rows[j]] = [rows[j], rows[i]];

  // DO NOT rebuild objects
  // DO NOT touch sequence
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

    // Sort rows by sequence of first column (if exists)
    rows.sort((a, b) => {
        const col = cols[0];
        const sa = a?.byLeadSource?.[col]?.sequence ?? 9999;
        const sb = b?.byLeadSource?.[col]?.sequence ?? 9999;
        return sa - sb;
    });

    this.displayRows = rows.map((r, ri) => {
        let total = 0;

        const cells = cols.map((col, ci) => {
            let value = '—';
            let poolId = null;
            let sequence = null;

            const node = r?.byLeadSource?.[col];

            // ✅ SAFE null handling
            if (node) {
                poolId = node.poolId || null;

                if (Number.isFinite(node.assignedWeight)) {
                    value = node.assignedWeight;
                    total += node.assignedWeight;
                }

                if (Number.isFinite(node.sequence)) {
                    sequence = node.sequence;
                }
            }

            // Track pool location
            if (poolId) {
                this.poolIndex[poolId] = { ri, ci, poolId };
            }

            return {
                key: `${r.salesRepId}-${col}`,
                value,
                poolId,
                sequence,
                src: col
            };
        });

        return {
            key: r.salesRepId,
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
        rows.forEach(r => {
            const n = Number(r.cells?.[ci]?.value);
            if (Number.isFinite(n)) sum += n;
        });
        return sum;
    });

    // Trigger live visual update
    this.displayRows = [...this.displayRows];
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
        rows.push({
  salesRepName: r.salesRepName,
  poolId: cell.poolId,
  bucketId: this.selectedBucket, // ⭐ CRITICAL
  sequence: Number.isFinite(n) ? n : ''
});

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
    debugger;
  };

  async saveSeqEdits() {


    const  validation = this.validateColumnTotals();
    if(!validation.valid){
       this.showToast(
        'Validation eror',
        `lead source "${validation.leadSource}" total is ${validation.total}. It must be ${validation.expected} (number of users in city).`,
            'error'
        );
        return;
    
       
    }
  if (!this.seqRows.length) {
    this.showToast('Info', 'No sequence changes to save.', 'info');
    return;
  }
// ensure visual order = array order
//this.seqRows = [...this.seqRows];

  // Recalculate sequence based on visual order
  const payload = this.seqRows.map((r, index) => ({
    poolId: r.poolId,
    sequence: index + 1,
    bucketId: r.bucketId
  }));
  debugger;

  try {
    await saveSequences({
         updatesJson: JSON.stringify({
        leadSource: this.columns[this.seqColIndex],
        city: this.selectedCity,
        bucket: this.selectedBucket,
        businessVertical: this.selectedBusinessVertical || null,
         typeVal: this.selectedType || 'Round Robin',
 
        updates: payload
    })
    });

    this.showToast('Success', 'Sequence order updated successfully.', 'success');
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
    const repId = el?.dataset?.repid;
    const src = el?.dataset?.src;

    let stageKey = poolId;
    if (!/^[a-zA-Z0-9]{15,18}$/.test(poolId || '')) {
        if (!repId || !src) return;
        stageKey = `${repId}|${src}`;
    }

    let raw = (el.textContent || '').trim();
    let num = null;

    if (raw !== '' && raw !== '—') {
        const parsed = Number(raw);
        if (Number.isFinite(parsed) && parsed >= 0) num = Math.floor(parsed);
    }

    el.textContent = num === null ? '—' : String(num);

    const stagedCopy = { ...this.staged };
    if (num === null) delete stagedCopy[stageKey];
    else stagedCopy[stageKey] = {
  value: num,
  leadSource: src
};


    this.staged = stagedCopy;

    // recalc totals & live validation
    this.recalcColumnTotals();
};


  async saveEdits() {
  const updates = [];

  Object.entries(this.staged).forEach(([key, data]) => {
    const value = data.value;
    const leadSource = data.leadSource;

    if (!Number.isFinite(value)) return;

    // Existing record
    if (/^[a-zA-Z0-9]{15,18}$/.test(key)) {
      updates.push({
        poolId: key,
        assignedWeight: value,
        city: this.selectedCity,
        leadSource: leadSource,
        bucket: this.selectedBucket || null,
        businessVertical: this.selectedBusinessVertical || null,
        visibleUserCount: this.displayRows.length,
         typeVal: this.selectedType // ✅ ADD
      });
      return;
    }

    // New record
    const parts = key.split('|');
    if (parts.length === 2) {
     updates.push({
    poolId: null,
    assignedWeight: value,
    salesRepId: parts[0],
    leadSource: leadSource,
    city: this.selectedCity,
    bucket: this.selectedBucket || null,
    course: 'CMA',
    businessVertical: this.selectedBusinessVertical || null,
    typeVal: this.selectedType || 'Round Robin'
});

    }
  });

  if (!updates.length) {
    this.showToast('Info', 'No valid changes to save', 'info');
    return;
  }

  try {
    await saveAssignedWeights({
      updatesJson: JSON.stringify(updates)
    });

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
    let sourcesToShow = this.leadSources || [];
    if (this.selectedBucket && this.bucketSourcesMap[this.selectedBucket]) {
      sourcesToShow = this.bucketSourcesMap[this.selectedBucket];
    }
    const sel = new Set(this.tempSelectedSources || []);
    this.displayLeadSourcesTemp = (sourcesToShow || []).map(s => ({
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


  onCellKeydown = e => {
    if (e.key === 'Enter') {
      e.preventDefault();
      e.target.blur();
    }
  };

  // onCityChange(e) {
  //   this.selectedCity = e.target.value;
  // }
  onCityChange(e) {
    this.selectedCity = e.target.value;
    this.resetMatrixView();
    this.selectedSources = [...(this.leadSources || [])];
    this.loadMatrix();
  }



  // onBucketChange(e) {
  //   this.selectedBucket = e.target.value;
  //   this.resetMatrixView();

  //   if (this.selectedBucket) {
  //     const sources = this.bucketSourcesMap[this.selectedBucket] || [];
  //     this.availableSourcesForSelectedBucket = [...sources];
  //     this.selectedSources = [...sources];
  //     this.rebuildTempDisplaySources();
  //     this.loadMatrix();
  //   } else {
  //     this.selectedSources = [];
  //     this.availableSourcesForSelectedBucket = [];
  //     this.rebuildTempDisplaySources();
  //   }
  // }

  onBucketChange(e) {
    this.selectedBucket = e.target.value;
    this.resetMatrixView();

    if (this.selectedBucket && this.bucketSourcesMap[this.selectedBucket]) {
      const sources = this.bucketSourcesMap[this.selectedBucket] || [];
      this.availableSourcesForSelectedBucket = [...sources];
      this.selectedSources = [...sources]; // bucket-wise sources
    } else {
      this.availableSourcesForSelectedBucket = [];
      this.selectedSources = [...(this.leadSources || [])]; // back to all
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
    this.selectedType = null;
    this.resetMatrixView();
  };
  get colspan() {
    return 1 + (this.columns?.length || 0);
  }
  openNewPresence() {
    this.template
        .querySelector('c-new-round-robin-adder')
        .open();
}


}