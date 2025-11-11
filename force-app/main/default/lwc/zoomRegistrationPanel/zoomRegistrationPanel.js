import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import getWebinarsByNameOnly from '@salesforce/apex/WebinarController.getWebinarsByNameOnly';
import createWebinarMember from '@salesforce/apex/WebinarController.createWebinarMember';

export default class WebinarRegisterPanel extends LightningElement {
  @api recordId;
  @track webinars = [];
  @track selectedWebinar = {};
  loading = true;
  saving = false;

  confirmOpen = false;
  detailsOpen = false;

  connectedCallback() {
    this.fetchWebinars();
  }

  async fetchWebinars() {
    this.loading = true;
    try {
      const rows = await getWebinarsByNameOnly();
      this.webinars = (rows || []).map(r => ({ ...r, isRegistered: false }));
    } catch (e) {
      this.toast('Error loading webinars', this.reduceError(e), 'error');
    } finally {
      this.loading = false;
    }
  }

  handleCardClick = (event) => {
    const webinarId = event.currentTarget?.dataset?.id;
    this.selectWebinar(webinarId);
    this.confirmOpen = true;
  };

  openConfirm = (event) => {
    const webinarId = event.currentTarget?.dataset?.id;
    this.selectWebinar(webinarId);
    this.confirmOpen = true;
  };

  closeConfirm = () => {
    this.confirmOpen = false;
  };

  openDetails = (event) => {
    const webinarId = event.currentTarget?.dataset?.id;
    this.selectWebinar(webinarId);
    this.detailsOpen = true;
  };

  closeDetails = () => {
    this.detailsOpen = false;
  };

  selectWebinar(webinarId) {
    const found = this.webinars.find(w => w.id === webinarId);
    this.selectedWebinar = found ? { ...found } : {};
  }

  async confirmRegister() {
    debugger;
    if (!this.selectedWebinar?.id) {
      this.toast('No webinar selected', 'Please select a webinar and try again.', 'warning');
      return;
    }

    this.saving = true;
    try {
      await createWebinarMember({
        leadId: this.recordId,
        webinarId: this.selectedWebinar.id
      });

      this.toast(
        'Registered',
        `Lead has been registered for "${this.selectedWebinar.name}".`,
        'success'
      );

      this.confirmOpen = false;
      this.detailsOpen = false;
      const idx = this.webinars.findIndex(w => w.id === this.selectedWebinar.id);
      if (idx > -1) {
        const updated = [...this.webinars];
        updated[idx] = { ...updated[idx], isRegistered: true };
        this.webinars = updated;
      }

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
      message = error.body.map(e => e.message).join(', ');
    } else if (error?.body?.message) {
      message = error.body.message;
    } else if (error?.message) {
      message = error.message;
    }
    return message;
  }
}