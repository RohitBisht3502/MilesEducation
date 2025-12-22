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
        String eligibility = 'Eligibility Criteria';
        List<Lead> leads = [SELECT Id, OwnerId, Phone, City__c, Course__c, Source_Bucket__c, GP_User__c FROM Lead WHERE Id = :recordId LIMIT 1];

        if (leads.isEmpty()) return;

        RoundRobinAssigner.assignWithStickyAndRoundRobin((List<SObject>) leads,'Lead', eligibility);

        EligibilityFolderService.createFoldersForLead(recordId);
    }
}