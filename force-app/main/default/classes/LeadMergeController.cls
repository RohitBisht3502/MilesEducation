public without sharing class LeadMergeController {

    @AuraEnabled
    public static List<LeadWrapper> searchLeads(String searchKey, Id currentLeadId, List<Id> selectedLeadIds) {

        if (String.isBlank(searchKey)) return new List<LeadWrapper>();

        String key = '%' + searchKey + '%';

        // Exclude current lead + selected leads
        Set<Id> excludeIds = new Set<Id>();
        if (currentLeadId != null) excludeIds.add(currentLeadId);
        if (selectedLeadIds != null) excludeIds.addAll(selectedLeadIds);

        // Phone search logic
        Set<Id> candidateIdsFromPhone = new Set<Id>();
        if (searchKey.length() >= 3) {
            for (Phone_Number__c pn : [SELECT Candidate__c FROM Phone_Number__c WHERE Phone__c LIKE :key AND Candidate__c != null LIMIT 50]) {
                candidateIdsFromPhone.add(pn.Candidate__c);
            }
        }

        List<Lead> results = [
            SELECT Id, Name, Email, Course__c, Owner.Name, OwnerId, Candidate__c, Merged_Status__c, Candidate_ID__c
            FROM Lead
            WHERE (Name LIKE :key OR Email LIKE :key OR Id IN :candidateIdsFromPhone OR Candidate_ID__c LIKE :key)
            AND Id NOT IN :excludeIds
            AND (Is_Merged__c = false OR Is_Merged__c = null)
            LIMIT 10
        ];

        if (results.isEmpty()) return new List<LeadWrapper>();

        // COLLECT IDs & Owners
        Set<Id> leadIds = new Set<Id>();
        Set<Id> parentIds = new Set<Id>();
        Set<Id> ownerIds = new Set<Id>();
        
        for (Lead l : results) {
            leadIds.add(l.Id);
            ownerIds.add(l.OwnerId);
            if (l.Candidate__c != null) {
                parentIds.add(l.Candidate__c);
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
            for (Lead parent : [SELECT Id, Merged_Status__c FROM Lead WHERE Id IN :parentIds]) {
                parentStatusMap.put(parent.Id, parent.Merged_Status__c);
            }
        }

        List<LeadWrapper> wrappers = new List<LeadWrapper>();
        for (Lead l : results) {
            LeadWrapper lw = new LeadWrapper();
            lw.lead = l;
            lw.ownerManagerId = ownerManagerMap.get(l.OwnerId); // May be null if owner is Queue
            
            Boolean selfLocked = lockedIds.contains(l.Id);
            Boolean selfPending = l.Merged_Status__c == 'Pending';
            
            Boolean parentLocked = (l.Candidate__c != null && lockedIds.contains(l.Candidate__c));
            Boolean parentPending = (l.Candidate__c != null && parentStatusMap.containsKey(l.Candidate__c) && parentStatusMap.get(l.Candidate__c) == 'Pending');
            
            lw.isUnderApproval = selfLocked || selfPending || parentLocked || parentPending;
            wrappers.add(lw);
        }

        return wrappers;
    }

    @AuraEnabled(cacheable=true)
    public static LeadWrapper getLeadDetails(Id leadId) {
        if (leadId == null) return null;
        
        List<Lead> leads = [SELECT Id, Name, Email, Course__c, Owner.Name, OwnerId, Candidate__c, Merged_Status__c 
                     FROM Lead WHERE Id = :leadId];
        
        if (leads.isEmpty()) return null;
        Lead l = leads[0];

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
        @AuraEnabled public Lead lead;
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
        List<Lead> leadsToCheck = [SELECT Id, Name, Candidate__c, Merged_Status__c, Course__c FROM Lead WHERE Id IN :leadIdsToMerge];
        Set<Id> parentIds = new Set<Id>();
        for (Lead l : leadsToCheck) {
            if (l.Candidate__c != null) {
                parentIds.add(l.Candidate__c);
                idsToCheck.add(l.Candidate__c);
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
            for (Lead parent : [SELECT Id, Merged_Status__c FROM Lead WHERE Id IN :parentIds]) {
                parentStatusMap.put(parent.Id, parent.Merged_Status__c);
            }
        }

        // A. Check Main Lead
        if (lockedIds.contains(mainLeadId)) {
             throw new AuraHandledException('The current lead is in an approval process.');
        }
        Lead currentLead = [SELECT Id, Merged_Status__c, OwnerId, Course__c FROM Lead WHERE Id = :mainLeadId];
        if (currentLead.Merged_Status__c == 'Pending') {
             throw new AuraHandledException('The current lead status is Pending.');
        }

        // B. Check Selected Leads
        for (Lead l : leadsToCheck) {
            if (lockedIds.contains(l.Id)) {
                 throw new AuraHandledException('Lead ' + l.Name + ' is in an approval process.');
            }
            if (l.Merged_Status__c == 'Pending') {
                 throw new AuraHandledException('Lead ' + l.Name + ' status is Pending.');
            }

            // C. Check Parents
            if (l.Candidate__c != null) {
                if (lockedIds.contains(l.Candidate__c)) {
                     throw new AuraHandledException('Lead ' + l.Name + ' is part of a pending merge (Parent locked).');
                }
                if (parentStatusMap.containsKey(l.Candidate__c) && parentStatusMap.get(l.Candidate__c) == 'Pending') {
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
        List<Lead> leadsToMerge = [SELECT Id, OwnerId FROM Lead WHERE Id IN :leadIdsToMerge];
        for (Lead l : leadsToMerge) {
            ownerIds.add(l.OwnerId);
        }
        
        // Fetch Owner Details (ManagerId and Manager's ManagerId)
        Map<Id, User> ownerMap = new Map<Id, User>([SELECT Id, ManagerId, Manager.ManagerId FROM User WHERE Id IN :ownerIds]);

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
        } else {
            // Case 1: Different GM -> Send to Admin
            requiresApproval = true;
        }
        
        // -------------------------
        // EXECUTE MERGE
        // -------------------------
        Lead mainLead = currentLead; 

        // Always require and store comment on Main Lead for audit
        if (String.isBlank(mergeComments)) {
            throw new AuraHandledException('Comment is required for this merge.');
        }
        mainLead.put('Merge_Comments__c', mergeComments);

        for (Lead lead : leadsToMerge) {
            lead.Candidate__c = mainLeadId;
        }
        update leadsToMerge;

        if (requiresApproval) {
            mainLead.Merged_Status__c = 'Pending';
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
            req.setComments(mergeComments); // Pass user comment to Approval Process
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
            mainLead.Merged_Status__c = 'Approved';
            update mainLead; 
            return 'Leads merged successfully (No Approval Required).';
        }
    }

    private static Id determineApprover(Lead mainLead, List<Lead> leadsToMerge, Map<Id, User> userMap) {
        User mainLeadOwner = userMap.get(mainLead.OwnerId);
        Id adminId = '005C1000005Qn8fIAC';

        // Collect unique manager IDs from all owners (Main + Merged)
        Set<Id> managerIds = new Set<Id>();
        if (mainLeadOwner != null && mainLeadOwner.ManagerId != null) {
            managerIds.add(mainLeadOwner.ManagerId);
        }
        
        for (Lead lead : leadsToMerge) {
            User owner = userMap.get(lead.OwnerId);
            if (owner != null && owner.ManagerId != null) {
                managerIds.add(owner.ManagerId);
            } else {
                // If any owner doesn't have a manager (or is a Queue), we can't have a unique common manager
                managerIds.add(null);
            }
        }

        // If there is exactly ONE common manager and they report to someone (Grandparent Manager)
        if (managerIds.size() == 1 && !managerIds.contains(null)) {
            Id commonManagerId = new List<Id>(managerIds)[0];
            
            // We need to check if that common manager has a manager.
            // Since we queried Manager.ManagerId for the OWNERS, it's available in the OWNER's record.
            // All owners in this case have the same info because they share the same manager.
            if (mainLeadOwner != null && mainLeadOwner.ManagerId == commonManagerId && mainLeadOwner.Manager.ManagerId != null) {
                return mainLeadOwner.Manager.ManagerId;
            }
        }

        // Otherwise (different managers, no manager, or top of hierarchy), send to Admin
        return adminId;
    }
}