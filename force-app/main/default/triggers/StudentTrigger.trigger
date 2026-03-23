trigger StudentTrigger on Account (before insert, after update) {
    if(Trigger.isAfter && Trigger.isUpdate){
        StudentTriggerHelperClass.handleStudentStatusChange(Trigger.newMap, Trigger.oldMap);
    }
}