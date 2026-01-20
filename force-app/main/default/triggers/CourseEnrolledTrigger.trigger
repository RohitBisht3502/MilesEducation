trigger CourseEnrolledTrigger on Course_Enrolled__c (
    before insert, after insert,
    before update, after update,
    before delete, after delete,
    after undelete
) {
    CourseEnrolledTriggerFrameworkHandler handler = new CourseEnrolledTriggerFrameworkHandler(
        (List<Course_Enrolled__c>)Trigger.new,
        (Trigger.isUpdate || Trigger.isDelete || Trigger.isUndelete)
            ? (List<Course_Enrolled__c>)Trigger.old
            : new List<Course_Enrolled__c>(),
        (Trigger.isInsert || Trigger.isUpdate)
            ? (Map<Id, Course_Enrolled__c>)Trigger.newMap
            : new Map<Id, Course_Enrolled__c>(),
        (Trigger.isUpdate || Trigger.isDelete || Trigger.isUndelete)
            ? (Map<Id, Course_Enrolled__c>)Trigger.oldMap
            : new Map<Id, Course_Enrolled__c>()
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