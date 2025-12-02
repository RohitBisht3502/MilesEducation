public without sharing class LeadTriggerHandler {

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
			log.Created_By__c = ld.OwnerId;

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
                log.Name                  = 'Created Lead Log';
                log.Changed_Date_Time__c  = ld.CreatedDate;
                log.Action_Performed_By__c = ld.CreatedById;
                log.Description__c        = 'Lead created';
            } else {
                log.Name                  = 'Updated Lead Log';
                log.Changed_Date_Time__c  = ld.LastModifiedDate;
                log.Action_Performed_By__c = ld.LastModifiedById;
                log.Description__c        = 'Stage is updated';
            }

            logsToInsert.add(log);
        }

        if (!logsToInsert.isEmpty()) {
            insert logsToInsert;
        }
    }
}