trigger TranscationTrigger on Transcation__c (after insert, after update) {
    
    if(Trigger.isAfter){
        if(Trigger.isInsert || Trigger.isUpdate){
            TranscationTriggerHandler.createActivityLogs(Trigger.new, Trigger.oldMap);
        }
    }
}