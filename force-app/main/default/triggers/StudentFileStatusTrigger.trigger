trigger StudentFileStatusTrigger on Student_File_Status__c (after update) {
    if (Trigger.isAfter && Trigger.isUpdate) {
        StudentFileStatusTaskHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
    }
}