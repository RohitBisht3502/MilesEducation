trigger StudentTrigger on Account (before insert,  after insert ,after update) {
    if (Trigger.isAfter) {
        if (Trigger.isInsert) {
            DataChangeEventHelper.publishEvents(Trigger.new, null, 'Account');
        }

        if (Trigger.isUpdate) {
             // StudentTriggerHelperClass.handleStudentStatusChange(Trigger.newMap, Trigger.oldMap);
            DataChangeEventHelper.publishEvents(Trigger.new, Trigger.oldMap, 'Account');
        }
    }
}