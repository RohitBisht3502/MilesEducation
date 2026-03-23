trigger EligibilityFolderTrigger on Eligibility_Folder__c (before insert, after update) {
    if (Trigger.isAfter && Trigger.isUpdate) {
        EligibilityFolderTriggerHelperClass.handleEligibilityFolderStatusChange(Trigger.oldMap, Trigger.newMap);
        EligibilityFolderTriggerHelperClass.handleEligibilityFolderStatusChangeForStudent(Trigger.oldMap, Trigger.newMap);
    }
}