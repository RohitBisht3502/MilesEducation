import { LightningElement, wire,track } from 'lwc';
import getUserLeads from '@salesforce/apex/LeadQueueManagementController.getUserLeads';
export default class LeadQueueManagement extends LightningElement {
  @track leads = [];
  @track error;

  @wire(getUserLeads)
  wireLeads({data,error}){
    if(data){
        this.leads = data.map((item,index)=>({
            ...item,rowNumber:index+1
        }));
        this.error= undefined;
    }else if (error){
        this.error = error;
        this.leads = [];
    }
  }

  get hasLeads(){
    return this.leads & this.leads.length>0;
  }

  handleStart(){

  }
  handleEnd(){

  }
}