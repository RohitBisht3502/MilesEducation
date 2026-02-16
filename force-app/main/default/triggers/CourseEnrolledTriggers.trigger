trigger CourseEnrolledTriggers on Course_Enrolled__c (after insert, after update) {

    if (Trigger.isAfter && Trigger.isInsert) {
        CourseEnrolledTriggerHandlerService.checkAndCreateNewTaskForInsert(
            Trigger.new
        );
    }
    if (Trigger.isAfter && Trigger.isUpdate) {
        CourseEnrolledTriggerHandlerService.checkAndCreateNewTaskForStatusChange(
            Trigger.newMap,
            Trigger.oldMap
        );
    }
}