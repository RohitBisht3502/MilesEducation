trigger PurchaseOrderTrigger on Purchase_Order__c (after update) {
    if (Trigger.isAfter && Trigger.isUpdate) {
        PurchaseOrderApprovalHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
    }
}