/*
    Author             : Dheeraj Kumar
    Created Date       : 07-01-2026
    Last Modified Date : 07-01-2026
    Description        : Service class to sync Lead owner changes to related records.
*/
public without sharing class LeadRelatedSyncService {
    
    public static void syncOnOwnerChange(Map<Id, Lead__c> oldMap, Map<Id, Lead__c> newMap) {

        Set<Id> leadIdsToSync = new Set<Id>();


        for (Id lid : newMap.keySet()) {
            Lead__c oldRec = oldMap.get(lid);
            Lead__c newRec = newMap.get(lid);

            // Sync when Owner changes 
            if (oldRec.OwnerId != newRec.OwnerId) {
                if (newRec.OwnerId != null) leadIdsToSync.add(lid);
            }


        }

        if (leadIdsToSync.isEmpty()) return;

        // No cutoff needed for owner sync - we want to sync ALL related records regardless of age
        // Datetime cutoff = System.now().addMinutes(-1); 

        // Fetch required Leads
        List<Lead__c> leads = [SELECT Id, Name, OwnerId, Phone__c, Email__c, Candidate__c FROM Lead__c WHERE Id IN :leadIdsToSync];


        Map<Id, Id> leadIdToOwner = new Map<Id, Id>();
        Map<Id, Id> leadIdToCandidate = new Map<Id, Id>();
        Map<Id, Set<Id>> candidateIdToLeadIds = new Map<Id, Set<Id>>();

        Set<String> phones = new Set<String>();
        Set<String> emails = new Set<String>();

        for (Lead__c l : leads) {
            leadIdToOwner.put(l.Id, l.OwnerId);
            leadIdToCandidate.put(l.Id, l.Candidate__c);

            if (l.Candidate__c != null) {
                if (!candidateIdToLeadIds.containsKey(l.Candidate__c)) {
                    candidateIdToLeadIds.put(l.Candidate__c, new Set<Id>());
                }
                candidateIdToLeadIds.get(l.Candidate__c).add(l.Id);
            }
                        
            if (!String.isBlank(l.Phone__c)) phones.add(l.Phone__c);
            if (!String.isBlank(l.Email__c)) emails.add(l.Email__c);
        }

        List<SObject> upd = new List<SObject>();

        // 1. Candidate Owner Sync
        List<Lead> candidates = [SELECT Id, OwnerId, CreatedDate, LastModifiedDate FROM Lead WHERE Id IN :leadIdToCandidate.values()];
        for (Lead c : candidates) {
            // Updated: Removed cutoff check. 
            // We iterate over leads mapping to this candidate to find if any need an update.
            
            for (Id leadId : leadIdToCandidate.keySet()) {
                if (leadIdToCandidate.get(leadId) == c.Id && c.OwnerId != leadIdToOwner.get(leadId)) {
                    c.OwnerId = leadIdToOwner.get(leadId);
                    upd.add(c);
                    // Avoid adding same candidate multiple times if mapped to multiple leads in same batch (rare but possible)
                    break; 
                }
            }
        }

        // 2. Enquiry Owner Sync
        List<Enquiry__c> enqs = [SELECT Id, OwnerId, Lead__c, CreatedDate, LastModifiedDate FROM Enquiry__c WHERE Lead__c IN :leadIdsToSync];
        for (Enquiry__c e : enqs) {
            // Updated: Removed cutoff check. 
            
            Id target = leadIdToOwner.get(e.Lead__c);
            if (target != null && e.OwnerId != target) {
                e.OwnerId = target;
                upd.add(e);
            }
        }

        // 3. Phone Number Owner Sync
        if (!phones.isEmpty()) {
            List<Phone_Number__c> phs = [
                SELECT Id, OwnerId, Lead__c, Phone__c, CreatedDate, LastModifiedDate FROM Phone_Number__c WHERE Lead__c IN :leadIdsToSync OR Phone__c IN :phones];
            for (Phone_Number__c p : phs) {
                // Updated: Removed cutoff check.

                Id target = (p.Lead__c != null) ? leadIdToOwner.get(p.Lead__c) : null;
                if (target != null && p.OwnerId != target) {
                    p.OwnerId = target;
                    upd.add(p);
                }
            }
        }

        // 4. Email Owner Sync
        if (!emails.isEmpty()) {
            List<Email__c> ems = [
                SELECT Id, OwnerId, Lead__c, Email__c, CreatedDate, LastModifiedDate FROM Email__c WHERE Lead__c IN :leadIdsToSync OR Email__c IN :emails];
            for (Email__c em : ems) {
                // Updated: Removed cutoff check.

                Id target = (em.Lead__c != null) ? leadIdToOwner.get(em.Lead__c) : null;
                if (target != null && em.OwnerId != target) {
                    em.OwnerId = target;
                    upd.add(em);
                }
            }
        }

        // 5. Activity Log Owner Sync
        Set<Id> candidateIds = new Set<Id>();
        candidateIds.addAll(candidateIdToLeadIds.keySet());

        if (!candidateIds.isEmpty() || !leadIdsToSync.isEmpty()) {

            List<Activity_Log__c> logs = [
                SELECT Id, OwnerId, Lead__c, Candidate__c, CreatedDate, LastModifiedDate
                FROM Activity_Log__c
                WHERE (Lead__c IN :leadIdsToSync)
                OR (Candidate__c IN :candidateIds)
            ];

            for (Activity_Log__c al : logs) {

                // Identify which Lead owner should be used
                Id mappedLeadId;

                if (al.Lead__c != null) {
                    mappedLeadId = al.Lead__c;
                } else if (al.Candidate__c != null && candidateIdToLeadIds.containsKey(al.Candidate__c)) {
                    mappedLeadId = candidateIdToLeadIds.get(al.Candidate__c).isEmpty()
                        ? null
                        : (Id)candidateIdToLeadIds.get(al.Candidate__c).iterator().next();
                }

                if (mappedLeadId == null) continue;

                // Updated: Removed cutoff check.
                
                Id targetOwner = leadIdToOwner.get(mappedLeadId);
                if (targetOwner != null && al.OwnerId != targetOwner) {
                    al.OwnerId = targetOwner;
                    upd.add(al);
                }
            }
        }

        // Update all owner sync changes
        if (!upd.isEmpty()) {
            // De-duplicate list to avoid "Duplicate id in list" error
            Map<Id, SObject> updMap = new Map<Id, SObject>();
            for(SObject s : upd) {
                updMap.put(s.Id, s);
            }
            update updMap.values();
        }

        // ---------------------------
        // NEW: Create Task on Enquiry
        // ---------------------------
        // NOTE: Keeping restriction for Task creation to recent records likely makes sense, 
        // to avoid spamming tasks on old enquiries if a massive data fix happens. 
        // However, if the user wants strictly NO cutoff, we can remove it. 
        // Given the requirement is about "seeing records" (ownership sync), I will relax the task creation logic too?
        // Actually, creating tasks for year-old enquiries just because owner changed might be annoying.
        // But the original code had: if (!(e.CreatedDate >= cutoff || e.LastModifiedDate >= cutoff)) continue;
        // I will KEEP the cutoff for TASK CREATION unless instructed otherwise, as that is an "Action", not a "Sync".
        
        Datetime cutoff = System.now().addMinutes(-1); 

        Map<Id, Id> enquiryIdToTargetOwner = new Map<Id, Id>();
        Set<Id> enquiryIdsNeedingTask = new Set<Id>();

        for (Enquiry__c e : enqs) {
            // Apply cutoff specifically for the Task Creation part, assuming we only want this for 'fresh' interactions
            if (!(e.CreatedDate >= cutoff || e.LastModifiedDate >= cutoff)) continue; 

            Id target = leadIdToOwner.get(e.Lead__c);
            if (target != null) {
                enquiryIdToTargetOwner.put(e.Id, target);
                enquiryIdsNeedingTask.add(e.Id);
            }
        }


        // Create tasks
        if (!enquiryIdsNeedingTask.isEmpty()) {
            List<Task> tasksToInsert = new List<Task>();

            for (Id enqId : enquiryIdsNeedingTask) {
                Id ownerId = enquiryIdToTargetOwner.get(enqId);
                if (ownerId == null) continue;

                tasksToInsert.add(new Task(
                    WhatId      = enqId,
                    OwnerId     = ownerId,
                    Subject     = 'Follow Up Call',
                    Priority    = 'Normal',
                    Status      = 'Open',
                    Type        = 'Task Assigned To',
                    Description = 'Auto-created task for SPOC follow-up via Miles API.'
                ));
            }

            if (!tasksToInsert.isEmpty()) {
                insert tasksToInsert;
                MilesExistingEnquiryWebService.sendTaskAssignedNotificationBulk( tasksToInsert, 'Custom_Notification' );
            }
        }

        // ---------------------------
        // Notify Lead Owners (Loss/Gain)
        // ---------------------------
        MilesExistingEnquiryWebService.sendLeadOwnerChangeNotifications(leads, oldMap, 'Custom_Notification');

    }
}