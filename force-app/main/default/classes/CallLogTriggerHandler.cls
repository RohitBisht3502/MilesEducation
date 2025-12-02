public without sharing class CallLogTriggerHandler {

    public static void createActivityLogs(
        List<Call_Log__c> newCallLogs,
        Map<Id, Call_Log__c> oldMap,
        Boolean isInsert
    ) {
        List<Activity_Log__c> activityLogsToInsert = new List<Activity_Log__c>();
        List<Activity_Log__c> activityLogsToUpdate = new List<Activity_Log__c>();

        // For updates, pre-load existing Activity_Log__c records by Logging_Id__c (Call_Log__c Id)
        Map<Id, Activity_Log__c> existingByCallLogId = new Map<Id, Activity_Log__c>();
        if (!isInsert) {
            Set<Id> callLogIds = new Set<Id>();
            for (Call_Log__c cl : newCallLogs) {
                callLogIds.add(cl.Id);
            }

            if (!callLogIds.isEmpty()) {
                for (Activity_Log__c al : [
                    SELECT Id,
                           Name,
                           L1__c,
                           L2__c,
                           Call_Duration_Seconds__c,
                           Call_Recording_URL__c,
                           Lead__c,
                           Logging_Id__c,
                           Activity_Type__c,
                           Changed_Date_Time__c,
                           Action_Performed_By__c,
                           Description__c,
                           Created_By__c
                    FROM Activity_Log__c
                    WHERE Logging_Id__c IN :callLogIds
                ]) {
                    existingByCallLogId.put((Id)al.Logging_Id__c, al);
                }
            }
        }

        for (Call_Log__c cl : newCallLogs) {
            Activity_Log__c al;

            if (isInsert) {
                // New Call Log → create new Activity Log
                al = new Activity_Log__c();
            } else {
                // Update Call Log → try to get existing Activity Log
                al = existingByCallLogId.get(cl.Id);

                // Safety net: if somehow not found, create new one
                if (al == null) {
                    al = new Activity_Log__c();
                }
            }

            // ===== Copy common fields (always overwrite with latest) =====
            al.L1__c                    = cl.L1__c;
            al.L2__c                    = cl.L2__c;
            al.Call_Duration_Seconds__c = cl.Duration_Seconds__c;
            al.Call_Recording_URL__c    = cl.Recording_Url__c;
            if(cl.Lead__c!=null){
            	al.Lead__c                  = cl.Lead__c;
            }
            al.Logging_Id__c            = cl.Id;
            al.Activity_Type__c         = 'Call';
			al.Call_Log_Type__c 		= cl.Type__c;

            if (isInsert || al.Id == null) {
                // ===== ON CREATE =====
                al.Name = 'Created Call Log';

                // Changed date/time = created date
                al.Changed_Date_Time__c = (cl.Created_At__c != null)
                                          ? cl.Created_At__c
                                          : cl.CreatedDate;

                // Performed by = CreatedBy
                al.Action_Performed_By__c = cl.CreatedById;

                // Custom text: who created the call log (store current user name)
                al.Created_By__c = UserInfo.getName();

                // Description for create
                al.Description__c = 'Created Call Log.';

                activityLogsToInsert.add(al);
            } else {
                // ===== ON UPDATE =====
                al.Name = 'Updated Call Log';

                // Changed date/time = last modified
                al.Changed_Date_Time__c = cl.LastModifiedDate;

                // Performed by = LastModifiedBy
                al.Action_Performed_By__c = cl.LastModifiedById;

                // ---- Build Description based on changed fields ----
                Call_Log__c oldRec        = oldMap != null ? oldMap.get(cl.Id) : null;
                List<String> changedNames = new List<String>();

                if (oldRec != null) {
                    if (isChanged(oldRec.L1__c, cl.L1__c)) {
                        changedNames.add('L1 Disposition');
                    }
                    if (isChanged(oldRec.L2__c, cl.L2__c)) {
                        changedNames.add('L2 Disposition');
                    }
                    if (isChanged(oldRec.Duration_Seconds__c, cl.Duration_Seconds__c)) {
                        changedNames.add('Call duration');
                    }
                    if (isChanged(oldRec.Recording_Url__c, cl.Recording_Url__c)) {
                        changedNames.add('Call recording url');
                    }
                }

                if (!changedNames.isEmpty()) {
                    String fieldListText = buildNaturalLanguageList(changedNames);
                    al.Description__c = fieldListText + ' is changed.';
                } else {
                    al.Description__c = 'Call Log updated (no tracked fields changed).';
                }

                // Do NOT touch Created_By__c here – it should remain original creator
                activityLogsToUpdate.add(al);
            }
        }

        if (!activityLogsToInsert.isEmpty()) {
            insert activityLogsToInsert;
        }
        if (!activityLogsToUpdate.isEmpty()) {
            update activityLogsToUpdate;
        }
    }

    // ===== Helpers =====

    // Null-safe "is value changed?" for String / Decimal / Integer etc.
    private static Boolean isChanged(Object oldVal, Object newVal) {
        if (oldVal == null && newVal == null) {
            return false;
        }
        if (oldVal == null && newVal != null) {
            return true;
        }
        if (oldVal != null && newVal == null) {
            return true;
        }
        return oldVal != newVal;
    }

    // Build "X", "X and Y", or "X, Y and Z"
    private static String buildNaturalLanguageList(List<String> items) {
        if (items.isEmpty()) {
            return '';
        }
        if (items.size() == 1) {
            return items[0];
        }
        if (items.size() == 2) {
            return items[0] + ' and ' + items[1];
        }

        // 3 or more
        String result = '';
        for (Integer i = 0; i < items.size(); i++) {
            if (i == items.size() - 1) {
                result += 'and ' + items[i];
            } else {
                result += items[i] + ', ';
            }
        }
        return result;
    }
}