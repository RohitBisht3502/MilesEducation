public without sharing class LeadMergeController {

    @AuraEnabled(cacheable=true)
    public static List<Lead__c> searchLeads(String searchKey, Id currentLeadId) {
        if (String.isBlank(searchKey)) return new List<Lead__c>();

        String key = '%' + searchKey + '%';

        // Exclude the current lead from search results
        return [
            SELECT Id, Name, Phone__c, Email__c, OwnerId, owner.Name
            FROM Lead__c
            WHERE (Phone__c LIKE :key
               OR Name LIKE :key
               OR Email__c LIKE :key)
            AND Id != :currentLeadId
            LIMIT 50
        ];
    }

    @AuraEnabled
    public static String submitMergeForApproval(Id lead1Id, Id lead2Id) {

        // Query leads
        Lead__c l1 = [
            SELECT Id, OwnerId
            FROM Lead__c WHERE Id = :lead1Id LIMIT 1
        ];

        Lead__c l2 = [
            SELECT Id, OwnerId
            FROM Lead__c WHERE Id = :lead2Id LIMIT 1
        ];

        // --- TAGGING SELECTED LEAD ---
        l1.Lead__c = lead2Id;
        update l1;

        // Query Owners as User records
        User u1 = [
            SELECT Id, ManagerId 
            FROM User 
            WHERE Id = :l1.OwnerId
        ];

        User u2 = [
            SELECT Id, ManagerId 
            FROM User 
            WHERE Id = :l2.OwnerId
        ];

        Id finalApprover;

        // --- BUSINESS LOGIC ---
        if (l1.OwnerId == l2.OwnerId) {
            // Same owner - send to their manager
            finalApprover = u1.ManagerId;
        }
        else if (u1.ManagerId == u2.ManagerId) {
            // Different owners but same manager - send to common manager
            finalApprover = u1.ManagerId;
        }
        else {
            // Different owners and different managers - send to Admin
            finalApprover = '005C1000005OqaTIAS'; // Admin User ID
        }

        // Validate finalApprover exists
        if (finalApprover == null) {
            throw new AuraHandledException('No valid approver found. Please contact administrator.');
        }

        // Submit for approval
        Approval.ProcessSubmitRequest req = new Approval.ProcessSubmitRequest();
        req.setObjectId(lead1Id);
        req.setProcessDefinitionNameOrId('Lead_merge');
        req.setNextApproverIds(new Id[]{ finalApprover });

        try {
            Approval.ProcessResult result = Approval.process(req);

            if (result.isSuccess()) {
                return 'Merge request submitted for approval successfully';
            } else {
                String errorMsg = '';
                for(Database.Error err : result.getErrors()) {
                    errorMsg += err.getMessage() + '\n';
                }
                throw new AuraHandledException('Error submitting approval: ' + errorMsg);
            }
        } catch (Exception e) {
            throw new AuraHandledException('Error: ' + e.getMessage());
        }
    }
}