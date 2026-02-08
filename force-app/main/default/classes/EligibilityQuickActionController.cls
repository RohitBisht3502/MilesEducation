/*
    Author             : MANJEET KUNDU
    Description        : 
    Last Modified      : MANJEET KUNDU
    Last Modified Date : 
*/

public without sharing class EligibilityQuickActionController {

    @AuraEnabled
    public static void initializeEligibility(Id recordId) {
        if (recordId == null) {
            throw new AuraHandledException('Record Id is required.');
        }
        String eligibility = 'GP';
        List<Lead> leads = [SELECT Id, OwnerId, Phone, City__c, Course__c,Course_Bucket__c, Source_Bucket__c, GP_User__c, GP_Lead_Status__c, LeadSource FROM Lead WHERE Id = :recordId LIMIT 1];

        if (leads.isEmpty()) return;

        for (Lead l : leads) {
            l.GP_Lead_Status__c = 'Initiated';
        }

        RoundRobinAssigner.assignWithStickyAndRoundRobin((List<SObject>) leads,'Lead', eligibility);
        update leads;

        EligibilityFolderService.createFoldersForLead(recordId);
    }
}