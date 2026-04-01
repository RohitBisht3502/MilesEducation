trigger WorkExperienceTrigger on Work_Experience__c (before insert, after insert, before update, after update) {

    WorkExperienceTriggerFrameworkHandler handler = new WorkExperienceTriggerFrameworkHandler(
        (List<Work_Experience__c>)Trigger.new,
        Trigger.isUpdate ? (List<Work_Experience__c>)Trigger.old : new List<Work_Experience__c>(),
        (Map<Id, Work_Experience__c>)Trigger.newMap,
        Trigger.isUpdate ? (Map<Id, Work_Experience__c>)Trigger.oldMap : new Map<Id, Work_Experience__c>()
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