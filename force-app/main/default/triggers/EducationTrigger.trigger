trigger EducationTrigger on Education__c (before insert, after insert, before update, after update) {

    EducationTriggerFrameworkHandler handler = new EducationTriggerFrameworkHandler(
        (List<Education__c>)Trigger.new,
        Trigger.isUpdate ? (List<Education__c>)Trigger.old : new List<Education__c>(),
        (Map<Id, Education__c>)Trigger.newMap,
        Trigger.isUpdate ? (Map<Id, Education__c>)Trigger.oldMap : new Map<Id, Education__c>()
    );

    if (Trigger.isBefore) {
        if (Trigger.isInsert) handler.beforeInsert();
        if (Trigger.isUpdate) handler.beforeUpdate();
    }

    if (Trigger.isAfter) {
        if (Trigger.isInsert) {
            handler.afterInsert();
        }

        if (Trigger.isUpdate) {
            handler.afterUpdate();
        }
    }
}