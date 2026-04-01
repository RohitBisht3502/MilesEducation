trigger ApprovalProcessTrigger on Approval_Process__c (after update , after insert) {
   if (Trigger.isAfter) {
        if (Trigger.isInsert) {
            DataChangeEventHelper.publishEvents(Trigger.new, null, 'Approval_Process__c');
        }

        if (Trigger.isUpdate) {

             ApprovalProcessHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
            DataChangeEventHelper.publishEvents(Trigger.new, Trigger.oldMap, 'Approval_Process__c');
        }
    }
}