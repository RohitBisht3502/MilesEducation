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
     * Creates activity logs for BOTH main lead and merged leads
     * Call this AFTER the merge approval is processed and Is_Merged__c is set
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
        
        // Query merged leads with their main lead reference
        List<Lead__c> mergedLeads = [
            SELECT Id, Name, Lead__c, Stage__c, LastModifiedById
            FROM Lead__c 
            WHERE Id IN :newlyMergedLeadIds
        ];
        
        // Group merged leads by their main lead
        Map<Id, List<Lead__c>> mainLeadToMergedLeadsMap = new Map<Id, List<Lead__c>>();
        Set<Id> mainLeadIds = new Set<Id>();
        
        for (Lead__c mergedLead : mergedLeads) {
            if (mergedLead.Lead__c != null) {
                mainLeadIds.add(mergedLead.Lead__c);
                
                if (!mainLeadToMergedLeadsMap.containsKey(mergedLead.Lead__c)) {
                    mainLeadToMergedLeadsMap.put(mergedLead.Lead__c, new List<Lead__c>());
                }
                mainLeadToMergedLeadsMap.get(mergedLead.Lead__c).add(mergedLead);
            }
        }
        
        // Query main leads to get their details
        Map<Id, Lead__c> mainLeadsMap = new Map<Id, Lead__c>([
            SELECT Id, Name, LastModifiedById
            FROM Lead__c
            WHERE Id IN :mainLeadIds
        ]);
        
        // =============================================================
        // CREATE ACTIVITY LOGS
        // =============================================================
        
        for (Id mainLeadId : mainLeadToMergedLeadsMap.keySet()) {
            List<Lead__c> associatedMergedLeads = mainLeadToMergedLeadsMap.get(mainLeadId);
            Lead__c mainLead = mainLeadsMap.get(mainLeadId);
            
            if (mainLead == null || associatedMergedLeads.isEmpty()) {
                continue;
            }
            
            // Collect merged lead names
            List<String> mergedLeadNames = new List<String>();
            for (Lead__c ml : associatedMergedLeads) {
                mergedLeadNames.add(ml.Name);
            }
            String mergedNamesStr = String.join(mergedLeadNames, ', ');
            Integer mergeCount = mergedLeadNames.size();
            
            // -------------------------------------------------------
            // 1️⃣ ACTIVITY LOG FOR MAIN LEAD (the one being merged INTO)
            // -------------------------------------------------------
            Activity_Log__c mainLeadLog = new Activity_Log__c();
            mainLeadLog.Lead__c                = mainLeadId;
            mainLeadLog.Logging_Id__c          = mainLeadId;
            mainLeadLog.Activity_Type__c       = 'Lead Merge';
            mainLeadLog.Name                   = 'Lead Merge - Main';
            mainLeadLog.Changed_Date_Time__c   = System.now();
            mainLeadLog.Action_Performed_By__c = mainLead.LastModifiedById;
            mainLeadLog.Created_By__c          = mainLead.LastModifiedById;
            mainLeadLog.Description__c         = mergeCount + ' lead(s) merged into this lead: ' + mergedNamesStr;
            
            logsToInsert.add(mainLeadLog);
            
            // -------------------------------------------------------
            // 2️⃣ ACTIVITY LOGS FOR EACH MERGED LEAD (the ones being merged FROM)
            // -------------------------------------------------------
            for (Lead__c mergedLead : associatedMergedLeads) {
                Activity_Log__c mergedLeadLog = new Activity_Log__c();
                mergedLeadLog.Lead__c                = mergedLead.Id;
                mergedLeadLog.Logging_Id__c          = mergedLead.Id;
                mergedLeadLog.Activity_Type__c       = 'Lead Merge';
                mergedLeadLog.Name                   = 'Lead Merge - Merged';
                mergedLeadLog.Changed_Date_Time__c   = System.now();
                mergedLeadLog.Action_Performed_By__c = mergedLead.LastModifiedById;
                mergedLeadLog.Created_By__c          = mergedLead.LastModifiedById;
                mergedLeadLog.Description__c         = 'This lead was merged into: ' + mainLead.Name + ' (ID: ' + mainLeadId + ')';
                
                logsToInsert.add(mergedLeadLog);
            }
        }
        
        if (!logsToInsert.isEmpty()) {
            insert logsToInsert;
        }
    }

    /**
     * Creates activity logs for Owner changes
     */
    public static void createOwnerChangeActivityLogs(List<Lead__c> newList, Map<Id, Lead__c> oldMap) {
        List<Activity_Log__c> logsToInsert = new List<Activity_Log__c>();

        for (Lead__c ld : newList) {
            Lead__c oldRec = oldMap.get(ld.Id);
            // Check if Owner Changed
            if (oldRec != null && oldRec.OwnerId != ld.OwnerId) {
                Activity_Log__c log = new Activity_Log__c();
                log.Lead__c          = ld.Id;
                log.Logging_Id__c    = ld.Id;
                log.Activity_Type__c = 'Owner Change'; 
                log.Created_By__c    = ld.OwnerId; // Assigned to new owner
                
                log.Name                   = 'Lead Owner Updated';
                log.Changed_Date_Time__c   = System.now(); // or ld.LastModifiedDate
                log.Action_Performed_By__c = UserInfo.getUserId(); 
                log.Description__c         = 'Lead ownership transferred.';
                
                logsToInsert.add(log);
            }
        }
        
        if (!logsToInsert.isEmpty()) {
            insert logsToInsert;
        }
    }


    public static void blockProtectedLeadDeletion(List<Lead__c> oldLeads) {
        for (Lead__c l : oldLeads) {
            if (l.Do_Not_Delete__c == true) {
                l.addError('❌ This custom Lead record is protected and cannot be deleted.');
            }
        }
    }
}