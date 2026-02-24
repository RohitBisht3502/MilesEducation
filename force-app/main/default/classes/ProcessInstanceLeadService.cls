public with sharing class ProcessInstanceLeadService {
    @AuraEnabled(cacheable=true)
    public static LeadMergeWrapper getLeadForWorkitem(Id workitemId) {
        if (workitemId == null) return null;

        ProcessInstanceWorkitem wi = [
            SELECT Id, ProcessInstance.TargetObjectId
            FROM ProcessInstanceWorkitem
            WHERE Id = :workitemId
            LIMIT 1
        ];

        Id targetId = wi.ProcessInstance.TargetObjectId;
        if (targetId == null || targetId.getSObjectType() != Lead__c.SObjectType) return null;

        Lead__c mainLead = [
            SELECT Id, Name, Stage__c, CAN_ID__c, City__c, Course__c, Course_Bucket__c,
                   Source__c, Source_Bucket__c, Candidate__c, Student__c, OwnerId,
                   Is_ReEnquiry__c, Is_Merged__c, Expected_payment_date__c, Payment_Received__c,
                   Status__c, CC_Spoc__c, GP_SPOC__c, Not_Commited__c, Lead_Merge_Comments__c
            FROM Lead__c
            WHERE Id = :targetId
            LIMIT 1
        ];

        // Fetch the lead being merged (Child lead where Lead__c = mainLead.Id)
        List<Lead__c> mergedLeads = [
            SELECT Id, Name, Stage__c, CAN_ID__c, City__c, Course__c, Course_Bucket__c,
                   Source__c, Source_Bucket__c, Candidate__c, Student__c, OwnerId,
                   Is_ReEnquiry__c, Is_Merged__c, Expected_payment_date__c, Payment_Received__c,
                   Status__c, CC_Spoc__c, GP_SPOC__c, Not_Commited__c
            FROM Lead__c
            WHERE Lead__c = :targetId
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        LeadMergeWrapper wrapper = new LeadMergeWrapper();
        wrapper.mainLead = mainLead;
        if (!mergedLeads.isEmpty()) {
            wrapper.mergedLead = mergedLeads[0];
        }
        return wrapper;
    }

    public class LeadMergeWrapper {
        @AuraEnabled public Lead__c mainLead;
        @AuraEnabled public Lead__c mergedLead;
    }
}