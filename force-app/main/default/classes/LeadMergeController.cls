public without sharing class LeadMergeController {

    private static final Set<String> ALLOWED_NAMES = new Set<String>{ 'CC', 'SR' };

    @AuraEnabled(cacheable=true)
    public static UserAccessWrapper getUserAccessInfo() {
        User currentUser = [SELECT Id, Profile.Name, UserRole.DeveloperName FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        UserAccessWrapper wrapper = new UserAccessWrapper();
        wrapper.profileName = currentUser.Profile != null ? currentUser.Profile.Name : null;
        wrapper.roleName = currentUser.UserRole != null ? currentUser.UserRole.DeveloperName : null;
        wrapper.hasAccess = ALLOWED_NAMES.contains(wrapper.profileName) || ALLOWED_NAMES.contains(wrapper.roleName);
        wrapper.message = wrapper.hasAccess ? null : 'You do not have access. Only CC and SR users can merge leads.';
        return wrapper;
    }

    @AuraEnabled
    public static List<LeadWrapper> searchLeads(String searchKey, Id currentLeadId, List<Id> selectedLeadIds) {
        if (String.isBlank(searchKey)) return new List<LeadWrapper>();

        String key = '%' + searchKey + '%';
        Set<Id> excludeIds = new Set<Id>();
        if (currentLeadId != null) excludeIds.add(currentLeadId);
        if (selectedLeadIds != null) excludeIds.addAll(selectedLeadIds);

        Set<Id> candidateIds = new Set<Id>();
        if (searchKey.length() >= 3) {
            for (Phone_Number__c phoneNumber : [SELECT Candidate__c FROM Phone_Number__c WHERE Phone__c LIKE :key AND Candidate__c != null LIMIT 50]) {
                candidateIds.add(phoneNumber.Candidate__c);
            }
        }

        for (Lead__c customLead : [SELECT Candidate__c FROM Lead__c WHERE Candidate__c != null AND (Name LIKE :key OR Phone__c LIKE :key OR Candidate__r.Name LIKE :key OR Candidate__r.Phone LIKE :key OR Candidate__r.Candidate_ID__c LIKE :key) LIMIT 50]) {
            candidateIds.add(customLead.Candidate__c);
        }

        for (Lead candidate : [SELECT Id FROM Lead WHERE Name LIKE :key OR Email LIKE :key OR Phone LIKE :key OR Candidate_ID__c LIKE :key LIMIT 50]) {
            candidateIds.add(candidate.Id);
        }

        candidateIds.removeAll(excludeIds);
        if (candidateIds.isEmpty()) return new List<LeadWrapper>();

        List<Lead> results = [SELECT Id, Name, Email, Phone, Course__c, Owner.Name, OwnerId, Candidate__c, Candidate_ID__c FROM Lead WHERE Id IN :candidateIds AND (Is_Merged__c = false OR Is_Merged__c = null) ORDER BY Name LIMIT 10];
        if (results.isEmpty()) return new List<LeadWrapper>();

        Set<Id> leadIds = new Set<Id>();
        Set<Id> ownerIds = new Set<Id>();
        for (Lead leadRecord : results) {
            leadIds.add(leadRecord.Id);
            ownerIds.add(leadRecord.OwnerId);
        }

        Set<Id> pendingLeadIds = new Set<Id>();
        for (Approval_Process__c approvalRecord : [SELECT Source_Candidate__c, Target_Candidate__c FROM Approval_Process__c WHERE Merge_Status__c = 'Pending' AND Record_Type__c = 'Lead Merged Request' AND (Source_Candidate__c IN :leadIds OR Target_Candidate__c IN :leadIds)]) {
            if (approvalRecord.Source_Candidate__c != null) pendingLeadIds.add(approvalRecord.Source_Candidate__c);
            if (approvalRecord.Target_Candidate__c != null) pendingLeadIds.add(approvalRecord.Target_Candidate__c);
        }

        Map<Id, Id> ownerManagerMap = new Map<Id, Id>();
        if (!ownerIds.isEmpty()) {
            for (User ownerUser : [SELECT Id, ManagerId FROM User WHERE Id IN :ownerIds]) {
                ownerManagerMap.put(ownerUser.Id, ownerUser.ManagerId);
            }
        }

        Map<Id, List<Lead__c>> customLeadsByCandidate = getCustomLeadsByCandidate(leadIds);
        List<LeadWrapper> wrappers = new List<LeadWrapper>();
        for (Lead leadRecord : results) {
            LeadWrapper wrapper = new LeadWrapper();
            wrapper.lead = leadRecord;
            wrapper.ownerManagerId = ownerManagerMap.get(leadRecord.OwnerId);
            wrapper.isUnderApproval = pendingLeadIds.contains(leadRecord.Id);
            wrapper.approvalMessage = wrapper.isUnderApproval ? 'One process already exists for this lead merge.' : null;
            wrapper.customLeads = customLeadsByCandidate.containsKey(leadRecord.Id) ? customLeadsByCandidate.get(leadRecord.Id) : new List<Lead__c>();
            wrapper.courseSummary = buildCourseSummary(wrapper.customLeads);
            wrappers.add(wrapper);
        }
        return wrappers;
    }

    @AuraEnabled(cacheable=true)
    public static LeadWrapper getLeadDetails(Id leadId) {
        if (leadId == null) return null;

        List<Lead> leads = [SELECT Id, Name, Email, Phone, Course__c, Owner.Name, OwnerId, Candidate__c, Candidate_ID__c FROM Lead WHERE Id = :leadId];
        if (leads.isEmpty()) return null;

        Lead leadRecord = leads[0];
        Boolean isPending = ![SELECT Id FROM Approval_Process__c WHERE Merge_Status__c = 'Pending' AND Record_Type__c = 'Lead Merged Request' AND (Source_Candidate__c = :leadId OR Target_Candidate__c = :leadId) LIMIT 1].isEmpty();

        LeadWrapper wrapper = new LeadWrapper();
        wrapper.lead = leadRecord;
        wrapper.isUnderApproval = isPending;
        wrapper.approvalMessage = isPending ? 'One process already exists for this lead merge.' : null;
        wrapper.customLeads = getCustomLeadsByCandidate(new Set<Id>{ leadId }).get(leadId);
        if (wrapper.customLeads == null) {
            wrapper.customLeads = new List<Lead__c>();
        }
        wrapper.courseSummary = buildCourseSummary(wrapper.customLeads);

        if (String.valueOf(leadRecord.OwnerId).startsWith('005')) {
            List<User> users = [SELECT Id, ManagerId FROM User WHERE Id = :leadRecord.OwnerId LIMIT 1];
            if (!users.isEmpty()) {
                wrapper.ownerManagerId = users[0].ManagerId;
            }
        }
        return wrapper;
    }

    public class LeadWrapper {
        @AuraEnabled public Lead lead;
        @AuraEnabled public Boolean isUnderApproval;
        @AuraEnabled public String ownerManagerId;
        @AuraEnabled public String courseSummary;
        @AuraEnabled public List<Lead__c> customLeads;
        @AuraEnabled public String approvalMessage;
    }

    public class UserAccessWrapper {
        @AuraEnabled public Boolean hasAccess;
        @AuraEnabled public String message;
        @AuraEnabled public String profileName;
        @AuraEnabled public String roleName;
    }

    @AuraEnabled
    public static String submitMergeForApproval(Id mainLeadId, Id sourceLeadId, List<Id> leadIdsToMerge, String mergeComments) {
        validateMergeAccess();

        Id finalSourceId = sourceLeadId;
        if (finalSourceId == null && leadIdsToMerge != null && !leadIdsToMerge.isEmpty()) {
            finalSourceId = leadIdsToMerge[0];
        }
        if (finalSourceId == null) {
            throw new AuraHandledException('No lead selected to merge');
        }

        Set<Id> allIdsToCheck = new Set<Id>{ mainLeadId, finalSourceId };
        List<Approval_Process__c> pendingRequests = [SELECT Source_Candidate__c, Target_Candidate__c, Source_Candidate__r.Name FROM Approval_Process__c WHERE Merge_Status__c = 'Pending' AND Record_Type__c = 'Lead Merged Request' AND (Source_Candidate__c IN :allIdsToCheck OR Target_Candidate__c IN :allIdsToCheck)];
        if (!pendingRequests.isEmpty()) {
            throw new AuraHandledException('One of the involves leads is already part of a pending merge request.');
        }

        Lead sourceLead = [SELECT Id, Name, OwnerId FROM Lead WHERE Id = :finalSourceId];
        Lead mainLead = [SELECT Id, Name, OwnerId FROM Lead WHERE Id = :mainLeadId];
        Id currentUserId = UserInfo.getUserId();
        Set<Id> ownerIds = new Set<Id>{ mainLead.OwnerId, sourceLead.OwnerId };
        Map<Id, User> ownerMap = new Map<Id, User>([SELECT Id, ManagerId FROM User WHERE Id IN :ownerIds]);

        Boolean isSameGM = true;
        for (Id ownerId : ownerIds) {
            User ownerUser = ownerMap.get(ownerId);
            if (ownerUser == null || ownerUser.ManagerId != currentUserId) {
                isSameGM = false;
                break;
            }
        }

        Id approverId = determineApprover(mainLead, sourceLead, ownerMap);
        if (String.isBlank(mergeComments)) {
            throw new AuraHandledException('Comment is required for this merge.');
        }

        Id recordTypeId = Schema.SObjectType.Approval_Process__c.getRecordTypeInfosByDeveloperName().get('Lead_Merged_Request').getRecordTypeId();
        Approval_Process__c approvalRecord = new Approval_Process__c();
        approvalRecord.Source_Candidate__c = finalSourceId;
        approvalRecord.Target_Candidate__c = mainLeadId;
        approvalRecord.Comments__c = mergeComments;
        approvalRecord.Requestor__c = currentUserId;
        approvalRecord.Approver__c = approverId;
        approvalRecord.Merge_Status__c = isSameGM ? 'Approved' : 'Pending';
        approvalRecord.RecordTypeId = recordTypeId;
        approvalRecord.Record_Type__c = 'Lead Merged Request';
        insert approvalRecord;

        if (isSameGM) {
            CandidateMergeService.mergeCandidates(finalSourceId, mainLeadId, mergeComments);
            LeadMergeApprovalDecisionController.sendNotifications(approvalRecord.Id, currentUserId, 'Lead_Merge_Approved');
            return 'Leads merged successfully (Directly Approved).';
        }

        LeadMergeApprovalDecisionController.sendNotifications(approvalRecord.Id, approverId, 'Lead_Merge_Approval_Request');
        return 'Approval request submitted and pending manager review.';
    }

    @AuraEnabled(cacheable=true)
    public static ComparisonWrapper getComparisonDetails(Id approvalId) {
        if (approvalId == null) return null;

        Approval_Process__c approvalRecord = [SELECT Source_Candidate__c, Target_Candidate__c FROM Approval_Process__c WHERE Id = :approvalId LIMIT 1];
        Set<Id> leadIds = new Set<Id>();
        if (approvalRecord.Source_Candidate__c != null) leadIds.add(approvalRecord.Source_Candidate__c);
        if (approvalRecord.Target_Candidate__c != null) leadIds.add(approvalRecord.Target_Candidate__c);
        if (leadIds.isEmpty()) return null;

        Map<Id, Lead> leadMap = new Map<Id, Lead>([SELECT Id, Name, Email, Course__c, LeadSource, Status, Owner.Name FROM Lead WHERE Id IN :leadIds]);
        Map<Id, List<Lead__c>> customLeadsByCandidate = new Map<Id, List<Lead__c>>();
        for (Lead__c customLead : [SELECT Id, Name, Stage__c, Status__c, Course__c, Candidate__c FROM Lead__c WHERE Candidate__c IN :leadIds ORDER BY CreatedDate DESC]) {
            if (!customLeadsByCandidate.containsKey(customLead.Candidate__c)) {
                customLeadsByCandidate.put(customLead.Candidate__c, new List<Lead__c>());
            }
            customLeadsByCandidate.get(customLead.Candidate__c).add(customLead);
        }

        ComparisonWrapper comparison = new ComparisonWrapper();
        comparison.source = new SingleLeadData(leadMap.get(approvalRecord.Source_Candidate__c), customLeadsByCandidate.containsKey(approvalRecord.Source_Candidate__c) ? customLeadsByCandidate.get(approvalRecord.Source_Candidate__c) : new List<Lead__c>());
        comparison.target = new SingleLeadData(leadMap.get(approvalRecord.Target_Candidate__c), customLeadsByCandidate.containsKey(approvalRecord.Target_Candidate__c) ? customLeadsByCandidate.get(approvalRecord.Target_Candidate__c) : new List<Lead__c>());
        return comparison;
    }

    public class ComparisonWrapper {
        @AuraEnabled public SingleLeadData source;
        @AuraEnabled public SingleLeadData target;
    }

    public class SingleLeadData {
        @AuraEnabled public Lead standardLead;
        @AuraEnabled public List<Lead__c> customLeads;

        public SingleLeadData(Lead standardLead, List<Lead__c> customLeads) {
            this.standardLead = standardLead;
            this.customLeads = customLeads;
        }
    }

    private static Id determineApprover(Lead mainLead, Lead sourceLead, Map<Id, User> userMap) {
        User requestor = [SELECT Id, ManagerId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        if (requestor.ManagerId != null && (mainLead.OwnerId == requestor.ManagerId || sourceLead.OwnerId == requestor.ManagerId)) {
            return requestor.ManagerId;
        }

        Set<Id> managerIds = new Set<Id>();
        User mainOwner = userMap.get(mainLead.OwnerId);
        User sourceOwner = userMap.get(sourceLead.OwnerId);
        if (mainOwner != null && mainOwner.ManagerId != null) managerIds.add(mainOwner.ManagerId);
        if (sourceOwner != null && sourceOwner.ManagerId != null) managerIds.add(sourceOwner.ManagerId);
        if (managerIds.size() == 1 && !managerIds.isEmpty()) {
            return new List<Id>(managerIds)[0];
        }
        return getAdminIdFromLabel();
    }

    private static void validateMergeAccess() {
        UserAccessWrapper access = getUserAccessInfo();
        if (access == null || access.hasAccess != true) {
            throw new AuraHandledException('You do not have access. Only CC and SR users can merge leads.');
        }
    }

    private static Map<Id, List<Lead__c>> getCustomLeadsByCandidate(Set<Id> leadIds) {
        Map<Id, List<Lead__c>> customLeadsByCandidate = new Map<Id, List<Lead__c>>();
        if (leadIds == null || leadIds.isEmpty()) {
            return customLeadsByCandidate;
        }

        for (Lead__c customLead : [SELECT Id, Name, Stage__c, Status__c, Course__c, Candidate__c, City__c FROM Lead__c WHERE Candidate__c IN :leadIds ORDER BY CreatedDate DESC]) {
            if (!customLeadsByCandidate.containsKey(customLead.Candidate__c)) {
                customLeadsByCandidate.put(customLead.Candidate__c, new List<Lead__c>());
            }
            customLeadsByCandidate.get(customLead.Candidate__c).add(customLead);
        }
        return customLeadsByCandidate;
    }

    private static String buildCourseSummary(List<Lead__c> customLeads) {
        if (customLeads == null || customLeads.isEmpty()) {
            return 'No related leads';
        }

        Set<String> uniqueCourses = new Set<String>();
        for (Lead__c customLead : customLeads) {
            if (String.isNotBlank(customLead.Course__c)) {
                uniqueCourses.add(customLead.Course__c);
            }
        }
        if (uniqueCourses.isEmpty()) {
            return 'No related leads';
        }

        List<String> sortedCourses = new List<String>();
        sortedCourses.addAll(uniqueCourses);
        sortedCourses.sort();
        return String.join(sortedCourses, ', ');
    }

    private static Id getAdminIdFromLabel() {
        String adminUsername = Label.Admin_Username;
        if (String.isBlank(adminUsername)) {
            throw new AuraHandledException('Custom label Admin_Username is blank.');
        }

        List<User> adminUsers = [SELECT Id FROM User WHERE Username = :adminUsername AND IsActive = true LIMIT 1];
        if (adminUsers.isEmpty()) {
            throw new AuraHandledException('No active user found for Admin_Username label value: ' + adminUsername);
        }
        return adminUsers[0].Id;
    }
}