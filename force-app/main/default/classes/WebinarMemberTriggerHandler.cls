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

        createWebinarActivityLogs(newMembers, null, true);
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

        createWebinarActivityLogs(newMembers, oldMap, false);
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

    private static void createWebinarActivityLogs(
        List<Webinar_Member__c> newMembers,
        Map<Id, Webinar_Member__c> oldMap,
        Boolean isInsert
    ) {
        if (newMembers == null || newMembers.isEmpty()) return;

        Set<Id> webinarIds = new Set<Id>();
        for (Webinar_Member__c wm : newMembers) {
            if (wm != null && wm.Webinar__c != null) {
                webinarIds.add(wm.Webinar__c);
            }
        }

        Map<Id, String> webinarNameById = new Map<Id, String>();
        if (!webinarIds.isEmpty()) {
            for (Webinar__c w : [
                SELECT Id, Name
                FROM Webinar__c
                WHERE Id IN :webinarIds
            ]) {
                webinarNameById.put(w.Id, w.Name);
            }
        }

        List<Activity_Log__c> logsToInsert = new List<Activity_Log__c>();

        for (Webinar_Member__c wm : newMembers) {
            if (wm == null) continue;

            if (wm.Webinar__c == null) continue;

            Id leadId = wm.Lead__c;
            Id candidateId = wm.Candidate__c;
            Id enquiryId = wm.Enquiry__c;

            if (leadId == null && candidateId == null && enquiryId == null) continue;

            String webinarName = webinarNameById.get(wm.Webinar__c);
            String webinarLabel = String.isBlank(webinarName) ? 'this webinar' : webinarName;

            if (!isInsert) {
                Webinar_Member__c oldWm = oldMap != null ? oldMap.get(wm.Id) : null;
                if (oldWm == null) continue;

                if (oldWm.Attendance_Status__c == wm.Attendance_Status__c) continue;
            }

            Activity_Log__c log = new Activity_Log__c();
            log.Activity_Type__c = 'Webinar';
            log.Logging_Id__c = wm.Id;
            log.Changed_Date_Time__c = isInsert ? wm.CreatedDate : wm.LastModifiedDate;
            log.Action_Performed_By__c = isInsert ? wm.CreatedById : wm.LastModifiedById;
            log.Created_By__c = UserInfo.getName();

            if (leadId != null) log.Lead__c = leadId;
            if (candidateId != null) log.Candidate__c = candidateId;
            if (enquiryId != null) log.Enquiry__c = enquiryId;

            if (isInsert) {
                log.Name = 'Webinar Registration';
                log.Description__c = 'Lead registered in webinar ' + webinarLabel + '.';
            } else {
                Webinar_Member__c oldWm = oldMap.get(wm.Id);
                String oldStatus = oldWm != null ? oldWm.Attendance_Status__c : null;
                String newStatus = wm.Attendance_Status__c;
                String oldStatusLabel = String.isBlank(oldStatus) ? 'blank' : oldStatus;
                String newStatusLabel = String.isBlank(newStatus) ? 'blank' : newStatus;
                log.Name = 'Webinar Attendance Update';
                log.Description__c =
                    'Webinar attendance status changed from ' + oldStatusLabel + ' to ' + newStatusLabel +
                    ' for webinar ' + webinarLabel + '.';
            }

            logsToInsert.add(log);
        }

        if (!logsToInsert.isEmpty()) {
            insert logsToInsert;
        }
    }
}