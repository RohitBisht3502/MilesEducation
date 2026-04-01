trigger CallLogTrigger on Call_Log__c (after update) {

    List<Call_Log__c> recordsToPublish = new List<Call_Log__c>();

    for (Call_Log__c newRec : Trigger.new) {
        Call_Log__c oldRec = Trigger.oldMap.get(newRec.Id);

       
        // Caller_Id__c was NULL before and now has value
        if (newRec.Caller_Id__c != null &&
            (oldRec.Caller_Id__c == null || oldRec.Caller_Id__c != newRec.Caller_Id__c)) {

            recordsToPublish.add(newRec);
        }
    }

    // ire platform event 
    if (!recordsToPublish.isEmpty()) {
        DataChangeEventHelper.publishEvents(
            recordsToPublish,
            Trigger.oldMap,
            'Call_Log__c'
        );
    }
}