trigger UserTrigger on User (after insert, after update) {
    if (Trigger.isAfter) {
        if (Trigger.isInsert) {
            UserTriggerHandler.createEmployeeAndAttendance(Trigger.new);
            DataChangeEventHelper.publishEvents(Trigger.new, null, 'User');
        }

        if (Trigger.isUpdate) {
            DataChangeEventHelper.publishEvents(Trigger.new, Trigger.oldMap, 'User');
        }
    }
}