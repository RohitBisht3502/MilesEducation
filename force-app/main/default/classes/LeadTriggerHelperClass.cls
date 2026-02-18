/*
    Author       : ROHIT SINGH BISHT
    Description  : 
*/
public without sharing class LeadTriggerHelperClass {

    public static void updateLevelSequence(List<Lead__c> newLeads, Map<Id, Lead__c> oldMap) {
        // Fetch all "M Stage Sequence" metadata records
        // Note: Custom Metadata SOQL does not count towards governor limits
        Map<String, Decimal> stageToSequenceMap = new Map<String, Decimal>();
        for (M_Stage_Sequence__mdt mdt : [SELECT Label, Level_Sequence__c FROM M_Stage_Sequence__mdt]) {
            if (mdt.Label != null) {
                stageToSequenceMap.put(mdt.Label, mdt.Level_Sequence__c);
            }
        }

        for (Lead__c lead : newLeads) {
            String currentStage = lead.Stage__c;
            String oldStage = (oldMap != null && oldMap.containsKey(lead.Id)) ? oldMap.get(lead.Id).Stage__c : null;

            // Trigger logic: Insert (oldMap is null) or Update (stage changed)
            if (oldMap == null || currentStage != oldStage) {
                if (currentStage != null && stageToSequenceMap.containsKey(currentStage)) {
                    lead.Level_Sequence__c = stageToSequenceMap.get(currentStage);
                } else {
                    // If stage doesn't match any metadata or is null, consider clearing the sequence
                    // lead.Level_Sequence__c = null; // Uncomment if you want to clear the sequence
                }
            }
        }
    }
    
    public static void handleBeforeInsert(List<Lead__c> newLeads) { 
        BucketAssignmentService.assignBucket((List<SObject>)newLeads, null);
        TriggerRoundRobinService.handleBeforeInsert(newLeads);
    }
    
    public static void handleBeforeUpdate(List<Lead__c> newLeads, Map<Id, Lead__c> oldMap) {
        BucketAssignmentService.assignBucket((List<SObject>)newLeads,(Map<Id, SObject>)oldMap); 
        TriggerRoundRobinService.handleBeforeUpdate(newLeads, oldMap);   
    }
    
    public static void handleAfterInsert1(List<Lead__c> newLeads) {
        if (newLeads == null || newLeads.isEmpty()) return;
        System.debug('Inside handleAfterInsert line 13 ');
        Set<Id> newLeadIds = new Set<Id>();
        for (Lead__c ld : newLeads) {
            if (ld.Id != null) newLeadIds.add(ld.Id);
        }
        if (!newLeadIds.isEmpty()) {
          //  LeadCityClassifier.enqueueLeadCityUpdate(newLeadIds);
        }

        Set<Id> leadsForZoom = new Set<Id>();
        for (Lead__c ld : newLeads) {
            System.debug('Inside ld line 13 '+ld);
            Boolean emailOk   = String.isNotBlank(ld.Email__c);
            Boolean wantsWeb  = (ld.Register_For_Webinar__c == true);
            Boolean noWebinar = String.isNotBlank(ld.Interested_Webinar_Id__c);
            System.debug('>>>> '+emailOk);
            System.debug('>>>> '+wantsWeb);
            System.debug('>>>> '+noWebinar);
           if (emailOk && wantsWeb && noWebinar) {
                leadsForZoom.add(ld.Id);
            }
        }
        if (!leadsForZoom.isEmpty()) {
            System.debug('Inside handleAfterInsert queue ');
            System.enqueueJob(new LeadZoomRegistrationJob(leadsForZoom));
        }
    }
public static void validateCallLogBeforeStageChange(
    List<Lead__c> newLeads,
    Map<Id, Lead__c> oldMapLead
) {

    Set<Id> leadIdsToCheck = new Set<Id>();

    // Detect stage change
    for (Lead__c newLead : newLeads) {
        Lead__c oldLead = oldMapLead.get(newLead.Id);

        if (oldLead != null && newLead.Stage__c != oldLead.Stage__c) {
            leadIdsToCheck.add(newLead.Id);
        }
    }

    if (leadIdsToCheck.isEmpty()) return;

    //  CHECK CUSTOM CALL LOG OBJECT
    Map<Id, Integer> callCountMap = new Map<Id, Integer>();

    for (AggregateResult ar : [
        SELECT Lead__c leadId, COUNT(Id) total
        FROM Call_Log__c
        WHERE Lead__c IN :leadIdsToCheck
        GROUP BY Lead__c
    ]) {
        callCountMap.put(
            (Id) ar.get('leadId'),
            (Integer) ar.get('total')
        );
    }

    // BLOCK STAGE CHANGE IF NO CALL LOG EXISTS
    for (Lead__c newLead : newLeads) {
        if (!leadIdsToCheck.contains(newLead.Id)) continue;

        Integer callCount = callCountMap.get(newLead.Id);

        if (callCount == null || callCount == 0) {
            newLead.addError(
                'You must log at least one Call before changing the Lead Stage.'
            );
        }
    }
}















    public static void afterInsertAutoRegisterWebinar(List<Lead__c> newList) {
        if (newList == null || newList.isEmpty()) return;

        Set<Id> leadIds = new Set<Id>();
        for (Lead__c l : newList) if (l != null && l.Id != null) leadIds.add(l.Id);

        WebinarAutoRegisterDispatcher.dispatchForLeads(leadIds);
    }

    public static void afterUpdateAutoRegisterWebinar(Map<Id, Lead__c> newMap, Map<Id, Lead__c> oldMap) {
        if (newMap == null || newMap.isEmpty() || oldMap == null) return;

        Set<Id> leadIdsToAutoRegister = new Set<Id>();

        for (Id lid : newMap.keySet()) {
            Lead__c n = newMap.get(lid);
            Lead__c o = oldMap.get(lid);
            if (n == null || o == null) continue;

            if (o.Is_ReEnquiry__c != n.Is_ReEnquiry__c && n.Is_ReEnquiry__c == true) {
                leadIdsToAutoRegister.add(lid);
            }
        }

        WebinarAutoRegisterDispatcher.dispatchForLeads(leadIdsToAutoRegister);
    }

    
    
    private static final Id M1_OWNER_ID = '005C1000005HJRZIA4';

    public static void handleAfterInsert(List<Lead__c> newLeads) {
        if (newLeads == null || newLeads.isEmpty()) return;
        System.debug('Inside handleAfterInsert line 13 ');
        Set<Id> newLeadIds = new Set<Id>();
        for (Lead__c ld : newLeads) {
            if (ld.Id != null) newLeadIds.add(ld.Id);
        }
        if (!newLeadIds.isEmpty()) {
            LeadCityClassifier.enqueueLeadCityUpdate(newLeadIds);
        }
    }
    
    public static void assignOwnerForM1(List<Lead__c> newList, Map<Id, Lead__c> oldMap, Boolean isInsert) {

        for (Lead__c newLead : newList) {

            // Apply only when Stage__c = 'M1'
            if (newLead.Stage__c == 'M1') {

                // INSERT CASE → always assign owner
                if (isInsert) {
                    newLead.OwnerId = M1_OWNER_ID;
                }

                // UPDATE CASE → only when stage changed to M1
                else {
                    Lead__c oldLead = oldMap.get(newLead.Id);

                    if (oldLead.Stage__c != 'M1') {
                        newLead.OwnerId = M1_OWNER_ID;
                    }
                }
            }
        }
    }


    // Author => Dheeraj Kumar
    // Description => After update merge leads
    public static void afterUpdateMergeLead(List<Lead__c> newList, Map<Id, Lead__c> oldMap) {
    
        // 1️⃣ Identify leads where status changed to 'Approved'
        Set<Id> approvedLeadIds = new Set<Id>();
        Set<Id> rejectedLeadIds = new Set<Id>();
        
        for (Lead__c ld : newList) {
            Lead__c oldLd = oldMap.get(ld.Id);
            if (oldLd != null && oldLd.Status__c != ld.Status__c) {
                if (ld.Status__c == 'Approved') {
                    approvedLeadIds.add(ld.Id);
                } else if (ld.Status__c == 'Rejected') {
                    rejectedLeadIds.add(ld.Id);
                }
            }
        }
        
        // Handle Approved Merges
        if (!approvedLeadIds.isEmpty()) {
            processMergeApproval(approvedLeadIds);
        }
        
        // Handle Rejected Merges
        if (!rejectedLeadIds.isEmpty()) {
            processMergeRejection(rejectedLeadIds);
        }
    }

    /**
     * Process approved merge requests
     */
    private static void processMergeApproval(Set<Id> approvedLeadIds) {
        
        // 2️⃣ Query all related leads that are tagged to the approved leads
        List<Lead__c> relatedLeads = [
            SELECT Id, Stage__c, Lead__c, Course__c, Candidate__c
            FROM Lead__c
            WHERE Lead__c IN :approvedLeadIds
        ];
        
        if (relatedLeads.isEmpty()) return;
        
        // 3️⃣ Create a map of main lead Id to its related leads
        Map<Id, List<Lead__c>> mainLeadToRelatedLeadsMap = new Map<Id, List<Lead__c>>();
        
        for (Lead__c relatedLead : relatedLeads) {
            
            if (!mainLeadToRelatedLeadsMap.containsKey(relatedLead.Lead__c)) {
                mainLeadToRelatedLeadsMap.put(relatedLead.Lead__c, new List<Lead__c>());
            }
            mainLeadToRelatedLeadsMap.get(relatedLead.Lead__c).add(relatedLead);
        }
        
        // 4️⃣ Query main leads with their current stage
        Map<Id, Lead__c> mainLeadsMap = new Map<Id, Lead__c>(
            [SELECT Id, Stage__c, Course__c, Candidate__c
            FROM Lead__c
            WHERE Id IN :approvedLeadIds]
        );
        
        // 5️⃣ Stage ranking configuration
        Map<String, Integer> stageRankMap = new Map<String, Integer>{
            'M1' => 1, 'M2' => 2, 'M3' => 3, 'M3+' => 4, 'M3++' => 5,
            'M4-' => 6, 'M4' => 7, 'M5' => 8, 'M6' => 9, 'M7' => 10
        };
        
        // 6️⃣ Processing
        List<Lead__c> mainLeadsToUpdate = new List<Lead__c>();
        List<Lead__c> relatedLeadsToUpdate = new List<Lead__c>();
        
        // Lists for Full Merge (Same Course)
        Set<Id> sameCourseRelatedLeadIds = new Set<Id>();
        List<Lead__c> sameCourseRelatedLeads = new List<Lead__c>();

        for (Id mainLeadId : mainLeadToRelatedLeadsMap.keySet()) {
            Lead__c mainLead = mainLeadsMap.get(mainLeadId);
            if (mainLead != null) {
                String highestStage = mainLead.Stage__c;
                
                for (Lead__c relatedLead : mainLeadToRelatedLeadsMap.get(mainLeadId)) {
                    
                    // Mark as merged (common for both scenarios)
                    relatedLead.Is_Merged__c = true;
                    
                    // SCENARIO 1: SAME COURSE (Original Logic)
                    if (relatedLead.Course__c == mainLead.Course__c) {
                        // Compare stages
                        highestStage = getHigherStage(highestStage, relatedLead.Stage__c, stageRankMap);
                        
                        // Add to lists for Reparenting
                        sameCourseRelatedLeadIds.add(relatedLead.Id);
                        sameCourseRelatedLeads.add(relatedLead);
                    } 
                    // SCENARIO 2: DIFFERENT COURSE
                    else {
                        // Tag related lead to Main Lead's Candidate
                        if (mainLead.Candidate__c != null) {
                            relatedLead.Candidate__c = mainLead.Candidate__c;
                        }
                    }
                    
                    relatedLeadsToUpdate.add(relatedLead);
                }
                
                // Update stage ONLY if logic from Same Course scenario changed it
                if (highestStage != mainLead.Stage__c) {
                    mainLead.Stage__c = highestStage;
                    mainLeadsToUpdate.add(mainLead);
                }
            }
        }
        
        // 7️⃣ Reparent child records ONLY for Same Course leads
        List<SObject> childRecordsToUpdate = new List<SObject>();
        
        if (!sameCourseRelatedLeadIds.isEmpty()) {
            // Reparent Enquiries
            childRecordsToUpdate.addAll(reparentChildRecords(
                [SELECT Id, Lead__c FROM Enquiry__c WHERE Lead__c IN :sameCourseRelatedLeadIds],
                'Lead__c',
                sameCourseRelatedLeads
            ));
            
            // Reparent Phone Numbers
            childRecordsToUpdate.addAll(reparentChildRecords(
                [SELECT Id, Lead__c FROM Phone_Number__c WHERE Lead__c IN :sameCourseRelatedLeadIds],
                'Lead__c',
                sameCourseRelatedLeads
            ));
            
            // Reparent Call Logs
            childRecordsToUpdate.addAll(reparentChildRecords(
                [SELECT Id, Lead__c FROM Call_Log__c WHERE Lead__c IN :sameCourseRelatedLeadIds],
                'Lead__c',
                sameCourseRelatedLeads
            ));
            
            // Reparent Webinar Members
            childRecordsToUpdate.addAll(reparentChildRecords(
                [SELECT Id, Lead__c FROM Webinar_Member__c WHERE Lead__c IN :sameCourseRelatedLeadIds],
                'Lead__c',
                sameCourseRelatedLeads
            ));
            
            // Reparent Activity Logs
            childRecordsToUpdate.addAll(reparentChildRecords(
                [SELECT Id, Lead__c FROM Activity_Log__c WHERE Lead__c IN :sameCourseRelatedLeadIds],
                'Lead__c',
                sameCourseRelatedLeads
            ));
            
            // Reparent Eligibility Folders
            childRecordsToUpdate.addAll(reparentChildRecords(
                [SELECT Id, Lead__c FROM Eligibility_Folder__c WHERE Lead__c IN :sameCourseRelatedLeadIds],
                'Lead__c',
                sameCourseRelatedLeads
            ));
        }
        
        // 8️⃣ Perform DML operations
        if (!mainLeadsToUpdate.isEmpty()) {
            update mainLeadsToUpdate;
        }
        
        if (!relatedLeadsToUpdate.isEmpty()) {
            update relatedLeadsToUpdate;
        }
        
        if (!childRecordsToUpdate.isEmpty()) {
            update childRecordsToUpdate;
        }
    }

    /**
     * Process rejected merge requests - remove related lead references
     */
    private static void processMergeRejection(Set<Id> rejectedLeadIds) {
        
        // Query all related leads that were tagged to the rejected main leads
        List<Lead__c> relatedLeads = [
            SELECT Id, Lead__c
            FROM Lead__c
            WHERE Lead__c IN :rejectedLeadIds
        ];
        
        if (relatedLeads.isEmpty()) return;
        
        // Remove the relationship by setting Lead__c to null
        for (Lead__c relatedLead : relatedLeads) {
            relatedLead.Lead__c = null;
        }
        
        // Update the related leads to remove the relationship
        update relatedLeads;
    }

    /**
     * Reparents child records from related leads to their main leads
     */
    private static List<SObject> reparentChildRecords( List<SObject> childRecords, String parentFieldName, List<Lead__c> relatedLeads ) {
        List<SObject> recordsToUpdate = new List<SObject>();
        
        // Create a map of related lead Id to main lead Id
        Map<Id, Id> relatedToMainLeadMap = new Map<Id, Id>();
        for (Lead__c relatedLead : relatedLeads) {
            relatedToMainLeadMap.put(relatedLead.Id, relatedLead.Lead__c);
        }
        
        for (SObject record : childRecords) {
            Id currentParentId = (Id) record.get(parentFieldName);
            
            // If this child belongs to a related lead, reparent it to the main lead
            if (relatedToMainLeadMap.containsKey(currentParentId)) {
                Id mainLeadId = relatedToMainLeadMap.get(currentParentId);
                record.put(parentFieldName, mainLeadId);
                recordsToUpdate.add(record);
            }
        }
        
        return recordsToUpdate;
    }

    /**
     * Returns the higher stage based on ranking
     */
    private static String getHigherStage(String stage1, String stage2, Map<String, Integer> stageRankMap) {
        if (stage1 == null) return stage2;
        if (stage2 == null) return stage1;
        
        Integer rank1 = stageRankMap.get(stage1);
        Integer rank2 = stageRankMap.get(stage2);
        
        if (rank1 == null) return stage2;
        if (rank2 == null) return stage1;
        
        return rank1 >= rank2 ? stage1 : stage2;
    }

    public static void blockProtectedLeadDeletion(List<Lead__c> oldLeads) {
        for (Lead__c l : oldLeads) {
            if (l.Do_Not_Delete__c == true) {
                l.addError('❌ This custom Lead record is protected and cannot be deleted.');
            }
        }
    }
    
    /*
     * Sync city from Lead to Candidate : Author => Rohit Singh Bisht
    */
    public static void syncParentCityOnChildCityChange(List<Lead__c> newLeads, Map<Id, Lead__c> oldMapLead) {
        if (newLeads == null || newLeads.isEmpty() || oldMapLead == null) return;
    
        Set<Id> parentIds = new Set<Id>();
        Map<Id, String> parentIdToCity = new Map<Id, String>();
    
        for (Lead__c n : newLeads) {
            Lead__c o = oldMapLead.get(n.Id);
            if (o == null) continue;
    
            if (n.Candidate__c != null && n.City__c != o.City__c && !String.isBlank(n.City__c)) {
                parentIds.add(n.Candidate__c);
                parentIdToCity.put(n.Candidate__c, n.City__c);
            }
        }
    
        if (parentIds.isEmpty()) return;
    
        List<Lead> parentsToUpdate = new List<Lead>();
    
        for (Lead p : [SELECT Id, City__c FROM Lead WHERE Id IN :parentIds ]) {
            if (!parentIdToCity.containsKey(p.Id)) continue;
    
            String newCity = parentIdToCity.get(p.Id);
            if (p.City__c != newCity) {
                p.City__c = newCity;
                parentsToUpdate.add(p);
            }
        }
    
        if (!parentsToUpdate.isEmpty()) {
            update parentsToUpdate;
        }

        
    }
    
    /*
     * Update Candidate Highest engagment M bucket : Author => Rohit Singh Bisht
    */
    public static void updateHighestLevelOnCandidateWhenStageChanges(List<Lead__c> newLeads, Map<Id, Lead__c> oldMapLead) {
        System.debug('updateHighestLevelOnCandidateWhenStageChanges => start');

        if (newLeads == null || newLeads.isEmpty()) {
            System.debug('updateHighestLevelOnCandidateWhenStageChanges => newLeads empty, exit');
            return;
        }
        if (oldMapLead == null || oldMapLead.isEmpty()) {
            System.debug('updateHighestLevelOnCandidateWhenStageChanges => oldMapLead empty, exit');
            return;
        }

        Set<Id> candidateIds = new Set<Id>();

        for (Lead__c n : newLeads) {
            Lead__c o = oldMapLead.get(n.Id);
            if (o == null) continue;

            if (n.Candidate__c != null && n.Stage__c != o.Stage__c) {
                candidateIds.add(n.Candidate__c);
            }

            if (o.Candidate__c != null && n.Candidate__c != o.Candidate__c) {
                candidateIds.add(o.Candidate__c);
            }
        }

        System.debug('updateHighestLevelOnCandidateWhenStageChanges => candidateIds size: ' + candidateIds.size() + ' ids: ' + candidateIds);

        if (!candidateIds.isEmpty()) {
            System.debug('updateHighestLevelOnCandidateWhenStageChanges => calling CandidateHighestLevelUpdater');
            CandidateHighestLevelUpdater.updationOfHighestLevelOnCandidate(candidateIds);
        } else {
            System.debug('updateHighestLevelOnCandidateWhenStageChanges => no candidateIds to process');
        }

        System.debug('updateHighestLevelOnCandidateWhenStageChanges => end');
    }
    

    // Author: Dheeraj Kumar
    // Description: Automate Task creation for M.Com Bridge Course
    public static void createMComTasks(List<Lead__c> newLeads, Map<Id, Lead__c> oldMap) {
        List<Task> tasksToInsert = new List<Task>();
        
        for (Lead__c lead : newLeads) {
            // Ensure logic only applies to MCOM course
            if (lead.Course__c != 'MCOM') continue;

            String oldStage = (oldMap != null) ? oldMap.get(lead.Id).Stage__c : null;
            
            // 1. Initial Contact (Creation at B3 or Update to B3)
            if (lead.Stage__c == 'B3' && (oldMap == null || oldStage != 'B3')) {
                Task t = new Task();
                t.Subject = 'Initial Contact: Bridge Course';
                t.WhatId = lead.Id; 
                t.OwnerId = lead.OwnerId;
                t.ActivityDate = System.today().addDays(1);
                t.Priority = 'High';
                t.Status = 'Open';
                tasksToInsert.add(t);
            }
            
            // 2. Post-Enrollment (Change to B7 Enrolled)
            if (lead.Stage__c == 'B7' && oldStage != 'B7') {
                // 3 Days
                tasksToInsert.add(createTask(lead, 'M.Com Post-Enrollment: 3 Days Follow-up', 3));
                // 7 Days
                tasksToInsert.add(createTask(lead, 'M.Com Post-Enrollment: 7 Days Follow-up', 7));
                // 30, 60, 90 Days
                tasksToInsert.add(createTask(lead, 'M.Com Monthly Call: 30 Days', 30));
                tasksToInsert.add(createTask(lead, 'M.Com Monthly Call: 60 Days', 60));
                tasksToInsert.add(createTask(lead, 'M.Com Monthly Call: 90 Days', 90));
            }
        }
        
        if(!tasksToInsert.isEmpty()) {
            try {
                insert tasksToInsert;
            } catch (Exception e) {
                System.debug('Error creating M.Com Tasks: ' + e.getMessage());
            }
        }
    }

    private static Task createTask(Lead__c lead, String subject, Integer daysOffset) {
        Task t = new Task();
        t.Subject = subject;
        t.WhatId = lead.Id;
        t.OwnerId = lead.OwnerId;
        t.ActivityDate = System.today().addDays(daysOffset);
        t.Status = 'Open';
        t.Priority = 'Normal';
        return t;
    }


    //Author => Dheeraj Kumar
    //Description => Validate approval comments for leads   
    public static void validateApprovalComments(List<Lead__c> newLeads, Map<Id, Lead__c> oldMap) {
        Set<Id> leadsToCheck = new Set<Id>();

        for (Lead__c lead : newLeads) {
            Lead__c oldLead = oldMap.get(lead.Id);
            // Check for Rejection
            if (lead.Status__c == 'Rejected' && oldLead.Status__c != 'Rejected') { 
                leadsToCheck.add(lead.Id);
            }
        }

        if (leadsToCheck.isEmpty()) return;

        Map<Id, String> leadToCommentMap = new Map<Id, String>();
        
        // Query the latest ProcessInstanceStep for these leads
        List<ProcessInstanceStep> steps = [
            SELECT ProcessInstance.TargetObjectId, Comments 
            FROM ProcessInstanceStep 
            WHERE ProcessInstance.TargetObjectId IN :leadsToCheck 
            ORDER BY SystemModstamp DESC 
            LIMIT 100
        ];

        for (ProcessInstanceStep step : steps) {
            if (!leadToCommentMap.containsKey(step.ProcessInstance.TargetObjectId)) {
                leadToCommentMap.put(step.ProcessInstance.TargetObjectId, step.Comments);
            }
        }

        for (Lead__c lead : newLeads) {
            if (leadsToCheck.contains(lead.Id)) {
                String comments = leadToCommentMap.get(lead.Id);
                if (String.isBlank(comments)) {
                    lead.addError('Comments are mandatory when rejecting a Lead merge request.');
                }
            }
        }
    }
}