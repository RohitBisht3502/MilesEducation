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


    @AuraEnabled
    public static List<LeadWrapper> searchLeads(String searchKey, Id currentLeadId, List<Id> selectedLeadIds) {

        if (String.isBlank(searchKey)) return new List<LeadWrapper>();

        String key = '%' + searchKey + '%';

        // Exclude current lead + selected leads
        Set<Id> excludeIds = new Set<Id>();
        if (currentLeadId != null) excludeIds.add(currentLeadId);
        if (selectedLeadIds != null) excludeIds.addAll(selectedLeadIds);

        List<Lead__c> results = [
            SELECT Id, Name, Email__c, Phone__c, Course__c, Owner.Name, OwnerId, Lead__c, Status__c
            FROM Lead__c
            WHERE (Name LIKE :key OR Phone__c LIKE :key OR Email__c LIKE :key)
            AND Id NOT IN :excludeIds
            AND (Is_Merged__c = false OR Is_Merged__c = null)
            LIMIT 10
        ];

        if (results.isEmpty()) {
            List<Lead> standardLeads = [
                SELECT Id, Candidate_ID__c FROM Lead WHERE Candidate_ID__c LIKE :key LIMIT 10
            ];
            if (!standardLeads.isEmpty()) {
                Set<Id> stdLeadIds = new Set<Id>();
                for (Lead ld : standardLeads) stdLeadIds.add(ld.Id);
                results = [
                    SELECT Id, Name, Email__c, Phone__c, Course__c, Owner.Name, OwnerId, Lead__c, Status__c
                    FROM Lead__c
                    WHERE Candidate__c IN :stdLeadIds
                    AND Id NOT IN :excludeIds
                    AND (Is_Merged__c = false OR Is_Merged__c = null)
                    LIMIT 10
                ];
            }
        }

        if (results.isEmpty()) return new List<LeadWrapper>();

        // COLLECT IDs & Owners
        Set<Id> leadIds = new Set<Id>();
        Set<Id> parentIds = new Set<Id>();
        Set<Id> ownerIds = new Set<Id>();
        
        for (Lead__c l : results) {
            leadIds.add(l.Id);
            ownerIds.add(l.OwnerId);
            if (l.Lead__c != null) {
                parentIds.add(l.Lead__c);
            }
        }

        // Fetch Manager Ids for Owners
        Map<Id, Id> ownerManagerMap = new Map<Id, Id>();
        if (!ownerIds.isEmpty()) {
            for(User u : [SELECT Id, ManagerId FROM User WHERE Id IN :ownerIds]) {
                ownerManagerMap.put(u.Id, u.ManagerId);
            }
        }

        // 1. QUERY PENDING PROCESSES (For both Leads and Parents)
        Set<Id> allIdsToCheck = new Set<Id>(leadIds);
        allIdsToCheck.addAll(parentIds);
        
        Set<Id> lockedIds = new Set<Id>();
        if (!allIdsToCheck.isEmpty()) {
            for (ProcessInstance pi : [
                SELECT TargetObjectId 
                FROM ProcessInstance 
                WHERE Status = 'Pending' 
                AND TargetObjectId IN :allIdsToCheck
            ]) {
                lockedIds.add(pi.TargetObjectId);
            }
        }

        // 2. QUERY PARENT STATUS (Explicitly)
        Map<Id, String> parentStatusMap = new Map<Id, String>();
        if (!parentIds.isEmpty()) {
            for (Lead__c parent : [SELECT Id, Status__c FROM Lead__c WHERE Id IN :parentIds]) {
                parentStatusMap.put(parent.Id, parent.Status__c);
            }
        }

        List<LeadWrapper> wrappers = new List<LeadWrapper>();
        for (Lead__c l : results) {
            LeadWrapper lw = new LeadWrapper();
            lw.lead = l;
            lw.ownerManagerId = ownerManagerMap.get(l.OwnerId); // May be null if owner is Queue
            
            Boolean selfLocked = lockedIds.contains(l.Id);
            Boolean selfPending = l.Status__c == 'Pending';
            
            Boolean parentLocked = (l.Lead__c != null && lockedIds.contains(l.Lead__c));
            Boolean parentPending = (l.Lead__c != null && parentStatusMap.containsKey(l.Lead__c) && parentStatusMap.get(l.Lead__c) == 'Pending');
            
            lw.isUnderApproval = selfLocked || selfPending || parentLocked || parentPending;
            wrappers.add(lw);
        }

        return wrappers;
    }

    @AuraEnabled(cacheable=true)
    public static LeadWrapper getLeadDetails(Id leadId) {
        if (leadId == null) return null;
        
        List<Lead__c> leads = [SELECT Id, Name, Email__c, Phone__c, Course__c, Owner.Name, OwnerId, Lead__c, Status__c 
                     FROM Lead__c WHERE Id = :leadId];
        
        if (leads.isEmpty()) return null;
        Lead__c l = leads[0];

        LeadWrapper lw = new LeadWrapper();
        lw.lead = l;
        
        // Handle Owner being a User or Queue
        if (String.valueOf(l.OwnerId).startsWith('005')) { // 005 is User prefix
             List<User> users = [SELECT Id, ManagerId FROM User WHERE Id = :l.OwnerId LIMIT 1];
             if (!users.isEmpty()) {
                 lw.ownerManagerId = users[0].ManagerId;
             }
        }
        
        return lw;
    }

    public class LeadWrapper {
        @AuraEnabled public Lead__c lead;
        @AuraEnabled public Boolean isUnderApproval;
        @AuraEnabled public String ownerManagerId;
    }

     // ===== APEX CONTROLLER METHOD =====

    @AuraEnabled
    public static String submitMergeForApproval(Id mainLeadId, List<Id> leadIdsToMerge, String mergeComments) {
        
        if (leadIdsToMerge == null || leadIdsToMerge.isEmpty()) {
            throw new AuraHandledException('No leads selected to merge');
        }

        // -------------------------
        // VALIDATION
        // -------------------------
        Set<Id> idsToCheck = new Set<Id>();
        idsToCheck.add(mainLeadId);
        idsToCheck.addAll(leadIdsToMerge);

        // Fetch leads to check for parents
        List<Lead__c> leadsToCheck = [SELECT Id, Name, Lead__c, Status__c FROM Lead__c WHERE Id IN :leadIdsToMerge];
        Set<Id> parentIds = new Set<Id>();
        for (Lead__c l : leadsToCheck) {
            if (l.Lead__c != null) {
                parentIds.add(l.Lead__c);
                idsToCheck.add(l.Lead__c);
            }
        }

        // Check ProcessInstances
        Set<Id> lockedIds = new Set<Id>();
        for (ProcessInstance pi : [
            SELECT TargetObjectId 
            FROM ProcessInstance 
            WHERE Status = 'Pending' 
            AND TargetObjectId IN :idsToCheck
        ]) {
            lockedIds.add(pi.TargetObjectId);
        }

        // Check Parent Statuses explicitly
        Map<Id, String> parentStatusMap = new Map<Id, String>();
        if (!parentIds.isEmpty()) {
            for (Lead__c parent : [SELECT Id, Status__c FROM Lead__c WHERE Id IN :parentIds]) {
                parentStatusMap.put(parent.Id, parent.Status__c);
            }
        }

        // A. Check Main Lead
        if (lockedIds.contains(mainLeadId)) {
             throw new AuraHandledException('The current lead is in an approval process.');
        }
        Lead__c currentLead = [SELECT Id, Status__c, OwnerId FROM Lead__c WHERE Id = :mainLeadId];
        if (currentLead.Status__c == 'Pending') {
             throw new AuraHandledException('The current lead status is Pending.');
        }

        // B. Check Selected Leads
        for (Lead__c l : leadsToCheck) {
            if (lockedIds.contains(l.Id)) {
                 throw new AuraHandledException('Lead ' + l.Name + ' is in an approval process.');
            }
            if (l.Status__c == 'Pending') {
                 throw new AuraHandledException('Lead ' + l.Name + ' status is Pending.');
            }
            
            // C. Check Parents
            if (l.Lead__c != null) {
                if (lockedIds.contains(l.Lead__c)) {
                     throw new AuraHandledException('Lead ' + l.Name + ' is part of a pending merge (Parent locked).');
                }
                if (parentStatusMap.containsKey(l.Lead__c) && parentStatusMap.get(l.Lead__c) == 'Pending') {
                     throw new AuraHandledException('Lead ' + l.Name + ' is part of a pending merge (Parent Pending).');
                }
            }
        }

        // -------------------------
        // DETERMINE SCENARIO
        // -------------------------
        // Roles: Admin vs GM vs SPOC
        // Admin: Profile = 'System Administrator' (or similar check)
        // GM: Current User is Manager of Lead Owners
        
        Id currentUserId = UserInfo.getUserId();

        // Collect Owners of all leads (Main + Merged)
        Set<Id> ownerIds = new Set<Id>{currentLead.OwnerId};
        List<Lead__c> leadsToMerge = [SELECT Id, OwnerId FROM Lead__c WHERE Id IN :leadIdsToMerge];
        for (Lead__c l : leadsToMerge) {
            ownerIds.add(l.OwnerId);
        }
        
        // Fetch Owner Details (ManagerId)
        Map<Id, User> ownerMap = new Map<Id, User>([SELECT Id, ManagerId FROM User WHERE Id IN :ownerIds]);

        // Scenario Logic
        // 1. Admin: Merge directly, no approval.
        // 2. GM (Same Manager): If current user is manager of ALL lead owners -> Merge directly (Require Comment).
        // 3. Different GM / Other: Approval to Admin.

        Boolean requiresApproval = true;
        Boolean isSameGM = true;

        // Check if Current User is Manager of ALL owners
        for (Id ownerId : ownerIds) {
            User u = ownerMap.get(ownerId);
            
            // If owner is a Queue, u will be null.
            if (u == null) {
                isSameGM = false;
                break;
            }
            
            // Strict Check: Current User MUST be the Manager.
            // Even if owner is self, managerId must be current user (impossible) -> implies Self is not GM.
            if (u.ManagerId != currentUserId) {
                isSameGM = false;
                break;
            }
        }

        if (isSameGM) {
            // Case 2: Same GM (Current User is everyone's manager)
            requiresApproval = false; 
            // Validate Comment
            if (String.isBlank(mergeComments)) {
                throw new AuraHandledException('Comment is required for this merge.');
            }
            // Store comment on Main Lead
            // Assuming field Lead_Merge_Comments__c exists
            currentLead.put('Lead_Merge_Comments__c', mergeComments);
        } else {
            // Case 1: Different GM -> Send to Admin
            requiresApproval = true;
        }
        
        // -------------------------
        // EXECUTE MERGE
        // -------------------------
        Lead__c mainLead = currentLead; 

        for (Lead__c lead : leadsToMerge) {
            lead.Lead__c = mainLeadId;
        }
        update leadsToMerge;

        if (requiresApproval) {
            mainLead.Status__c = 'Pending';
            update mainLead;

            // Approval Routing Logic (SPOC or Different GM)
            // Use existing logic to determine approver (Common Manager or Admin)
            Id approverId = determineApprover(mainLead, leadsToMerge, ownerMap);

            if (approverId == null) {
                 throw new AuraHandledException('No valid approver found.');
            }
            
            Approval.ProcessSubmitRequest req = new Approval.ProcessSubmitRequest();
            req.setObjectId(mainLeadId);
            req.setProcessDefinitionNameOrId('Lead_merge');
            req.setNextApproverIds(new Id[]{ approverId });  

            try {
                Approval.ProcessResult result = Approval.process(req);
                if (result.isSuccess()) {
                    return 'Merge request submitted for approval.';
                } else {
                    throw new AuraHandledException('Error submitting approval.');
                }
            } catch (Exception e) {
                throw new AuraHandledException('Error: ' + e.getMessage());
            }

        } else {
            // Direct Merge (Admin or Same GM)
            mainLead.Status__c = 'Approved';
            update mainLead; 
            return 'Leads merged successfully (No Approval Required).';
        }
    }

    private static Id determineApprover(Lead__c mainLead, List<Lead__c> leadsToMerge, Map<Id, User> userMap) {
        User mainLeadOwner = userMap.get(mainLead.OwnerId);
        
        Boolean sameOwner = true;
        for (Lead__c lead : leadsToMerge) {
            if (lead.OwnerId != mainLead.OwnerId) {
                sameOwner = false; 
                break;
            }
        }

        if (sameOwner) {
            if (mainLeadOwner.ManagerId != null) return mainLeadOwner.ManagerId;
        }

        Set<Id> managerIds = new Set<Id>();
        if (mainLeadOwner.ManagerId != null) managerIds.add(mainLeadOwner.ManagerId);
        
        for (Lead__c lead : leadsToMerge) {
            User owner = userMap.get(lead.OwnerId);
            if (owner != null && owner.ManagerId != null) managerIds.add(owner.ManagerId);
        }

        if (managerIds.size() == 1 && !managerIds.contains(null)) {
            return new List<Id>(managerIds)[0];
        }

        return '005C1000005OqaTIAS';
    }
}