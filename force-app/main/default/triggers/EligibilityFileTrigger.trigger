trigger EligibilityFileTrigger on Eligibility_File__c (before insert, after update) {
    if (Trigger.isAfter && Trigger.isUpdate) {
        EligibilityFileTriggerHelperClass.handleEligibilityFileStatusChange(Trigger.oldMap, Trigger.newMap);
        EligibilityFileTriggerHelperClass.handleEligibilityFileStatusChangeForStudent(Trigger.oldMap, Trigger.newMap);
    }
}