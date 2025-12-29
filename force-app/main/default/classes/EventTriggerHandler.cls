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
    }

    public static void afterDelete(List<Event> oldEvents) {
    }

    public static void afterUndelete(List<Event> newEvents) {
    }
}