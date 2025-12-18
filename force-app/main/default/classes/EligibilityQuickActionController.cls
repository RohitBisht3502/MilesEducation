/**
* @File Name : EligibilityQuickActionController.cls
* @Description :
* @Author :
* @Last Modified By :
* @Last Modified On : November 27, 2025
* @Modification Log :
*==============================================================================
* Ver | Date | Author | Modification
*==============================================================================
* 1.0 | November 27, 2025 |   | Initial Version
**/

public without sharing class EligibilityQuickActionController {

    @AuraEnabled
    public static void initializeEligibility(Id recordId) {
        if (recordId == null) {
            throw new AuraHandledException('Record Id is required.');
        }
        String eligibility = 'Eligibility Criteria';
        //List<Lead> lead = [SELECT Id, OwnerId, Phone__c, City__c, Course__c, Source__c, Source_Bucket__c, GP_User__c FROM Lead WHERE Id = :recordId LIMIT 1];

        //RoundRobinAssigner.assignLeadsWithStickyAndRoundRobin(lead, eligibility);

        EligibilityFolderService.createFoldersForLead(recordId);
    }
}