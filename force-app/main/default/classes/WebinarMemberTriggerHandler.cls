public without sharing class WebinarMemberTriggerHandler {

    public static void beforeInsert(List<Webinar_Member__c> newMembers) {
        // no-op
    }

    public static void beforeUpdate(List<Webinar_Member__c> newMembers, Map<Id, Webinar_Member__c> oldMap) {
        // no-op
    }

    public static void beforeDelete(List<Webinar_Member__c> oldMembers) {
        // no-op
    }

    public static void afterInsert(List<Webinar_Member__c> newMembers) {
        Set<Id> toSend = new Set<Id>();

        for (Webinar_Member__c wm : newMembers) {
            // Only send when required fields exist (same rule as your service)
            if (wm != null &&
                wm.Lead__c != null &&
                wm.Webinar__c != null &&        // ensures relationship exists
                !String.isBlank(wm.Registrant_Id__c)) {
                toSend.add(wm.Id);
            }
        }

        if (!toSend.isEmpty()) {
            Webservice_WebinarRegistrationsService.sendWebinarRegistrations(toSend);
        }
    }

    public static void afterUpdate(List<Webinar_Member__c> newMembers, Map<Id, Webinar_Member__c> oldMap) {
        Set<Id> toSend = new Set<Id>();

        for (Webinar_Member__c wm : newMembers) {
            Webinar_Member__c oldWm = oldMap != null ? oldMap.get(wm.Id) : null;
            if (wm == null || oldWm == null) continue;

            Boolean changed =
                wm.Lead__c != oldWm.Lead__c ||
                wm.Webinar__c != oldWm.Webinar__c ||
                wm.Registrant_Id__c != oldWm.Registrant_Id__c;

            if (changed &&
                wm.Lead__c != null &&
                wm.Webinar__c != null &&
                !String.isBlank(wm.Registrant_Id__c)) {
                toSend.add(wm.Id);
            }
        }

        if (!toSend.isEmpty()) {
            Webservice_WebinarRegistrationsService.sendWebinarRegistrations(toSend);
        }
    }

    public static void afterDelete(List<Webinar_Member__c> oldMembers) {
        // no-op
    }

    public static void afterUndelete(List<Webinar_Member__c> newMembers) {
        // optional: if you want to send on undelete too
        Set<Id> toSend = new Set<Id>();

        for (Webinar_Member__c wm : newMembers) {
            if (wm != null &&
                wm.Lead__c != null &&
                wm.Webinar__c != null &&
                !String.isBlank(wm.Registrant_Id__c)) {
                toSend.add(wm.Id);
            }
        }

        if (!toSend.isEmpty()) {
            Webservice_WebinarRegistrationsService.sendWebinarRegistrations(toSend);
        }
    }
}