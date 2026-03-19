public without sharing class LeadMergeController {

    @AuraEnabled
    public static List<LeadWrapper> searchLeads(String searchKey, Id currentLeadId, List<Id> selectedLeadIds) {

        if (String.isBlank(searchKey)) return new List<LeadWrapper>();

        String key = '%' + searchKey + '%';

        Set<Id> excludeIds = new Set<Id>();
        if (currentLeadId != null) excludeIds.add(currentLeadId);
        if (selectedLeadIds != null) excludeIds.addAll(selectedLeadIds);

        Set<Id> candidateIdsFromPhone = new Set<Id>();
        if (searchKey.length() >= 3) {
            for (Phone_Number__c pn : [SELECT Candidate__c FROM Phone_Number__c WHERE Phone__c LIKE :key AND Candidate__c != null LIMIT 50]) {
                candidateIdsFromPhone.add(pn.Candidate__c);
            }
        }

        List<Lead> results = [
            SELECT Id, Name, Email, Course__c, Owner.Name, OwnerId, Candidate__c, Candidate_ID__c
            FROM Lead
            WHERE (Name LIKE :key OR Email LIKE :key OR Id IN :candidateIdsFromPhone OR Candidate_ID__c LIKE :key)
            AND Id NOT IN :excludeIds
            AND (Is_Merged__c = false OR Is_Merged__c = null)
            LIMIT 10
        ];

        if (results.isEmpty()) return new List<LeadWrapper>();

        Set<Id> leadIds = new Set<Id>();
        Set<Id> ownerIds = new Set<Id>();
        for (Lead l : results) {
            leadIds.add(l.Id);
            ownerIds.add(l.OwnerId);
        }

        Set<Id> pendingLeadIds = new Set<Id>();
        for (Approval_Process__c ap : [
            SELECT Source_Candidate__c, Target_Candidate__c 
            FROM Approval_Process__c 
            WHERE Merge_Status__c = 'Pending' 
            AND Record_Type__c = 'Lead Merged Request'
            AND (Source_Candidate__c IN :leadIds OR Target_Candidate__c IN :leadIds)
        ]) {
            if (ap.Source_Candidate__c != null) pendingLeadIds.add(ap.Source_Candidate__c);
            if (ap.Target_Candidate__c != null) pendingLeadIds.add(ap.Target_Candidate__c);
        }

        Map<Id, Id> ownerManagerMap = new Map<Id, Id>();
        if (!ownerIds.isEmpty()) {
            for(User u : [SELECT Id, ManagerId FROM User WHERE Id IN :ownerIds]) {
                ownerManagerMap.put(u.Id, u.ManagerId);
            }
        }

        List<LeadWrapper> wrappers = new List<LeadWrapper>();
        for (Lead l : results) {
            LeadWrapper lw = new LeadWrapper();
            lw.lead = l;
            lw.ownerManagerId = ownerManagerMap.get(l.OwnerId);
            lw.isUnderApproval = pendingLeadIds.contains(l.Id);
            wrappers.add(lw);
        }

        return wrappers;
    }

    @AuraEnabled(cacheable=true)
    public static LeadWrapper getLeadDetails(Id leadId) {
        if (leadId == null) return null;
        
        List<Lead> leads = [SELECT Id, Name, Email, Course__c, Owner.Name, OwnerId, Candidate__c
                     FROM Lead WHERE Id = :leadId];
        
        if (leads.isEmpty()) return null;
        Lead l = leads[0];

        Boolean isPending = ![
            SELECT Id FROM Approval_Process__c 
            WHERE Merge_Status__c = 'Pending' 
            AND Record_Type__c = 'Lead Merged Request'
            AND (Source_Candidate__c = :leadId OR Target_Candidate__c = :leadId)
            LIMIT 1
        ].isEmpty();

        LeadWrapper lw = new LeadWrapper();
        lw.lead = l;
        lw.isUnderApproval = isPending;
        
        if (String.valueOf(l.OwnerId).startsWith('005')) {
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

    @AuraEnabled
    public static String submitMergeForApproval(Id mainLeadId, Id sourceLeadId, List<Id> leadIdsToMerge, String mergeComments) {
        
        // Handle both parameter styles to avoid deployment/cache sync issues
        Id finalSourceId = sourceLeadId;
        if (finalSourceId == null && leadIdsToMerge != null && !leadIdsToMerge.isEmpty()) {
            finalSourceId = leadIdsToMerge[0];
        }

        if (finalSourceId == null) {
            throw new AuraHandledException('No lead selected to merge');
        }

        // -------------------------
        // VALIDATION
        // -------------------------
        Set<Id> allIdsToCheck = new Set<Id>{mainLeadId, finalSourceId};

        List<Approval_Process__c> pendingRequests = [
            SELECT Source_Candidate__c, Target_Candidate__c, Source_Candidate__r.Name
            FROM Approval_Process__c 
            WHERE Merge_Status__c = 'Pending' 
            AND Record_Type__c = 'Lead Merged Request'
            AND (Source_Candidate__c IN :allIdsToCheck OR Target_Candidate__c IN :allIdsToCheck)
        ];

        if (!pendingRequests.isEmpty()) {
            throw new AuraHandledException('One of the involves leads is already part of a pending merge request.');
        }

        Lead sourceLead = [SELECT Id, Name, OwnerId FROM Lead WHERE Id = :finalSourceId];
        Lead mainLead = [SELECT Id, Name, OwnerId FROM Lead WHERE Id = :mainLeadId];

        // -------------------------
        // DETERMINE SCENARIO
        // -------------------------
        Id currentUserId = UserInfo.getUserId();
        Set<Id> ownerIds = new Set<Id>{mainLead.OwnerId, sourceLead.OwnerId};
        Map<Id, User> ownerMap = new Map<Id, User>([SELECT Id, ManagerId FROM User WHERE Id IN :ownerIds]);

        Boolean isSameGM = true;
        for (Id ownerId : ownerIds) {
            User u = ownerMap.get(ownerId);
            if (u == null || u.ManagerId != currentUserId) {
                isSameGM = false;
                break;
            }
        }

        // -------------------------
        // EXECUTE APPROVAL PROCESS CREATION
        // -------------------------
        Id approverId = determineApprover(mainLead, sourceLead, ownerMap);

        if (String.isBlank(mergeComments)) {
            throw new AuraHandledException('Comment is required for this merge.');
        }

        Id recordTypeId = Schema.SObjectType.Approval_Process__c.getRecordTypeInfosByDeveloperName().get('Lead_Merged_Request').getRecordTypeId();

        Approval_Process__c ap = new Approval_Process__c();
        ap.Source_Candidate__c = finalSourceId;
        ap.Target_Candidate__c = mainLeadId;
        ap.Comments__c = mergeComments;
        ap.Requestor__c = currentUserId;
        ap.Approver__c = approverId;
        ap.Merge_Status__c = isSameGM ? 'Approved' : 'Pending';
        ap.RecordTypeId = recordTypeId;
        ap.Record_Type__c = 'Lead Merged Request';
        insert ap;

        if (isSameGM) {
            sourceLead.Candidate__c = mainLeadId;
            sourceLead.Is_Merged__c = true;
            update sourceLead;

            mainLead.Merge_Comments__c = mergeComments;
            update mainLead;

            // Notify Requestor of successful direct merge
            sendNotifications(ap.Id, currentUserId, 'Lead_Merge_Approved');

            return 'Leads merged successfully (Directly Approved).';
        } else {
            // Push & Email Notification to Approver
            sendNotifications(ap.Id, approverId, 'Lead_Merge_Approval_Request');
            return 'Approval request submitted and pending manager review.';
        }
    }

    @AuraEnabled(cacheable=true)
    public static ComparisonWrapper getComparisonDetails(Id approvalId) {
        if (approvalId == null) return null;

        Approval_Process__c ap = [SELECT Source_Candidate__c, Target_Candidate__c FROM Approval_Process__c WHERE Id = :approvalId LIMIT 1];
        
        Set<Id> leadIds = new Set<Id>();
        if (ap.Source_Candidate__c != null) leadIds.add(ap.Source_Candidate__c);
        if (ap.Target_Candidate__c != null) leadIds.add(ap.Target_Candidate__c);

        if (leadIds.isEmpty()) return null;

        Map<Id, Lead> leadMap = new Map<Id, Lead>([
            SELECT Id, Name, Email, Course__c, LeadSource, Status, Owner.Name
            FROM Lead WHERE Id IN :leadIds
        ]);

        Map<Id, List<Lead__c>> customLeadsByCandidate = new Map<Id, List<Lead__c>>();
        for (Lead__c cl : [
            SELECT Id, Name, Stage__c, Status__c, Course__c, Candidate__c
            FROM Lead__c WHERE Candidate__c IN :leadIds
            ORDER BY CreatedDate DESC
        ]) {
            if (!customLeadsByCandidate.containsKey(cl.Candidate__c)) {
                customLeadsByCandidate.put(cl.Candidate__c, new List<Lead__c>());
            }
            customLeadsByCandidate.get(cl.Candidate__c).add(cl);
        }

        ComparisonWrapper cw = new ComparisonWrapper();
        cw.source = new SingleLeadData(
            leadMap.get(ap.Source_Candidate__c), 
            customLeadsByCandidate.containsKey(ap.Source_Candidate__c) ? customLeadsByCandidate.get(ap.Source_Candidate__c) : new List<Lead__c>()
        );
        cw.target = new SingleLeadData(
            leadMap.get(ap.Target_Candidate__c), 
            customLeadsByCandidate.containsKey(ap.Target_Candidate__c) ? customLeadsByCandidate.get(ap.Target_Candidate__c) : new List<Lead__c>()
        );
        return cw;
    }

    public class ComparisonWrapper {
        @AuraEnabled public SingleLeadData source;
        @AuraEnabled public SingleLeadData target;
    }

    public class SingleLeadData {
        @AuraEnabled public Lead standardLead;
        @AuraEnabled public List<Lead__c> customLeads;

        public SingleLeadData(Lead std, List<Lead__c> cstList) {
            this.standardLead = std;
            this.customLeads = cstList;
        }
    }

    private static Id determineApprover(Lead mainLead, Lead sourceLead, Map<Id, User> userMap) {
        Id adminId = '005C1000005Qn8fIAC';

        Set<Id> managerIds = new Set<Id>();
        User mOwner = userMap.get(mainLead.OwnerId);
        User sOwner = userMap.get(sourceLead.OwnerId);

        if (mOwner != null && mOwner.ManagerId != null) managerIds.add(mOwner.ManagerId);
        else managerIds.add(null);
        
        if (sOwner != null && sOwner.ManagerId != null) managerIds.add(sOwner.ManagerId);
        else managerIds.add(null);

        if (managerIds.size() == 1 && !managerIds.contains(null)) {
            Id commonManagerId = new List<Id>(managerIds)[0];
            User commonManager = [SELECT ManagerId FROM User WHERE Id = :commonManagerId LIMIT 1];
            if (commonManager.ManagerId != null) return commonManager.ManagerId;
        }

        return adminId;
    }

    @AuraEnabled
    public static void processApprovalResult(Id approvalId, String status, String managerComments) {
        if (String.isBlank(managerComments)) {
            throw new AuraHandledException('Comments are mandatory for finalizing the approval.');
        }

        Approval_Process__c ap = [SELECT Id, Source_Candidate__c, Target_Candidate__c, Merge_Status__c, Comments__c, Approval_Comments__c, Requestor__c FROM Approval_Process__c WHERE Id = :approvalId];
        ap.Merge_Status__c = status; 
        ap.Approval_Comments__c = managerComments;
        update ap;

        if (status == 'Approved' && ap.Source_Candidate__c != null && ap.Target_Candidate__c != null) {
            Lead source = new Lead(
                Id = ap.Source_Candidate__c,
                Candidate__c = ap.Target_Candidate__c,
                Is_Merged__c = true
            );
            update source;

            Lead target = new Lead(
                Id = ap.Target_Candidate__c,
                Merge_Comments__c = managerComments
            );
            update target;
        }

        // Notify Requestor
        String templateName = (status == 'Approved') ? 'Lead_Merge_Approved' : 'Lead_Merge_Rejected';
        sendNotifications(ap.Id, ap.Requestor__c, templateName);
    }

    private static void sendNotifications(Id processId, Id targetUserId, String templateDeveloperName) {
        if (targetUserId == null || processId == null) return;
        
        try {
            // Get recipient details and record details to find a dummy "Who" (Lead) to bypass Salesforce restriction.
            // Salesforce does not allow WhatId when TargetObjectId is a User.
            User recipient = [SELECT Email FROM User WHERE Id = :targetUserId LIMIT 1];
            Approval_Process__c ap = [SELECT Source_Candidate__c, Target_Candidate__c FROM Approval_Process__c WHERE Id = :processId LIMIT 1];
            
            // 1. Send Email
            List<EmailTemplate> templates = [SELECT Id FROM EmailTemplate WHERE DeveloperName = :templateDeveloperName LIMIT 1];
            if (!templates.isEmpty()) {
                Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
                mail.setTemplateId(templates[0].Id);
                
                // CRITICAL WORKAROUND: To use merge fields (!Approval_Process__c.X) when sending to a User,
                // we must use a Lead/Contact/Account as TargetObjectId and redirect to the User email.
                Id dummyWhoId = (ap.Source_Candidate__c != null) ? ap.Source_Candidate__c : ap.Target_Candidate__c;
                
                mail.setTargetObjectId(dummyWhoId); 
                mail.setWhatId(processId);
                mail.setTreatTargetObjectAsRecipient(false); // DO NOT send to the lead email
                mail.setToAddresses(new String[] { recipient.Email }); // Send to the actual user
                mail.setSaveAsActivity(false);
                
                Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });
            }

            // 2. Send Custom Notification (Push)
            List<CustomNotificationType> types = [SELECT Id FROM CustomNotificationType WHERE DeveloperName = 'Lead_Merge_Status_Notification' LIMIT 1];
            if (!types.isEmpty()) {
                Messaging.CustomNotification notification = new Messaging.CustomNotification();
                notification.setNotificationTypeId(types[0].Id);
                notification.setTargetId(processId);
                
                String title = 'Lead Merge Update';
                String body = 'A lead merge request has been updated.';
                
                if (templateDeveloperName == 'Lead_Merge_Approval_Request') {
                    title = 'Merge Request Pending';
                    body = recipient.Email + ', a new lead merge request requires your approval.';
                } else if (templateDeveloperName == 'Lead_Merge_Approved') {
                    title = 'Merge Request Approved';
                    body = 'Your lead merge request has been approved and finalized.';
                } else if (templateDeveloperName == 'Lead_Merge_Rejected') {
                    title = 'Merge Request Rejected';
                    body = 'Your lead merge request has been rejected.';
                }
                
                notification.setTitle(title);
                notification.setBody(body);
                notification.send(new Set<String>{String.valueOf(targetUserId)});
            }
        } catch (Exception e) {
            // Log for visibility but only throw if it's a critical configuration error
            System.debug('Notification Logic failed: ' + e.getMessage());
            if (e.getMessage().contains('INVALID_ID_FIELD')) {
                throw new AuraHandledException('Email Configuration Error: ' + e.getMessage());
            }
        }
    }
}