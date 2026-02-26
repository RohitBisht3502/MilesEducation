/*
    Author             : MANJEET KUNDU
    Description        : 
    Last Modified      : MANJEET KUNDU
    Last Modified Date : 
*/

public without sharing class EligibilityQuickActionController {

    @AuraEnabled(cacheable=true)
    public static String getEligibilityStatus(Id recordId) {
        if (recordId == null) {
            return null;
        }

        EligibilityRecordResolver.Context ctx = EligibilityRecordResolver.resolveByRecordId(recordId);
        if (ctx.studentId != null) {
            Account a = [
                SELECT GP_Lead_Status__c
                FROM Account
                WHERE Id = :ctx.studentId
                LIMIT 1
            ];
            return a.GP_Lead_Status__c;
        }
        if (ctx.candidateId != null) {
            Lead l = [
                SELECT GP_Lead_Status__c
                FROM Lead
                WHERE Id = :ctx.candidateId
                LIMIT 1
            ];
            return l.GP_Lead_Status__c;
        }
        return null;
    }

    @AuraEnabled
    public static void initializeEligibility(Id recordId) {
        if (recordId == null) {
            throw new AuraHandledException('Record Id is required.');
        }
        String eligibility = 'Eligibility Criteria';

        Schema.SObjectType sobjectType = recordId.getSObjectType();
        if (sobjectType == Lead.SObjectType) {
            List<Lead> leads = [
                SELECT Id, OwnerId, Phone, City__c, Course__c, Source_Bucket__c, GP_User__c, GP_Lead_Status__c, LeadSource
                FROM Lead
                WHERE Id = :recordId
                LIMIT 1
            ];

            if (leads.isEmpty()) return;

            for (Lead l : leads) {
                l.GP_Lead_Status__c = 'Initiated';
            }

            RoundRobinAssigner.assignWithStickyAndRoundRobin((List<SObject>) leads, 'Lead', eligibility);
            update leads;

            EligibilityFolderService.createFoldersForLead(recordId);
            return;
        }

        if (sobjectType == Account.SObjectType) {
            EligibilityRecordResolver.Context ctx = EligibilityRecordResolver.resolveByRecordId(recordId);
            if (ctx.studentId == null) return;

            Account a = [
                SELECT Id, GP_Lead_Status__c
                FROM Account
                WHERE Id = :ctx.studentId
                LIMIT 1
            ];
            a.GP_Lead_Status__c = 'Initiated';
            update a;

            EligibilityFolderService.createFoldersForRecord(ctx.candidateId, ctx.studentId);
        }
    }
}