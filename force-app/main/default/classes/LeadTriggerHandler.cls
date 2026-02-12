public without sharing class LeadTriggerHandler {

    
   public static void createLeadActivityLogs(
    List<Lead__c> newList,
    Map<Id, Lead__c> oldMap,
    Boolean isInsert
) {
    List<Activity_Log__c> logsToInsert = new List<Activity_Log__c>();

    for (Lead__c ld : newList) {

        Lead__c oldRec = oldMap != null ? oldMap.get(ld.Id) : null;

        Boolean stageChanged = false;
        Boolean ownerChanged = false;

        if (!isInsert && oldRec != null) {
            stageChanged = oldRec.Stage__c != ld.Stage__c;
            ownerChanged = oldRec.OwnerId != ld.OwnerId;

         
            if (!stageChanged && !ownerChanged) {
                continue;
            }
        }

        Activity_Log__c log = new Activity_Log__c();

        log.Lead__c          = ld.Id;
        log.Logging_Id__c    = ld.Id;
        log.Created_By__c    = ld.OwnerId;

        /* ================= LEVEL CHANGE ================= */

        if (isInsert || stageChanged) {
            log.Activity_Type__c = 'Level Change';

            log.Previous_Level__c = isInsert ? null : oldRec.Stage__c;
            log.New_Level__c      = ld.Stage__c;
        }

        /* ================= OWNER CHANGE ================= */

        if (!isInsert && ownerChanged) {
              log.Activity_Type__c = 'Owner Change';
            log.Previous_Owner__c = oldRec.OwnerId;
            log.New_Owner__c      = ld.OwnerId;
        }

       

        if (isInsert) {
            log.Name                   = 'Created Lead Log';
            log.Changed_Date_Time__c   = ld.CreatedDate;
            log.Action_Performed_By__c = ld.CreatedById;
            log.Description__c         = 'Lead created';
        } else {
            log.Name                   = 'Updated Lead Log';
            log.Changed_Date_Time__c   = ld.LastModifiedDate;
            log.Action_Performed_By__c = ld.LastModifiedById;

            if (stageChanged && ownerChanged) {
                log.Description__c = 'Stage and Owner updated';
            } else if (stageChanged) {
                log.Description__c = 'Stage updated';
            } else if (ownerChanged) {
                log.Description__c = 'Owner updated';
            }
        }

        logsToInsert.add(log);
    }

    if (!logsToInsert.isEmpty()) {
        insert logsToInsert;
    }
}


   
    public static void createMergeLeadActivityLogs(
    List<Lead__c> newList,
    Map<Id, Lead__c> oldMap
) {
    List<Activity_Log__c> logsToInsert = new List<Activity_Log__c>();

    /* ============ FIND NEWLY MERGED LEADS ============ */

    Set<Id> newlyMergedLeadIds = new Set<Id>();

    for (Lead__c ld : newList) {
        Lead__c oldLd = oldMap.get(ld.Id);

        if (oldLd != null && !oldLd.Is_Merged__c && ld.Is_Merged__c) {
            newlyMergedLeadIds.add(ld.Id);
        }
    }

    if (newlyMergedLeadIds.isEmpty()) {
        return;
    }

    /* ============ LOAD MERGED LEADS WITH OWNER ============ */

    List<Lead__c> mergedLeads = [
        SELECT Id, Name, Lead__c, Stage__c, LastModifiedById, OwnerId
        FROM Lead__c
        WHERE Id IN :newlyMergedLeadIds
    ];

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

    /* ============ LOAD MAIN LEADS WITH OWNER ============ */

    Map<Id, Lead__c> mainLeadsMap = new Map<Id, Lead__c>([
        SELECT Id, Name, LastModifiedById, OwnerId
        FROM Lead__c
        WHERE Id IN :mainLeadIds
    ]);

    /* ============ CREATE LOGS ============ */

    for (Id mainLeadId : mainLeadToMergedLeadsMap.keySet()) {

        List<Lead__c> associatedMergedLeads = mainLeadToMergedLeadsMap.get(mainLeadId);
        Lead__c mainLead = mainLeadsMap.get(mainLeadId);

        if (mainLead == null || associatedMergedLeads.isEmpty()) {
            continue;
        }

        // Collect merged names
        List<String> mergedLeadNames = new List<String>();
        for (Lead__c ml : associatedMergedLeads) {
            mergedLeadNames.add(ml.Name);
        }

        String mergedNamesStr = String.join(mergedLeadNames, ', ');
        Integer mergeCount = mergedLeadNames.size();

        /* ===== MAIN LEAD LOG ===== */

        Activity_Log__c mainLeadLog = new Activity_Log__c();

        mainLeadLog.Lead__c                = mainLeadId;
        mainLeadLog.Logging_Id__c          = mainLeadId;
        mainLeadLog.Activity_Type__c       = 'Lead Merge';
        mainLeadLog.Name                   = 'Lead Merge - Main';
        mainLeadLog.Changed_Date_Time__c   = System.now();
        mainLeadLog.Action_Performed_By__c = mainLead.LastModifiedById;
        mainLeadLog.Created_By__c          = mainLead.LastModifiedById;
        mainLeadLog.Description__c         =
            mergeCount + ' lead(s) merged into this lead: ' + mergedNamesStr;

        //  OWNER TRACKING FOR MAIN LEAD
        Lead__c oldMainLead = oldMap.get(mainLeadId);
        if (oldMainLead != null && oldMainLead.OwnerId != mainLead.OwnerId) {
            mainLeadLog.Previous_Owner__c = oldMainLead.OwnerId;
            mainLeadLog.New_Owner__c      = mainLead.OwnerId;
        }

        logsToInsert.add(mainLeadLog);

        /* ===== MERGED LEAD LOGS ===== */

        for (Lead__c mergedLead : associatedMergedLeads) {

            Activity_Log__c mergedLeadLog = new Activity_Log__c();

            mergedLeadLog.Lead__c                = mergedLead.Id;
            mergedLeadLog.Logging_Id__c          = mergedLead.Id;
            mergedLeadLog.Activity_Type__c       = 'Lead Merge';
            mergedLeadLog.Name                   = 'Lead Merge - Merged';
            mergedLeadLog.Changed_Date_Time__c   = System.now();
            mergedLeadLog.Action_Performed_By__c = mergedLead.LastModifiedById;
            mergedLeadLog.Created_By__c          = mergedLead.LastModifiedById;
            mergedLeadLog.Description__c         =
                'This lead was merged into: ' + mainLead.Name + ' (ID: ' + mainLeadId + ')';

            //  OWNER TRACKING FOR MERGED LEAD
            Lead__c oldMergedLead = oldMap.get(mergedLead.Id);
            if (oldMergedLead != null && oldMergedLead.OwnerId != mergedLead.OwnerId) {
                mergedLeadLog.Activity_Type__c       = 'Owner Change';
                mergedLeadLog.Previous_Owner__c = oldMergedLead.OwnerId;
                mergedLeadLog.New_Owner__c      = mergedLead.OwnerId;
            }

            logsToInsert.add(mergedLeadLog);
        }
    }

    if (!logsToInsert.isEmpty()) {
        insert logsToInsert;
    }
}


  
  public static void createOwnerChangeActivityLogs(
    List<Lead__c> newList,
    Map<Id, Lead__c> oldMap
) {
    List<Activity_Log__c> logsToInsert = new List<Activity_Log__c>();

    for (Lead__c ld : newList) {

        Lead__c oldRec = oldMap.get(ld.Id);

        // Owner changed
        if (oldRec != null && oldRec.OwnerId != ld.OwnerId) {

            Activity_Log__c log = new Activity_Log__c();

            log.Lead__c           = ld.Id;
            log.Logging_Id__c     = ld.Id;
            log.Activity_Type__c  = 'Owner Change';

            //  STORE OLD + NEW OWNER
            log.Previous_Owner__c = oldRec.OwnerId;
            log.New_Owner__c      = ld.OwnerId;

            log.Name                   = 'Lead Owner Updated';
            log.Changed_Date_Time__c   = System.now();
            log.Action_Performed_By__c = UserInfo.getUserId();
            log.Created_By__c          = ld.OwnerId;

            log.Description__c =
                'Owner changed from ' + oldRec.OwnerId + ' to ' + ld.OwnerId;

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