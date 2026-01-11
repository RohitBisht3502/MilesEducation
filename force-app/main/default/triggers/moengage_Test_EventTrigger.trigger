/**
 * Auto Generated and Deployed by the MoEngage Sync Tool Package (moengage)
**/
trigger moengage_Test_EventTrigger on Test_Event__c (before insert, before update, after insert, after update) {
    moengage.SyncHandler.triggerHandler();
}