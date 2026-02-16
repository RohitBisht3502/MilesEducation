trigger StudentFileStatusTrigger on Student_File_Status__c (after insert, after update) {
    if (Trigger.isAfter && Trigger.isInsert) {
        StudentFileStatusTaskHandler.handleAfterInsert(Trigger.new);
    }
    if (Trigger.isAfter && Trigger.isUpdate) {
        StudentFileStatusTaskHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
    }
}