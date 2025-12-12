trigger WebinarMemberTrigger on Webinar_Member__c (before insert, after insert, before update, after update, before delete, after delete, after undelete) {
    WebinarMemberTriggerFrameworkHandler handler = new WebinarMemberTriggerFrameworkHandler(
        (List<Webinar_Member__c>)Trigger.new,
        (Trigger.isUpdate || Trigger.isDelete || Trigger.isUndelete)
            ? (List<Webinar_Member__c>)Trigger.old
            : new List<Webinar_Member__c>(),
        (Trigger.isInsert || Trigger.isUpdate)
            ? (Map<Id, Webinar_Member__c>)Trigger.newMap
            : new Map<Id, Webinar_Member__c>(),
        (Trigger.isUpdate || Trigger.isDelete || Trigger.isUndelete)
            ? (Map<Id, Webinar_Member__c>)Trigger.oldMap
            : new Map<Id, Webinar_Member__c>()
    );

    if (Trigger.isBefore) {
        if (Trigger.isInsert) handler.beforeInsert();
        if (Trigger.isUpdate)  handler.beforeUpdate();
        if (Trigger.isDelete)  handler.beforeDelete();
    }

    if (Trigger.isAfter) {
        if (Trigger.isInsert)   handler.afterInsert();
        if (Trigger.isUpdate)   handler.afterUpdate();
        if (Trigger.isDelete)   handler.afterDelete();
        if (Trigger.isUndelete) handler.afterUndelete();
    }
}