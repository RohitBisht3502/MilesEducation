public without sharing class NavBarDateService {

    @AuraEnabled(cacheable=true)
    public static Map<String, Datetime> getIconDates(Id recordId) {
        Map<String, Datetime> result = new Map<String, Datetime>();

        if (recordId == null) {
            return result;
        }

        String sObjName = recordId.getSObjectType().getDescribe().getName();
        Boolean isLead = (sObjName == 'Lead__c');
        Boolean isAccount = (sObjName == 'Account');
        Boolean isCandidate = (sObjName == 'Lead');

        if (!isLead && !isAccount && !isCandidate) {
            return result;
        }

        // Webinar dates
        String webinarQuery = 'SELECT Webinar__r.Type_Of_Webinar__c webinarType, MAX(Webinar__r.Start_Date_Time__c) latestDt'
            + ' FROM Webinar_Member__c'
            + ' WHERE Attendance_Status__c = \'Present\' AND Webinar__c != null AND ';

        if (isLead) {
            webinarQuery += 'Lead__c = :recordId';
        } else if (isAccount) {
            webinarQuery += 'Student__c = :recordId';
        } else {
            webinarQuery += 'Candidate__c = :recordId';
        }
        webinarQuery += ' GROUP BY Webinar__r.Type_Of_Webinar__c';

        for (AggregateResult ar : Database.query(webinarQuery)) {
            String webinarType = (String) ar.get('webinarType');
            Datetime latestDt = (Datetime) ar.get('latestDt');
            if (latestDt != null) {
                String label = (webinarType != null && webinarType.trim().equalsIgnoreCase('CAIRA'))
                    ? 'CAIRA Webinar'
                    : 'Zoom Webinar';
                result.put(label, latestDt);
            }
        }

        // Event dates
        for (AggregateResult ar : [
            SELECT Meeting_type__c source, MAX(StartDateTime) latestDt
            FROM Event
            WHERE (WhoId = :recordId OR WhatId = :recordId)
                AND Meeting_type__c != null
                AND Meeting_type__c != ''
                AND Stage__c = 'Completed'
            GROUP BY Meeting_type__c
        ]) {
            String source = (String) ar.get('source');
            Datetime latestDt = (Datetime) ar.get('latestDt');
            if (latestDt != null && source != null) {
                result.put(source, latestDt);
            }
        }

        return result;
    }
}