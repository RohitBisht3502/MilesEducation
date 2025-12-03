public without sharing class LeadTriggerHandler {

    /**
     * Creates activity logs for Stage changes (Level Change)
     */
    public static void createLeadActivityLogs(
        List<Lead__c> newList,
        Map<Id, Lead__c> oldMap,
        Boolean isInsert
    ) {
        List<Activity_Log__c> logsToInsert = new List<Activity_Log__c>();

        for (Lead__c ld : newList) {

            // On update, only log when Stage__c actually changes
            if (!isInsert && oldMap != null) {
                Lead__c oldRec = oldMap.get(ld.Id);
                if (oldRec == null) {
                    continue;
                }
                if (oldRec.Stage__c == ld.Stage__c) {
                    // Stage not changed → skip creating log
                    continue;
                }
            }

            Activity_Log__c log = new Activity_Log__c();

            // Common fields
            log.Lead__c          = ld.Id;
            log.Logging_Id__c    = ld.Id;
            log.Activity_Type__c = 'Level Change';
            log.Created_By__c    = ld.OwnerId;

            // Previous / New Levels
            if (isInsert) {
                log.Previous_Level__c = null;
                log.New_Level__c      = ld.Stage__c;
            } else {
                Lead__c oldRec = oldMap.get(ld.Id);
                log.Previous_Level__c = oldRec != null ? oldRec.Stage__c : null;
                log.New_Level__c      = ld.Stage__c;
            }

            // Name, Changed_Date_Time__c, Action_Performed_By__c, Description
            if (isInsert) {
                log.Name                   = 'Created Lead Log';
                log.Changed_Date_Time__c   = ld.CreatedDate;
                log.Action_Performed_By__c = ld.CreatedById;
                log.Description__c         = 'Lead created';
            } else {
                log.Name                   = 'Updated Lead Log';
                log.Changed_Date_Time__c   = ld.LastModifiedDate;
                log.Action_Performed_By__c = ld.LastModifiedById;
                log.Description__c         = 'Stage is updated';
            }

            logsToInsert.add(log);
        }

        if (!logsToInsert.isEmpty()) {
            insert logsToInsert;
        }
    }

    /**
     * Creates activity logs for Merged Leads
     * Call this AFTER the merge logic completes
     */
    public static void createMergeLeadActivityLogs(
        List<Lead__c> newList,
        Map<Id, Lead__c> oldMap
    ) {
        List<Activity_Log__c> logsToInsert = new List<Activity_Log__c>();
        
        // Track which leads were just merged
        Set<Id> newlyMergedLeadIds = new Set<Id>();
        
        for (Lead__c ld : newList) {
            Lead__c oldLd = oldMap.get(ld.Id);
            
            // Check if this lead was just marked as merged
            if (oldLd != null && !oldLd.Is_Merged__c && ld.Is_Merged__c) {
                newlyMergedLeadIds.add(ld.Id);
            }
        }
        
        if (newlyMergedLeadIds.isEmpty()) {
            return;
        }
        
        // Query related leads to get merge details
        List<Lead__c> relatedLeads = [
            SELECT Id, Name, Lead__c, Stage__c
            FROM Lead__c
            WHERE Lead__c IN :newlyMergedLeadIds
        ];
        
        // Create a map: Main Lead Id → List of merged lead names
        Map<Id, List<String>> mainLeadToMergedNamesMap = new Map<Id, List<String>>();
        
        for (Lead__c relatedLead : relatedLeads) {
            if (!mainLeadToMergedNamesMap.containsKey(relatedLead.Lead__c)) {
                mainLeadToMergedNamesMap.put(relatedLead.Lead__c, new List<String>());
            }
            mainLeadToMergedNamesMap.get(relatedLead.Lead__c).add(relatedLead.Name);
        }
        
        // Create activity logs for each merged lead
        for (Id mainLeadId : newlyMergedLeadIds) {
            Lead__c mainLead = newList[0]; // Get from newList
            for (Lead__c ld : newList) {
                if (ld.Id == mainLeadId) {
                    mainLead = ld;
                    break;
                }
            }
            
            List<String> mergedLeadNames = mainLeadToMergedNamesMap.get(mainLeadId);
            if (mergedLeadNames == null || mergedLeadNames.isEmpty()) {
                continue;
            }
            
            Activity_Log__c log = new Activity_Log__c();
            log.Lead__c                = mainLeadId;
            log.Logging_Id__c          = mainLeadId;
            log.Activity_Type__c       = 'Lead Merge';
            log.Name                   = 'Lead Merged';
            log.Changed_Date_Time__c   = System.now();
            log.Action_Performed_By__c = mainLead.LastModifiedById;
            log.Created_By__c          = mainLead.LastModifiedById;
            
            // Build description with merged lead names
            String mergedNames = String.join(mergedLeadNames, ', ');
            Integer mergeCount = mergedLeadNames.size();
            log.Description__c = mergeCount + ' lead(s) merged into this lead: ' + mergedNames;
            
            logsToInsert.add(log);
        }
        
        if (!logsToInsert.isEmpty()) {
            insert logsToInsert;
        }
    }
}