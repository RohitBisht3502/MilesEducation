trigger ApprovalProcessTrigger on Approval_Process__c (after update) {
    if (Trigger.isAfter && Trigger.isUpdate) {
        ApprovalProcessHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
    }
}