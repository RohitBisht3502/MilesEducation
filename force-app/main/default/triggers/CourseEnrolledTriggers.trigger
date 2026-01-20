trigger CourseEnrolledTriggers on Course_Enrolled__c (after insert , after update ) {

    if(Trigger.isAfter){
        CourseEnrolledTriggerHandle.handleAfter(
        Trigger.new,
        Trigger.oldMap
        );
    }
}