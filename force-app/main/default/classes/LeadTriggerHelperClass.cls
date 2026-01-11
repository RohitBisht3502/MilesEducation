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
            SELECT Id, Stage__c, Lead__c
            FROM Lead__c
            WHERE Lead__c IN :approvedLeadIds
        ];
        
        if (relatedLeads.isEmpty()) return;
        
        // 3️⃣ Create a map of main lead Id to its related leads
        Map<Id, List<Lead__c>> mainLeadToRelatedLeadsMap = new Map<Id, List<Lead__c>>();
        Set<Id> allRelatedLeadIds = new Set<Id>();
        
        for (Lead__c relatedLead : relatedLeads) {
            allRelatedLeadIds.add(relatedLead.Id);
            
            if (!mainLeadToRelatedLeadsMap.containsKey(relatedLead.Lead__c)) {
                mainLeadToRelatedLeadsMap.put(relatedLead.Lead__c, new List<Lead__c>());
            }
            mainLeadToRelatedLeadsMap.get(relatedLead.Lead__c).add(relatedLead);
        }
        
        // 4️⃣ Query main leads with their current stage
        Map<Id, Lead__c> mainLeadsMap = new Map<Id, Lead__c>(
            [SELECT Id, Stage__c
            FROM Lead__c
            WHERE Id IN :approvedLeadIds]
        );
        
        // 5️⃣ Stage ranking configuration
        Map<String, Integer> stageRankMap = new Map<String, Integer>{
            'M1' => 1, 'M2' => 2, 'M3' => 3, 'M3+' => 4, 'M3++' => 5,
            'M4-' => 6, 'M4' => 7, 'M5' => 8, 'M6' => 9, 'M7' => 10
        };
        
        // 6️⃣ Update stages for main leads (pick highest stage from all related leads)
        List<Lead__c> mainLeadsToUpdate = new List<Lead__c>();
        List<Lead__c> relatedLeadsToUpdate = new List<Lead__c>();
        
        for (Id mainLeadId : mainLeadToRelatedLeadsMap.keySet()) {
            Lead__c mainLead = mainLeadsMap.get(mainLeadId);
            if (mainLead != null) {
                String highestStage = mainLead.Stage__c;
                
                // Compare with all related leads to find highest stage
                for (Lead__c relatedLead : mainLeadToRelatedLeadsMap.get(mainLeadId)) {
                    highestStage = getHigherStage(highestStage, relatedLead.Stage__c, stageRankMap);
                    
                    // Mark related lead as merged
                    relatedLead.Is_Merged__c = true;
                    relatedLeadsToUpdate.add(relatedLead);
                }
                
                // Update stage only if it changed
                if (highestStage != mainLead.Stage__c) {
                    mainLead.Stage__c = highestStage;
                    mainLeadsToUpdate.add(mainLead);
                }
            }
        }
        
        // 7️⃣ Query and reparent all child records in bulk
        List<SObject> childRecordsToUpdate = new List<SObject>();
        
        // Reparent Enquiries
        childRecordsToUpdate.addAll(reparentChildRecords(
            [SELECT Id, Lead__c FROM Enquiry__c WHERE Lead__c IN :allRelatedLeadIds],
            'Lead__c',
            relatedLeads
        ));
        
        // Reparent Phone Numbers
        childRecordsToUpdate.addAll(reparentChildRecords(
            [SELECT Id, Lead__c FROM Phone_Number__c WHERE Lead__c IN :allRelatedLeadIds],
            'Lead__c',
            relatedLeads
        ));
        
        // Reparent Call Logs
        childRecordsToUpdate.addAll(reparentChildRecords(
            [SELECT Id, Lead__c FROM Call_Log__c WHERE Lead__c IN :allRelatedLeadIds],
            'Lead__c',
            relatedLeads
        ));
        
        // Reparent Webinar Members
        childRecordsToUpdate.addAll(reparentChildRecords(
            [SELECT Id, Lead__c FROM Webinar_Member__c WHERE Lead__c IN :allRelatedLeadIds],
            'Lead__c',
            relatedLeads
        ));
        
        // Reparent Activity Logs
        childRecordsToUpdate.addAll(reparentChildRecords(
            [SELECT Id, Lead__c FROM Activity_Log__c WHERE Lead__c IN :allRelatedLeadIds],
            'Lead__c',
            relatedLeads
        ));
        
        // Reparent Eligibility Folders
        childRecordsToUpdate.addAll(reparentChildRecords(
            [SELECT Id, Lead__c FROM Eligibility_Folder__c WHERE Lead__c IN :allRelatedLeadIds],
            'Lead__c',
            relatedLeads
        ));
        
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
    


}