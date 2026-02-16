public class PurchaseOrderApprovalHandler {

    public static void handleAfterUpdate(
        List<Purchase_Order__c> newList,
        Map<Id, Purchase_Order__c> oldMap
    ) {
        if (newList == null || newList.isEmpty() || oldMap == null) return;

        Set<Id> toProcess = new Set<Id>();
        for (Purchase_Order__c po : newList) {
            Purchase_Order__c oldPo = oldMap.get(po.Id);
            if (oldPo == null) continue;

            if (po.Approval_Status__c == 'Approved' &&
                oldPo.Approval_Status__c != 'Approved' &&
                po.Purchase_Order_Id__c == null) {
                toProcess.add(po.Id);
            }
        }

        if (!toProcess.isEmpty()) {
            PurchaseOrderService.enqueuePurchaseOrderCallout(toProcess);
        }
    }
}