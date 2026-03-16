/*
    Author       : ROHIT SINGH BISHT
    Description  : 
*/
public without sharing class LeadSyncOwnerChange {
    
    public static void syncOnOwnerChange(Map<Id, Lead__c> oldMap, Map<Id, Lead__c> newMap) {

        Set<Id> leadIdsToSync = new Set<Id>();
        Set<Id> forceSyncLeadIds = new Set<Id>();

        if (oldMap == null) {
            oldMap = new Map<Id, Lead__c>();
        }

        for (Id lid : newMap.keySet()) {
            Lead__c oldRec = oldMap.get(lid);
            Lead__c newRec = newMap.get(lid);

            if (newRec.OwnerId != null) leadIdsToSync.add(lid);

            if (newRec.Downgraded__c == true && newRec.Is_ReEnquiry__c == true) {
                if (newRec.OwnerId != null) {
                    leadIdsToSync.add(lid); 
                    forceSyncLeadIds.add(lid);
                }
            }            
        }

        if (leadIdsToSync.isEmpty()) return;

        Datetime cutoff = System.now().addMinutes(-1);

        // Fetch required Leads
        List<Lead__c> leads = [SELECT Id, OwnerId, Phone__c, Email__c, Candidate__c FROM Lead__c WHERE Id IN :leadIdsToSync];

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

        // Candidate owner (recent only)
        List<Lead> candidates = [SELECT Id, OwnerId, CreatedDate, LastModifiedDate FROM Lead WHERE Id IN :leadIdToCandidate.values()];
        for (Lead c : candidates) {

            Boolean shouldIgnoreCutoff = false;
            for (Id leadId : leadIdToCandidate.keySet()) {
                if (leadIdToCandidate.get(leadId) == c.Id && forceSyncLeadIds.contains(leadId)) {
                    shouldIgnoreCutoff = true;
                    break;
                }
            }
            if (!shouldIgnoreCutoff && !(c.CreatedDate >= cutoff || c.LastModifiedDate >= cutoff)) continue;


            // find which Lead__c maps to this candidate
            for (Id leadId : leadIdToCandidate.keySet()) {
                if (leadIdToCandidate.get(leadId) == c.Id && c.OwnerId != leadIdToOwner.get(leadId)) {
                    c.OwnerId = leadIdToOwner.get(leadId);
                    upd.add(c);
                }
            }
        }

        // Enquiry owner (recent only)
        List<Enquiry__c> enqs = [SELECT Id, OwnerId, Lead__c, CreatedDate, LastModifiedDate FROM Enquiry__c WHERE Lead__c IN :leadIdsToSync];
        for (Enquiry__c e : enqs) {

            if (!forceSyncLeadIds.contains(e.Lead__c) && !(e.CreatedDate >= cutoff || e.LastModifiedDate >= cutoff)) continue;

            Id target = leadIdToOwner.get(e.Lead__c);
            if (target != null && e.OwnerId != target) {
                e.OwnerId = target;
                upd.add(e);
            }
        }

        if (!phones.isEmpty()) {
            List<Phone_Number__c> phs = [
                SELECT Id, OwnerId, Lead__c, Candidate__c, Phone__c, CreatedDate, LastModifiedDate
                FROM Phone_Number__c
                WHERE Candidate__c IN :candidateIdToLeadIds.keySet() OR Phone__c IN :phones
            ];
            for (Phone_Number__c p : phs) {
                Id mappedLeadId = (p.Candidate__c != null && candidateIdToLeadIds.containsKey(p.Candidate__c))
                    ? (Id)candidateIdToLeadIds.get(p.Candidate__c).iterator().next()
                    : ((p.Lead__c != null) ? p.Lead__c : null);
                Id leadIdForForce = mappedLeadId;
                if (!forceSyncLeadIds.contains(leadIdForForce) && !(p.CreatedDate >= cutoff || p.LastModifiedDate >= cutoff)) continue;

                Id target = (mappedLeadId != null) ? leadIdToOwner.get(mappedLeadId) : null;
                if (target != null && p.OwnerId != target) {
                    p.OwnerId = target;
                    upd.add(p);
                }
            }
        }

        if (!emails.isEmpty()) {
            List<Email__c> ems = [
                SELECT Id, OwnerId, Lead__c, Candidate__c, Email__c, CreatedDate, LastModifiedDate
                FROM Email__c
                WHERE Candidate__c IN :candidateIdToLeadIds.keySet() OR Email__c IN :emails
            ];
            for (Email__c em : ems) {

                Id mappedLeadId = (em.Candidate__c != null && candidateIdToLeadIds.containsKey(em.Candidate__c))
                    ? (Id)candidateIdToLeadIds.get(em.Candidate__c).iterator().next()
                    : ((em.Lead__c != null) ? em.Lead__c : null);
                Id leadIdForForce = mappedLeadId;
                if (!forceSyncLeadIds.contains(leadIdForForce) && !(em.CreatedDate >= cutoff || em.LastModifiedDate >= cutoff)) continue;

                Id target = (mappedLeadId != null) ? leadIdToOwner.get(mappedLeadId) : null;
                if (target != null && em.OwnerId != target) {
                    em.OwnerId = target;
                    upd.add(em);
                }
            }
        }

        // Activity logs for Downgrade Re-inquiry
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
                    // If multiple leads map to same candidate, pick any one from current sync scope
                    mappedLeadId = candidateIdToLeadIds.get(al.Candidate__c).isEmpty()
                        ? null
                        : (Id)candidateIdToLeadIds.get(al.Candidate__c).iterator().next();
                }

                if (mappedLeadId == null) continue;

                // cutoff handling
                if (!forceSyncLeadIds.contains(mappedLeadId) && !(al.CreatedDate >= cutoff || al.LastModifiedDate >= cutoff)) {
                    continue;
                }

                Id targetOwner = leadIdToOwner.get(mappedLeadId);
                if (targetOwner != null && al.OwnerId != targetOwner) {
                    al.OwnerId = targetOwner;
                    upd.add(al);
                }
            }
        }


        // ---------------------------
        // NEW: Create Task on Enquiry
        // ---------------------------
        Map<Id, Id> enquiryIdToTargetOwner = new Map<Id, Id>();
        Set<Id> enquiryIdsNeedingTask = new Set<Id>();

        for (Enquiry__c e : enqs) {
            if (!(e.CreatedDate >= cutoff || e.LastModifiedDate >= cutoff)) continue;

            Id target = leadIdToOwner.get(e.Lead__c);
            if (target != null) {
                enquiryIdToTargetOwner.put(e.Id, target);

                // only when owner mismatch (owner change)
              //  if (e.OwnerId != target) {
                    enquiryIdsNeedingTask.add(e.Id);
               // }
            }
        }

        // Update all owner sync changes
        if (!upd.isEmpty()) update upd;

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
    }
}