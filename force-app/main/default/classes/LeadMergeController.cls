public without sharing class LeadMergeController {

    // @AuraEnabled(cacheable=true)
    // public static List<Lead__c> searchLeads1(String searchKey, Id currentLeadId, List<Id> selectedLeadIds) {
    //     if (String.isBlank(searchKey)) return new List<Lead__c>();

    //     String key = '%' + searchKey + '%';

    //     // Exclude the current lead and already selected leads from search results
    //     Set<Id> excludeIds = new Set<Id>{currentLeadId};
    //     if (selectedLeadIds != null && !selectedLeadIds.isEmpty()) {
    //         excludeIds.addAll(selectedLeadIds);
    //     }

    //     return [
    //         SELECT Id, Name, Phone__c, Email__c, OwnerId, Owner.Name
    //         FROM Lead__c
    //         WHERE (Phone__c LIKE :key
    //            OR Name LIKE :key
    //            OR Email__c LIKE :key)
    //         AND Id NOT IN :excludeIds
    //         LIMIT 50
    //     ];
    // }


    @AuraEnabled(cacheable=true)
    public static List<Lead__c> searchLeads(String searchKey, Id currentLeadId, List<Id> selectedLeadIds) {

        if (String.isBlank(searchKey)) return new List<Lead__c>();

        String key = '%' + searchKey + '%';

        // Exclude current lead + selected leads
        Set<Id> excludeIds = new Set<Id>();
        if (currentLeadId != null) excludeIds.add(currentLeadId);
        if (selectedLeadIds != null) excludeIds.addAll(selectedLeadIds);

        // -------------------------
        // 1️⃣ FIRST TRY DIRECT SEARCH ON LEAD__c (Name, Phone, Email)
        // -------------------------
        List<Lead__c> results = [
            SELECT Id, Name, Email__c, Phone__c, Course__c, Owner.Name
            FROM Lead__c
            WHERE (Name LIKE :key
                OR Phone__c LIKE :key
                OR Email__c LIKE :key)
            AND Id NOT IN :excludeIds
            AND (Is_Merged__c = false OR Is_Merged__c = null)
            LIMIT 10
        ];

        if (!results.isEmpty()) return results;

        // -------------------------
        // 2️⃣ IF NO RESULTS → SEARCH Candidate_ID__c ON STANDARD LEAD
        // -------------------------
        List<Lead> standardLeads = [
            SELECT Id, Candidate_ID__c
            FROM Lead
            WHERE Candidate_ID__c LIKE :key
            LIMIT 10
        ];

        if (standardLeads.isEmpty()) {
            return results; // still empty
        }

        // Map standard Lead → custom Lead__c lookup field (Candidate__c)
        Set<Id> stdLeadIds = new Set<Id>();
        for (Lead ld : standardLeads) {
            stdLeadIds.add(ld.Id);
        }

        // -------------------------
        // 3️⃣ GET CUSTOM LEADS LINKED TO THESE STANDARD LEADS
        // -------------------------
        results = [
            SELECT Id, Name, Email__c, Phone__c, Course__c, Owner.Name
            FROM Lead__c
            WHERE Candidate__c IN :stdLeadIds
            AND Id NOT IN :excludeIds
            AND (Is_Merged__c = false OR Is_Merged__c = null)
            LIMIT 10
        ];

        return results;
    }

     // ===== APEX CONTROLLER METHOD =====

    @AuraEnabled
    public static String submitMergeForApproval(Id mainLeadId, List<Id> leadIdsToMerge) {
        
        if (leadIdsToMerge == null || leadIdsToMerge.isEmpty()) {
            throw new AuraHandledException('No leads selected to merge');
        }

        // Query main lead
        Lead__c mainLead = [
            SELECT Id, OwnerId, Status__c
            FROM Lead__c 
            WHERE Id = :mainLeadId 
            LIMIT 1
        ];

        // Query all leads to merge
        List<Lead__c> leadsToMerge = [
            SELECT Id, OwnerId
            FROM Lead__c 
            WHERE Id IN :leadIdsToMerge
        ];

        // Tag all selected leads as related to main lead
        for (Lead__c lead : leadsToMerge) {
            lead.Lead__c = mainLeadId;
        }
        update leadsToMerge;

        // Set status to Pending
        mainLead.Status__c = 'Pending';
        update mainLead;

        // Query all owner IDs
        Set<Id> ownerIds = new Set<Id>{mainLead.OwnerId};
        for (Lead__c lead : leadsToMerge) {
            ownerIds.add(lead.OwnerId);
        }

        // Query Users with their managers
        Map<Id, User> userMap = new Map<Id, User>([
            SELECT Id, ManagerId 
            FROM User 
            WHERE Id IN :ownerIds
        ]);

        // Determine approver based on business logic
        Id finalApprover = determineApprover(mainLead, leadsToMerge, userMap);

        // Validate finalApprover exists
        if (finalApprover == null) {
            throw new AuraHandledException('No valid approver found. Please contact administrator.');
        }

        // Submit for approval
        Approval.ProcessSubmitRequest req = new Approval.ProcessSubmitRequest();
        req.setObjectId(mainLeadId);
        req.setProcessDefinitionNameOrId('Lead_merge');
        req.setNextApproverIds(new Id[]{ finalApprover });

        try {
            Approval.ProcessResult result = Approval.process(req);

            if (result.isSuccess()) {
                return 'Merge request for ' + leadIdsToMerge.size() + ' lead(s) submitted successfully';
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

    private static Id determineApprover(Lead__c mainLead, List<Lead__c> leadsToMerge, Map<Id, User> userMap) {
        User mainLeadOwner = userMap.get(mainLead.OwnerId);
        
        // Check if all leads have the same owner
        Boolean sameOwner = true;
        for (Lead__c lead : leadsToMerge) {
            if (lead.OwnerId != mainLead.OwnerId) {
                sameOwner = false;
                break;
            }
        }

        if (sameOwner) {
            // All have same owner - send to their manager
            return mainLeadOwner.ManagerId;
        }

        // Check if all owners share the same manager
        Set<Id> managerIds = new Set<Id>();
        managerIds.add(mainLeadOwner.ManagerId);
        
        for (Lead__c lead : leadsToMerge) {
            User owner = userMap.get(lead.OwnerId);
            if (owner != null && owner.ManagerId != null) {
                managerIds.add(owner.ManagerId);
            }
        }

        if (managerIds.size() == 1 && !managerIds.contains(null)) {
            // All have same manager
            return new List<Id>(managerIds)[0];
        }

        // Different managers - send to Admin
        return '005C1000005OqaTIAS'; // Admin User ID
    }
}