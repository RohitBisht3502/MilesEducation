public class ApprovalProcessHandler {

    public static void handleAfterUpdate(
        List<Approval_Process__c> newList,
        Map<Id, Approval_Process__c> oldMap
    ) {
        // Delegate all post-approval logic to the service class
        ApprovalProcessService.processFinalizedRequests(newList, oldMap);
    }
}