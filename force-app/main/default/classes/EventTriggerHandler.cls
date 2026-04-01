/*
    Author       : Rohit Singh Bisht
    Description  : 
*/
public without sharing class EventTriggerHandler {

    public static void beforeInsert(List<Event> newEvents) {
    }

    public static void beforeUpdate(List<Event> newEvents, Map<Id, Event> oldMap) {
    }

    public static void beforeDelete(List<Event> oldEvents) {
    }

    public static void afterInsert(List<Event> newEvents) {
        Set<Id> toSend = new Set<Id>();

        for (Event ev : newEvents) {
            if (!String.isBlank(ev.Location) &&
                !String.isBlank(ev.Meeting_type__c) &&
                ev.StartDateTime != null &&
                ev.EndDateTime != null) {
                toSend.add(ev.Id);
            }
        }

        if (!toSend.isEmpty()) {
            Webservice_GMeetRegistrationsService.sendGMeetRegistrations(toSend);
        }

        createGmeetActivityLogs(newEvents, null, true);
    }

    public static void afterUpdate(List<Event> newEvents, Map<Id, Event> oldMap) {
        Set<Id> toSend = new Set<Id>();
        Set<Id> toSyncGoogle = new Set<Id>();
        Set<Id> toNotifyDataLake = new Set<Id>();

        for (Event ev : newEvents) {
            Event oldEv = oldMap.get(ev.Id);
            String newStage = getStringField(ev, 'Stage__c');
            String oldStage = getStringField(oldEv, 'Stage__c');

            Boolean changed =
                ev.Location != oldEv.Location ||
                ev.Meeting_type__c != oldEv.Meeting_type__c ||
                ev.StartDateTime != oldEv.StartDateTime ||
                ev.EndDateTime != oldEv.EndDateTime;
            Boolean stageChanged = newStage != oldStage;
            Boolean hasGoogleEventId = String.isNotBlank(getStringField(ev, 'Event_Id__c'));
            Boolean hasConferenceId = String.isNotBlank(getStringField(ev, 'ConferenceId__c'));
            Boolean shouldSyncGoogle =
                hasGoogleEventId &&
                (changed || stageChanged) &&
                (
                    !String.isBlank(ev.Location) ||
                    isCancelledStage(newStage)
                );
            Boolean shouldNotifyDataLake =
                hasGoogleEventId &&
                hasConferenceId &&
                (
                    ev.StartDateTime != oldEv.StartDateTime ||
                    ev.EndDateTime != oldEv.EndDateTime ||
                    (stageChanged && isCancelledStage(newStage))
                );

            if (changed &&
                !String.isBlank(ev.Location) &&
                !String.isBlank(ev.Meeting_type__c) &&
                ev.StartDateTime != null &&
                ev.EndDateTime != null) {
                toSend.add(ev.Id);
            }

            if (shouldSyncGoogle) {
                toSyncGoogle.add(ev.Id);
            }
            if (shouldNotifyDataLake) {
                toNotifyDataLake.add(ev.Id);
            }
        }

        if (!toSend.isEmpty()) {
            Webservice_GMeetRegistrationsService.sendGMeetRegistrations(toSend);
        }

        if (!toSyncGoogle.isEmpty()) {
            GmeetCalloutSyncService.syncUpdatedEvents(new List<Id>(toSyncGoogle));
        }
        if (!toNotifyDataLake.isEmpty()) {
            Callout_GmeetUpdateDataLake.sendUpdates(new List<Id>(toNotifyDataLake));
        }

        createGmeetActivityLogs(newEvents, oldMap, false);
    }

    public static void afterDelete(List<Event> oldEvents) {
        List<String> googleEventIdsToCancel = new List<String>();
        for (Event ev : oldEvents) {
            String googleEventId = getStringField(ev, 'Event_Id__c');
            if (String.isNotBlank(googleEventId)) {
                googleEventIdsToCancel.add(googleEventId);
            }
        }

        if (!googleEventIdsToCancel.isEmpty()) {
            GmeetCalloutSyncService.cancelDeletedEvents(googleEventIdsToCancel);
        }
    }

    public static void afterUndelete(List<Event> newEvents) {
    }

    private static void createGmeetActivityLogs(List<Event> newEvents, Map<Id, Event> oldMap, Boolean isInsert) {
        if (newEvents == null || newEvents.isEmpty()) return;

        List<Activity_Log__c> logsToInsert = new List<Activity_Log__c>();

        for (Event ev : newEvents) {
            EventLogContext context = getEventLogContext(ev);
            if (context == null || !context.hasTarget()) continue;

            String approvalStatus = getStringField(ev, 'Approval_Status__c');
            String stageValue = getStringField(ev, 'Stage__c');

            Boolean approvalChanged = false;
            Boolean rescheduled = false;
            Boolean cancelled = false;
            if (!isInsert && oldMap != null && oldMap.containsKey(ev.Id)) {
                Event oldEv = oldMap.get(ev.Id);
                String oldApproval = getStringField(oldEv, 'Approval_Status__c');
                approvalChanged = (oldApproval != approvalStatus);
                rescheduled =
                    ev.StartDateTime != oldEv.StartDateTime ||
                    ev.EndDateTime != oldEv.EndDateTime;
                cancelled =
                    getStringField(oldEv, 'Stage__c') != stageValue &&
                    isCancelledStage(stageValue);
            }

            Boolean shouldCreate = isInsert;
            Boolean shouldLogApproval = !isInsert && approvalChanged;
            Boolean shouldLogRescheduled = !isInsert && rescheduled;
            Boolean shouldLogCancelled = !isInsert && cancelled;

            if (!shouldCreate && !shouldLogApproval && !shouldLogRescheduled && !shouldLogCancelled) continue;

            if (shouldCreate) {
                Activity_Log__c log = buildBaseGmeetLog(ev, context, true);
                log.Name = 'GMeet Created';
                log.Description__c = 'GMeet event created.';
                if (!String.isBlank(approvalStatus)) {
                    log.Description__c += ' Approval status: ' + approvalStatus + '.';
                    setApprovalStatusIfPresent(log, approvalStatus);
                }
                logsToInsert.add(log);
            }

            if (shouldLogApproval) {
                Activity_Log__c log = buildBaseGmeetLog(ev, context, false);
                log.Name = 'GMeet Approval Status';
                log.Description__c = 'Approval status changed to ' + approvalStatus + '.';
                setApprovalStatusIfPresent(log, approvalStatus);
                logsToInsert.add(log);
            }

            if (shouldLogRescheduled) {
                Activity_Log__c log = buildBaseGmeetLog(ev, context, false);
                log.Name = 'GMeet Rescheduled';
                log.put('Start_Date_Time__c', ev.StartDateTime);
                log.End_Date_Time__c = ev.EndDateTime;
                log.Description__c =
                    'GMeet event rescheduled. New start: ' + formatDateTime(ev.StartDateTime) +
                    ', new end: ' + formatDateTime(ev.EndDateTime) + '.';
                logsToInsert.add(log);
            }

            if (shouldLogCancelled) {
                Activity_Log__c log = buildBaseGmeetLog(ev, context, false);
                log.Name = 'GMeet Cancelled';
                log.Description__c = 'GMeet event cancelled.';
                logsToInsert.add(log);
            }
        }

        if (!logsToInsert.isEmpty()) {
            ActivityLogService.insertLogs(logsToInsert);
        }
    }

    private static Activity_Log__c buildBaseGmeetLog(Event ev, EventLogContext context, Boolean isInsert) {
        Activity_Log__c log = new Activity_Log__c();
        if (context != null) {
            if (context.leadId != null) {
                log.Lead__c = context.leadId;
            }
            if (context.candidateId != null) {
                log.Candidate__c = context.candidateId;
            }
        }
        log.Logging_Id__c = ev.Id;
        log.Activity_Type__c = 'Gmeet';
        log.Changed_Date_Time__c = isInsert ? ev.CreatedDate : ev.LastModifiedDate;
        log.Action_Performed_By__c = isInsert ? ev.CreatedById : ev.LastModifiedById;
        log.Created_By__c = UserInfo.getName();
        return log;
    }

    private class EventLogContext {
        Id leadId;
        Id candidateId;

        Boolean hasTarget() {
            return leadId != null || candidateId != null;
        }
    }

    private static EventLogContext getEventLogContext(Event ev) {
        if (ev == null) {
            return null;
        }

        EventLogContext context = new EventLogContext();

        if (ev.WhatId != null && ev.WhatId.getSObjectType() == Lead__c.SObjectType) {
            context.leadId = ev.WhatId;
        }
        if (ev.WhoId != null && ev.WhoId.getSObjectType() == Lead.SObjectType) {
            context.candidateId = ev.WhoId;
        }

        return context;
    }

    private static String getStringField(SObject sobj, String fieldApiName) {
        if (sobj == null || String.isBlank(fieldApiName)) return null;
        Map<String, Schema.SObjectField> fMap = sobj.getSObjectType().getDescribe().fields.getMap();
        if (!fMap.containsKey(fieldApiName)) return null;
        Object val = sobj.get(fieldApiName);
        return val == null ? null : String.valueOf(val);
    }

    private static void setApprovalStatusIfPresent(Activity_Log__c log, String status) {
        if (log == null) return;
        Map<String, Schema.SObjectField> fMap = Activity_Log__c.SObjectType.getDescribe().fields.getMap();
        if (fMap.containsKey('Approval_Status__c')) {
            log.put('Approval_Status__c', status);
        }
    }

    private static Boolean isCancelledStage(String stageValue) {
        return stageValue == 'Cancelled' || stageValue == 'Canceled';
    }

    private static String formatDateTime(Datetime value) {
        return value == null ? 'N/A' : value.format('yyyy-MM-dd HH:mm');
    }
}