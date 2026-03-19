trigger UserTrigger on User (after insert) {
    UserTriggerHandler.createEmployeeAndAttendance(Trigger.new);
}