import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import getWebinarsByNameOnly from '@salesforce/apex/WebinarController.getWebinarsByNameOnly';
import createWebinarMember from '@salesforce/apex/WebinarController.createWebinarMember';

export default class WebinarRegisterPanel extends LightningElement {
  @api recordId; // Lead Id

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
      // Expecting [{ id: '...', name: '...' }, ...]
      this.webinars = await getWebinarsByNameOnly();
    } catch (e) {
      this.toast('Error loading webinars', this.reduceError(e), 'error');
    } finally {
      this.loading = false;
    }
  }

  // ====== UI Actions ======
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

  // ====== Registration ======
  async confirmRegister() {
    if (!this.selectedWebinar?.id) {
      this.toast('No webinar selected', 'Please select a webinar and try again.', 'warning');
      return;
    }
    this.saving = true;
    try {
      await createWebinarMember({ leadId: this.recordId, webinarId: this.selectedWebinar.id });
      this.toast('Registered', `Lead has been registered for "${this.selectedWebinar.name}".`, 'success');
      this.confirmOpen = false;
    } catch (e) {
      this.toast('Registration failed', this.reduceError(e), 'error');
    } finally {
      this.saving = false;
    }
  }

  // ====== Helpers ======
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