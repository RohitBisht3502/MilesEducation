trigger AttendanceTrigger on Attendance__c (after insert, before update) {
    if(Trigger.isAfter && Trigger.isInsert){
        AttendanceTriggerHelperClass.shareWithManagers(Trigger.new);
    }
    if(Trigger.isBefore && Trigger.isUpdate){
        AttendanceTriggerHelperClass.handleBeforeUpdate(Trigger.oldMap, Trigger.newMap);
    }
}