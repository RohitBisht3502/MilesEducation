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

        // Assuming this is Lead Id
        List<Lead__c> lead = [
            SELECT Id, OwnerId, City__c, Course__c, Source__c
            FROM Lead__c
            WHERE Id = :recordId
            LIMIT 1
        ];
        String eligibility = 'Eligibility Criteria';
        RoundRobinService.assignForLeads(lead, eligibility);

        EligibilityFolderService.createFoldersForLead(recordId);
    }
}