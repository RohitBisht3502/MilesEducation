trigger WebinarTrigger on Webinar__c (before insert, after insert, before update, after update, before delete, after delete, after undelete) {

    WebinarTriggerFrameworkHandler handler = new WebinarTriggerFrameworkHandler(
        (List<Webinar__c>)Trigger.new,
        (Trigger.isUpdate || Trigger.isDelete || Trigger.isUndelete)
            ? (List<Webinar__c>)Trigger.old
            : new List<Webinar__c>(),
        (Trigger.isInsert || Trigger.isUpdate)
            ? (Map<Id, Webinar__c>)Trigger.newMap
            : new Map<Id, Webinar__c>(),
        (Trigger.isUpdate || Trigger.isDelete || Trigger.isUndelete)
            ? (Map<Id, Webinar__c>)Trigger.oldMap
            : new Map<Id, Webinar__c>()
    );

    if (Trigger.isBefore) {
        if (Trigger.isInsert) handler.beforeInsert();
        if (Trigger.isUpdate) handler.beforeUpdate();
        if (Trigger.isDelete) handler.beforeDelete();
    }

    if (Trigger.isAfter) {
        if (Trigger.isInsert)   handler.afterInsert();
        if (Trigger.isUpdate)   handler.afterUpdate();
        if (Trigger.isDelete)   handler.afterDelete();
        if (Trigger.isUndelete) handler.afterUndelete();
    }
}