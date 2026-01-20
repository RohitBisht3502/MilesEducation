/**
 * Auto Generated and Deployed by the MoEngage Sync Tool Package (moengage)
**/
trigger moengage_LeadTrigger on Lead (before insert, before update, after insert, after update) {
    moengage.SyncHandler.triggerHandler();
}