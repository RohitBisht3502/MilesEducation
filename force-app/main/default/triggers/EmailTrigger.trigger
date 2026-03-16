trigger EmailTrigger on Email__c (after insert, after update) {

    EmailTriggerFrameworkHandler handler = new EmailTriggerFrameworkHandler(
        (List<Email__c>)Trigger.new,
        Trigger.isUpdate
            ? (List<Email__c>)Trigger.old
            : new List<Email__c>(),
        (Map<Id, Email__c>)Trigger.newMap,
        Trigger.isUpdate
            ? (Map<Id, Email__c>)Trigger.oldMap
            : new Map<Id, Email__c>()
    );

    if (Trigger.isAfter) {
        if (Trigger.isInsert) handler.afterInsert();
        if (Trigger.isUpdate) handler.afterUpdate();
    }
}
