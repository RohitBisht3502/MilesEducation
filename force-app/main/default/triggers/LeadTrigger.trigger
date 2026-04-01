trigger LeadTrigger on Lead__c (before insert, after insert, before update, after update) {

    LeadTriggerFrameworkHandler handler = new LeadTriggerFrameworkHandler(
        (List<Lead__c>)Trigger.new,
        Trigger.isUpdate ? (List<Lead__c>)Trigger.old : new List<Lead__c>(),
        (Map<Id, Lead__c>)Trigger.newMap,
        Trigger.isUpdate ? (Map<Id, Lead__c>)Trigger.oldMap : new Map<Id, Lead__c>()
    );

    if (Trigger.isBefore) {
        if (Trigger.isInsert) handler.beforeInsert();
        if (Trigger.isUpdate) handler.beforeUpdate();
    }

    if (Trigger.isAfter) {
        if (Trigger.isInsert) {
            handler.afterInsert();
            DataChangeEventHelper.publishEvents(Trigger.new, null, 'Lead__c');
        }

        if (Trigger.isUpdate) {
            handler.afterUpdate();
            DataChangeEventHelper.publishEvents(Trigger.new, Trigger.oldMap, 'Lead__c');
        }
    }
}