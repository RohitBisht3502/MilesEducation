import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import getWebinarsByNameOrId from '@salesforce/apex/WebinarController.getWebinarsByNameOrId';
import createWebinarMember from '@salesforce/apex/WebinarController.createWebinarMember';

export default class ZoomRegistrationPanel extends LightningElement {
  @api recordId;
  @track webinars = [];
  @track allWebinars = [];
  @track selectedWebinar = {};
  @track searchKey = '';

  loading = true;
  saving = false;
  confirmOpen = false;
  detailsOpen = false;

  get showListView() {
    return !this.confirmOpen && !this.detailsOpen;
  }

  get showConfirmView() {
    return this.confirmOpen;
  }

  get showDetailsView() {
    return this.detailsOpen;
  }

  connectedCallback() {
    this.fetchWebinars();
  }

  get hasWebinars() {
    return Array.isArray(this.webinars) && this.webinars.length > 0;
  }

  async fetchWebinars() {
    this.loading = true;
    this.webinars = [];
    this.allWebinars = [];

    try {
      const rows = await getWebinarsByNameOrId({ searchKey: '' });
      this.allWebinars = (rows || []).map((r) => ({ ...r, isRegistered: false }));
      this.applySearch();
    } catch (e) {
      this.toast('Error loading webinars', this.reduceError(e), 'error');
    } finally {
      this.loading = false;
    }
  }

  handleSearchChange = (event) => {
    const value = event?.detail?.value ?? event?.target?.value ?? '';
    this.searchKey = value;
    this.applySearch();
  };

  applySearch() {
    const searchValue = (this.searchKey || '').trim().toLowerCase();

    if (!searchValue) {
      this.webinars = [...this.allWebinars];
      return;
    }

    this.webinars = this.allWebinars.filter((webinar) => {
      const name = (webinar.name || '').toLowerCase();
      const webinarId = (webinar.webinarId || '').toLowerCase();
      return name.includes(searchValue) || webinarId.includes(searchValue);
    });
  }

  openConfirm = (event) => {
    const webinarId = event.currentTarget?.dataset?.id;
    this.selectWebinar(webinarId);
    this.detailsOpen = false;
    this.confirmOpen = true;
  };

  closeConfirm = () => {
    this.confirmOpen = false;
  };

  openDetails = (event) => {
    const webinarId = event.currentTarget?.dataset?.id;
    this.selectWebinar(webinarId);
    this.confirmOpen = false;
    this.detailsOpen = true;
  };

  closeDetails = () => {
    this.detailsOpen = false;
  };

  selectWebinar(webinarId) {
    const found = this.webinars.find((w) => w.id === webinarId);
    this.selectedWebinar = found ? { ...found } : {};
  }

  async confirmRegister() {
    if (!this.selectedWebinar?.id) {
      this.toast('No webinar selected', 'Please select a webinar and try again.', 'warning');
      return;
    }

    this.saving = true;
    try {
      await createWebinarMember({
        recordId: this.recordId,
        webinarId: this.selectedWebinar.id
      });

      this.toast('Registered', `Lead has been registered for "${this.selectedWebinar.name}".`, 'success');

      this.confirmOpen = false;
      this.detailsOpen = false;

      this.allWebinars = this.allWebinars.map((webinar) =>
        webinar.id === this.selectedWebinar.id ? { ...webinar, isRegistered: true } : webinar
      );
      this.applySearch();

      this.dispatchEvent(new CloseActionScreenEvent());
      setTimeout(() => window.location.reload(), 800);
    } catch (e) {
      this.toast('Registration failed', this.reduceError(e), 'error');
    } finally {
      this.saving = false;
    }
  }

  toast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }

  reduceError(error) {
    let message = 'Unknown error';
    if (Array.isArray(error?.body)) {
      message = error.body.map((e) => e.message).join(', ');
    } else if (error?.body?.message) {
      message = error.body.message;
    } else if (error?.message) {
      message = error.message;
    }
    return message;
  }
}