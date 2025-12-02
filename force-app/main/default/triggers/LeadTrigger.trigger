trigger LeadTrigger on Lead__c (before insert, after insert, before update, after update) {

    LeadTriggerFrameworkHandler handler = new LeadTriggerFrameworkHandler(
        (List<Lead__c>)Trigger.new,
        (Trigger.isUpdate || Trigger.isDelete || Trigger.isUndelete) 
            ? (List<Lead__c>)Trigger.old 
            : new List<Lead__c>(),
        (Trigger.isInsert || Trigger.isUpdate) 
            ? (Map<Id, Lead__c>)Trigger.newMap 
            : new Map<Id, Lead__c>(),
        (Trigger.isUpdate || Trigger.isDelete || Trigger.isUndelete) 
            ? (Map<Id, Lead__c>)Trigger.oldMap 
            : new Map<Id, Lead__c>()
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