/*
    Author       : Rohit Singh Bisht
*/
public without sharing class LeadActivityLogHandler {

    public static void createLeadActivityLogs(
        List<Lead__c> newList,
        Map<Id, Lead__c> oldMap,
        Boolean isInsert
    ) {
        List<Activity_Log__c> logsToInsert = new List<Activity_Log__c>();
        Id levelChangeRecordTypeId = getActivityLogRecordTypeId('Level Change');
        Id ownerChangeRecordTypeId = getActivityLogRecordTypeId('Owner Change');
        Id queueHandoffRecordTypeId = getActivityLogRecordTypeId('Queue Handoff');
        Map<Id, String> ownerNamesById = getOwnerNames(newList, oldMap);

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

            if (isInsert || stageChanged) {
                Activity_Log__c levelLog = new Activity_Log__c();
                levelLog.Lead__c = ld.Id;
                levelLog.Logging_Id__c = ld.Id;
                levelLog.Created_By__c = ld.OwnerId;
                levelLog.Activity_Type__c = 'Level Change';
                levelLog.Previous_Level__c = isInsert ? null : oldRec.Stage__c;
                levelLog.New_Level__c = ld.Stage__c;
                levelLog.Name = isInsert ? 'Created Lead Log' : 'Lead Level Updated';
                levelLog.Changed_Date_Time__c = isInsert ? ld.CreatedDate : ld.LastModifiedDate;
                levelLog.Action_Performed_By__c = isInsert ? ld.CreatedById : ld.LastModifiedById;
                levelLog.Description__c = isInsert ? 'Lead created' : 'Stage updated';
                if (levelChangeRecordTypeId != null) {
                    levelLog.RecordTypeId = levelChangeRecordTypeId;
                }
                logsToInsert.add(levelLog);
            }

            if (!isInsert && ownerChanged) {
                Boolean oldIsQueue = isQueueOwner(oldRec.OwnerId);
                Boolean newIsQueue = isQueueOwner(ld.OwnerId);
                Boolean isCandidateQueueTransition = (oldIsQueue && !newIsQueue) || (!oldIsQueue && newIsQueue);
                if (isCandidateQueueTransition) {
                    continue;
                }

                Activity_Log__c ownerLog = new Activity_Log__c();
                ownerLog.Lead__c = ld.Id;
                ownerLog.Logging_Id__c = ld.Id;
                ownerLog.Created_By__c = ld.OwnerId;
                ownerLog.Activity_Type__c = 'Owner Change';
                ownerLog.Changed_Date_Time__c = ld.LastModifiedDate;
                ownerLog.Action_Performed_By__c = ld.LastModifiedById;
                applyOwnerChangeDetails(
                    ownerLog,
                    oldRec.OwnerId,
                    ld.OwnerId,
                    'Lead',
                    ownerNamesById,
                    ownerChangeRecordTypeId,
                    queueHandoffRecordTypeId
                );
                logsToInsert.add(ownerLog);
            }
        }

        if (!logsToInsert.isEmpty()) {
            ActivityLogService.insertLogs(logsToInsert);
        }
    }

    public static void createMergeLeadActivityLogs(
        List<Lead__c> newList,
        Map<Id, Lead__c> oldMap
    ) {
        List<Activity_Log__c> logsToInsert = new List<Activity_Log__c>();
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

        Map<Id, Lead__c> mainLeadsMap = new Map<Id, Lead__c>([
            SELECT Id, Name, LastModifiedById, OwnerId
            FROM Lead__c
            WHERE Id IN :mainLeadIds
        ]);

        for (Id mainLeadId : mainLeadToMergedLeadsMap.keySet()) {
            List<Lead__c> associatedMergedLeads = mainLeadToMergedLeadsMap.get(mainLeadId);
            Lead__c mainLead = mainLeadsMap.get(mainLeadId);

            if (mainLead == null || associatedMergedLeads.isEmpty()) {
                continue;
            }

            List<String> mergedLeadNames = new List<String>();
            for (Lead__c ml : associatedMergedLeads) {
                mergedLeadNames.add(ml.Name);
            }

            String mergedNamesStr = String.join(mergedLeadNames, ', ');
            Integer mergeCount = mergedLeadNames.size();

            Activity_Log__c mainLeadLog = new Activity_Log__c();
            mainLeadLog.Lead__c = mainLeadId;
            mainLeadLog.Logging_Id__c = mainLeadId;
            mainLeadLog.Activity_Type__c = 'Lead Merge';
            mainLeadLog.Name = 'Lead Merge - Main';
            mainLeadLog.Changed_Date_Time__c = System.now();
            mainLeadLog.Action_Performed_By__c = mainLead.LastModifiedById;
            mainLeadLog.Created_By__c = mainLead.LastModifiedById;
            mainLeadLog.Description__c = mergeCount + ' lead(s) merged into this lead: ' + mergedNamesStr;

            Lead__c oldMainLead = oldMap.get(mainLeadId);
            if (oldMainLead != null && oldMainLead.OwnerId != mainLead.OwnerId) {
                mainLeadLog.Previous_Owner__c = oldMainLead.OwnerId;
                mainLeadLog.New_Owner__c = mainLead.OwnerId;
            }

            logsToInsert.add(mainLeadLog);

            for (Lead__c mergedLead : associatedMergedLeads) {
                Activity_Log__c mergedLeadLog = new Activity_Log__c();
                mergedLeadLog.Lead__c = mergedLead.Id;
                mergedLeadLog.Logging_Id__c = mergedLead.Id;
                mergedLeadLog.Activity_Type__c = 'Lead Merge';
                mergedLeadLog.Name = 'Lead Merge - Merged';
                mergedLeadLog.Changed_Date_Time__c = System.now();
                mergedLeadLog.Action_Performed_By__c = mergedLead.LastModifiedById;
                mergedLeadLog.Created_By__c = mergedLead.LastModifiedById;
                mergedLeadLog.Description__c =
                    'This lead was merged into: ' + mainLead.Name + ' (ID: ' + mainLeadId + ')';

                Lead__c oldMergedLead = oldMap.get(mergedLead.Id);
                if (oldMergedLead != null && oldMergedLead.OwnerId != mergedLead.OwnerId) {
                    mergedLeadLog.OwnerId = mergedLead.OwnerId;
                    mergedLeadLog.Activity_Type__c = 'Owner Change';
                    mergedLeadLog.Previous_Owner__c = oldMergedLead.OwnerId;
                    mergedLeadLog.New_Owner__c = mergedLead.OwnerId;
                }

                logsToInsert.add(mergedLeadLog);
            }
        }

        if (!logsToInsert.isEmpty()) {
            ActivityLogService.insertLogs(logsToInsert);
        }
    }

    private static Id getActivityLogRecordTypeId(String recordTypeName) {
        if (String.isBlank(recordTypeName)) {
            return null;
        }

        Map<String, Schema.RecordTypeInfo> recordTypeInfos =
            Schema.SObjectType.Activity_Log__c.getRecordTypeInfosByName();

        if (recordTypeInfos != null && recordTypeInfos.containsKey(recordTypeName)) {
            return recordTypeInfos.get(recordTypeName).getRecordTypeId();
        }

        return null;
    }

    private static void applyOwnerChangeDetails(
        Activity_Log__c logRec,
        Id oldOwnerId,
        Id newOwnerId,
        String subjectLabel,
        Map<Id, String> ownerNamesById,
        Id ownerChangeRecordTypeId,
        Id queueHandoffRecordTypeId
    ) {
        if (logRec == null) {
            return;
        }

        Boolean oldIsQueue = isQueueOwner(oldOwnerId);
        Boolean newIsQueue = isQueueOwner(newOwnerId);
        Boolean isQueueHandoff = oldIsQueue || newIsQueue;

        if (!newIsQueue) {
            logRec.OwnerId = newOwnerId;
        }

        logRec.Previous_Owner__c = oldIsQueue ? null : oldOwnerId;
        logRec.New_Owner__c = newIsQueue ? null : newOwnerId;
        logRec.Name = isQueueHandoff ? subjectLabel + ' Queue Handoff' : subjectLabel + ' Owner Updated';
        logRec.Description__c =
            'Owner changed from ' + getOwnerDisplayName(oldOwnerId, ownerNamesById) +
            ' to ' + getOwnerDisplayName(newOwnerId, ownerNamesById) + '.';

        if (isQueueHandoff) {
            logRec.put('Queue_Name__c', newIsQueue
                ? getOwnerDisplayName(newOwnerId, ownerNamesById)
                : getOwnerDisplayName(oldOwnerId, ownerNamesById));
            if (queueHandoffRecordTypeId != null) {
                logRec.RecordTypeId = queueHandoffRecordTypeId;
            }
        } else if (ownerChangeRecordTypeId != null) {
            logRec.RecordTypeId = ownerChangeRecordTypeId;
        }
    }

    private static String getOwnerDisplayName(Id ownerId, Map<Id, String> ownerNamesById) {
        if (ownerId == null) {
            return 'Unknown';
        }
        String ownerName = ownerNamesById != null ? ownerNamesById.get(ownerId) : null;
        return String.isNotBlank(ownerName) ? ownerName : String.valueOf(ownerId);
    }

    private static Boolean isQueueOwner(Id ownerId) {
        return ownerId != null && ownerId.getSObjectType() == Group.SObjectType;
    }

    private static Map<Id, String> getOwnerNames(List<Lead__c> newList, Map<Id, Lead__c> oldMap) {
        Set<Id> ownerIds = new Set<Id>();
        for (Lead__c ld : newList) {
            Lead__c oldRec = oldMap != null ? oldMap.get(ld.Id) : null;
            if (ld.OwnerId != null) ownerIds.add(ld.OwnerId);
            if (oldRec != null && oldRec.OwnerId != null) ownerIds.add(oldRec.OwnerId);
        }

        Map<Id, String> namesById = new Map<Id, String>();
        if (ownerIds.isEmpty()) {
            return namesById;
        }

        for (User u : [SELECT Id, Name FROM User WHERE Id IN :ownerIds]) {
            namesById.put(u.Id, u.Name);
        }
        for (Group g : [SELECT Id, Name FROM Group WHERE Id IN :ownerIds]) {
            if (!namesById.containsKey(g.Id)) {
                namesById.put(g.Id, g.Name);
            }
        }
        return namesById;
    }
}
