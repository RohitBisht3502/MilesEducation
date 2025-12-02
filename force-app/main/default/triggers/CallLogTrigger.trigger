trigger CallLogTrigger on Call_Log__c (before insert,before update,before delete,after insert,after update,after delete,after undelete) {
    CallLogTriggerFrameworkHandler handler = new CallLogTriggerFrameworkHandler(
        (List<Call_Log__c>)Trigger.new,
        (List<Call_Log__c>)Trigger.old,
        (Map<Id, Call_Log__c>)Trigger.newMap,
        (Map<Id, Call_Log__c>)Trigger.oldMap
    );

    if (Trigger.isBefore) {
        if (Trigger.isInsert) handler.beforeInsert();
        if (Trigger.isUpdate) handler.beforeUpdate();
        if (Trigger.isDelete) handler.beforeDelete();
    }

    if (Trigger.isAfter) {
        if (Trigger.isInsert) handler.afterInsert();
        if (Trigger.isUpdate) handler.afterUpdate();
        if (Trigger.isDelete) handler.afterDelete();
        if (Trigger.isUndelete) handler.afterUndelete();
    }
}