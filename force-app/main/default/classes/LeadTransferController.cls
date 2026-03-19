public with sharing class LeadTransferController {

    @AuraEnabled
    public static void sendApproval(Id leadId, String comments) {

        Id currentUserId = UserInfo.getUserId();
        Lead ld = [SELECT Id, OwnerId FROM Lead WHERE Id = :leadId LIMIT 1];
        
         if (ld.OwnerId == currentUserId) {
            throw new AuraHandledException('You cannot send request for your own lead.');
        }

        // Fetch Managers for both Lead Owner and current Requestor
        Set<Id> userIds = new Set<Id>{ld.OwnerId, currentUserId};
        Map<Id, User> userMap = new Map<Id, User>([SELECT Id, ManagerId FROM User WHERE Id IN :userIds]);

        User leadOwner = userMap.get(ld.OwnerId);
        User requestor = userMap.get(currentUserId);

        Id approverId = '005C1000005Qn8fIAC'; // Fallback Admin ID

        if (leadOwner != null && requestor != null && 
            leadOwner.ManagerId != null && leadOwner.ManagerId == requestor.ManagerId) {
            approverId = leadOwner.ManagerId;
        }

        Id recordTypeId = Schema.SObjectType.Approval_Process__c.getRecordTypeInfosByDeveloperName().get('Lead_Transfer_Request').getRecordTypeId();

        Approval_Process__c req = new Approval_Process__c();

        req.Master_Lead__c = leadId;
        req.Requestor__c = currentUserId;
        req.Approver__c = approverId;
        req.OwnerId = approverId;
        req.Comments__c = comments;
        req.Merge_Status__c = 'Pending';
        req.Record_Type__c = 'Lead Transfer';
        req.RecordTypeId = recordTypeId;

        insert req;

        // CREATE INITIAL LOG
        insert new Activity_log__c(
            Name = 'Lead Transfer Request',
            Candidate__c = leadId,
            Activity_Type__c = 'Owner Change',
            Description__c = 'Lead Transfer Request initiated. Status: Pending approval.',
            Previous_Owner__c = ld.OwnerId,
            New_Owner__c = currentUserId,
            Logging_Id__c = req.Id,
            Action_Performed_By__c = currentUserId
        );
    }
}