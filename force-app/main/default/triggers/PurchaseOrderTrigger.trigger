trigger PurchaseOrderTrigger on Purchase_Order__c (after insert, after update) {
    if (Trigger.isAfter && Trigger.isInsert) {
        PurchaseOrderActivityLogHandler.handleAfterInsert(Trigger.new);
    }

    if (Trigger.isAfter && Trigger.isUpdate) {
        PurchaseOrderActivityLogHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
        PurchaseOrderApprovalHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
    }
}