/*
    Author       : ROHIT SINGH BISHT
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

        for (Event ev : newEvents) {
            Event oldEv = oldMap.get(ev.Id);

            Boolean changed =
                ev.Location != oldEv.Location ||
                ev.Meeting_type__c != oldEv.Meeting_type__c ||
                ev.StartDateTime != oldEv.StartDateTime ||
                ev.EndDateTime != oldEv.EndDateTime;

            if (changed &&
                !String.isBlank(ev.Location) &&
                !String.isBlank(ev.Meeting_type__c) &&
                ev.StartDateTime != null &&
                ev.EndDateTime != null) {
                toSend.add(ev.Id);
            }
        }

        if (!toSend.isEmpty()) {
            Webservice_GMeetRegistrationsService.sendGMeetRegistrations(toSend);
        }

        createGmeetActivityLogs(newEvents, oldMap, false);
    }

    public static void afterDelete(List<Event> oldEvents) {
    }

    public static void afterUndelete(List<Event> newEvents) {
    }

    private static void createGmeetActivityLogs(List<Event> newEvents, Map<Id, Event> oldMap, Boolean isInsert) {
        if (newEvents == null || newEvents.isEmpty()) return;

        List<Activity_Log__c> logsToInsert = new List<Activity_Log__c>();

        for (Event ev : newEvents) {
            Id leadId = getLeadIdFromEvent(ev);
            if (leadId == null) continue;

            String meetingType = getStringField(ev, 'Meeting_type__c');
            if (!isGmeet(meetingType)) continue;

            String approvalStatus = getStringField(ev, 'Approval_Status__c');

            Boolean approvalChanged = false;
            if (!isInsert && oldMap != null && oldMap.containsKey(ev.Id)) {
                String oldApproval = getStringField(oldMap.get(ev.Id), 'Approval_Status__c');
                approvalChanged = (oldApproval != approvalStatus);
            }

            Boolean becameGmeet = false;
            if (!isInsert && oldMap != null && oldMap.containsKey(ev.Id)) {
                String oldMeetingType = getStringField(oldMap.get(ev.Id), 'Meeting_type__c');
                becameGmeet = !isGmeet(oldMeetingType) && isGmeet(meetingType);
            }

            Boolean shouldCreate = isInsert || becameGmeet;
            Boolean shouldLogApproval = approvalChanged && isTrackedApprovalStatus(approvalStatus);

            if (!shouldCreate && !shouldLogApproval) continue;

            Activity_Log__c log = new Activity_Log__c();
            log.Lead__c = leadId;
            log.Logging_Id__c = ev.Id;
            log.Activity_Type__c = 'Gmeet';
            log.Changed_Date_Time__c = isInsert ? ev.CreatedDate : ev.LastModifiedDate;
            log.Action_Performed_By__c = isInsert ? ev.CreatedById : ev.LastModifiedById;
            log.Created_By__c = UserInfo.getName();

            if (shouldLogApproval) {
                log.Name = 'GMeet Approval Status';
                log.Description__c = 'Approval status changed to ' + approvalStatus + '.';
                setApprovalStatusIfPresent(log, approvalStatus);
            } else {
                log.Name = 'GMeet Created';
                log.Description__c = 'GMeet event created.';
                if (!String.isBlank(approvalStatus)) {
                    log.Description__c += ' Approval status: ' + approvalStatus + '.';
                    setApprovalStatusIfPresent(log, approvalStatus);
                }
            }

            logsToInsert.add(log);
        }

        if (!logsToInsert.isEmpty()) {
            insert logsToInsert;
        }
    }

    private static Id getLeadIdFromEvent(Event ev) {
        if (ev == null || ev.WhatId == null) return null;
        return (ev.WhatId.getSObjectType() == Lead__c.SObjectType) ? ev.WhatId : null;
    }

    private static Boolean isGmeet(String meetingType) {
        return !String.isBlank(meetingType) && meetingType.trim().equalsIgnoreCase('Gmeet');
    }

    private static Boolean isTrackedApprovalStatus(String status) {
        if (String.isBlank(status)) return false;
        String s = status.trim().toLowerCase();
        return s == 'pending for approval' || s == 'approved' || s == 'rejected';
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
}