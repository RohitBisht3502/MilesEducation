public with sharing class ProcessInstanceLeadService {
    @AuraEnabled(cacheable=true)
    public static Lead__c getLeadForWorkitem(Id workitemId) {
        if (workitemId == null) {
            return null;
        }

        ProcessInstanceWorkitem wi = [
            SELECT Id, ProcessInstance.TargetObjectId
            FROM ProcessInstanceWorkitem
            WHERE Id = :workitemId
            LIMIT 1
        ];

        Id targetId = wi.ProcessInstance.TargetObjectId;
        if (targetId == null) {
            return null;
        }

        if (targetId.getSObjectType() != Lead__c.SObjectType) {
            return null;
        }

        Lead__c leadRec = [
            SELECT Id, Name, Stage__c, CAN_ID__c, City__c, Course__c, Course_Bucket__c,
                   Source__c, Source_Bucket__c, Candidate__c, Student__c, OwnerId,
                   Is_ReEnquiry__c, Is_Merged__c, Expected_payment_date__c, Payment_Received__c,
                   Status__c, CC_Spoc__c, GP_SPOC__c, Not_Commited__c
            FROM Lead__c
            WHERE Id = :targetId
            LIMIT 1
        ];

        return leadRec;
    }
}