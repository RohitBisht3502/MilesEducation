public without sharing class SobjectNavBarController {

    private static final String ENQUIRY_OBJECT = 'Enquiry__c';
    private static final String WEBINAR_OBJECT = 'Webinar_Member__c';
    private static final String SOURCE_FIELD  = 'Coming_From__c';
    private static final String LEAD_LOOKUP = 'Lead__c';
    private static final String STUDENT_LOOKUP = 'Student__c';
    private static final String CAND_LOOKUP   = 'Candidate__c';

    @AuraEnabled(cacheable=true)
    public static NavDataWrapper getNavData(Id recordId) {
        NavDataWrapper res = new NavDataWrapper();
        res.enquiry = new List<SourceCountWrapper>();
        res.webinar = new List<SourceCountWrapper>();
        res.events = new List<SourceCountWrapper>();
        res.latestSource = 'Sources';

        if (recordId == null) {
            System.debug(LoggingLevel.WARN, 'getNavData: recordId is null');
            return res;
        }

        String sObjName = recordId.getSObjectType().getDescribe().getName();
        Boolean isLead = (sObjName == 'Lead__c');
        Boolean isAccount = (sObjName == 'Account');
        Boolean isCandidate = (sObjName == 'Lead');

        if (!isLead && !isAccount && !isCandidate) {
            System.debug(LoggingLevel.WARN, 'getNavData: Unsupported sObjectType=' + sObjName + ', recordId=' + recordId);
            return res;
        }

        String lookupField;
        if (isCandidate) {
            lookupField = CAND_LOOKUP;
        } else if (isAccount) {
            lookupField = STUDENT_LOOKUP;
        } else {
            lookupField = LEAD_LOOKUP;
        }
        System.debug(LoggingLevel.INFO, 'getNavData: recordId=' + recordId + ', sObjName=' + sObjName + ', lookupField=' + lookupField);

        if (hasField(ENQUIRY_OBJECT, lookupField)) {
            res.enquiry = queryGroupedBySource(ENQUIRY_OBJECT, lookupField, recordId);
        }
        if (hasField(WEBINAR_OBJECT, lookupField)) {
            res.webinar = queryWebinarTotal(WEBINAR_OBJECT, lookupField, recordId);
        }
        res.events = queryEventsByMeetingType(recordId, isCandidate);

        Datetime latestDt;
        String latestSrc;

        for (SourceCountWrapper w : res.enquiry) {
            if (w != null && w.lastModified != null && (latestDt == null || w.lastModified > latestDt)) {
                latestDt = w.lastModified;
                latestSrc = w.source;
            }
        }
        for (SourceCountWrapper w : res.webinar) {
            if (w != null && w.lastModified != null && (latestDt == null || w.lastModified > latestDt)) {
                latestDt = w.lastModified;
                latestSrc = w.source;
            }
        }
        for (SourceCountWrapper w : res.events) {
            if (w != null && w.lastModified != null && (latestDt == null || w.lastModified > latestDt)) {
                latestDt = w.lastModified;
                latestSrc = w.source;
            }
        }

        if (!String.isBlank(latestSrc)) res.latestSource = latestSrc;

        System.debug(LoggingLevel.INFO, 'getNavData: latestSource=' + res.latestSource + ', enquiryTabs=' + res.enquiry.size() + ', webinarTabs=' + res.webinar.size());
        return res;
    }

    private static List<SourceCountWrapper> queryEventsByMeetingType(Id recordId, Boolean isCandidate) {
        List<SourceCountWrapper> outList = new List<SourceCountWrapper>();

        String parentField = isCandidate ? 'WhoId' : 'WhatId';
        String q =
            'SELECT Meeting_type__c, COUNT(Id), MAX(LastModifiedDate) ' +
            'FROM Event ' +
            'WHERE ' + parentField + ' = :recId ' +
            'AND Meeting_type__c != NULL ' +
            'AND Meeting_type__c != \'\' ' +
            'GROUP BY Meeting_type__c ' +
            'ORDER BY MAX(LastModifiedDate) DESC';

        Id recId = recordId;
        System.debug(LoggingLevel.DEBUG, 'queryEventsByMeetingType: ' + q);

        List<SObject> sobs = Database.query(q);
        for (SObject s : sobs) {
            AggregateResult ar = (AggregateResult) s;
            outList.add(new SourceCountWrapper(
                (String) ar.get('Meeting_type__c'),
                (Integer) ar.get('expr0'),
                (Datetime) ar.get('expr1')
            ));
        }

        System.debug(LoggingLevel.DEBUG, 'queryEventsByMeetingType: rows=' + outList.size());
        return outList;
    }

    private static List<SourceCountWrapper> queryGroupedBySource(String objectApiName, String lookupField, Id recordId) {
        List<SourceCountWrapper> outList = new List<SourceCountWrapper>();

        String q =
            'SELECT ' + SOURCE_FIELD + ', ' +
            'COUNT(Id), ' +
            'MAX(LastModifiedDate) ' +
            'FROM ' + objectApiName + ' ' +
            'WHERE ' + lookupField + ' = :recId ' +
            'AND ' + SOURCE_FIELD + ' != NULL ' +
            'AND ' + SOURCE_FIELD + ' != \'\' ' +
            'GROUP BY ' + SOURCE_FIELD + ' ' +
            'ORDER BY MAX(LastModifiedDate) DESC';

        Id recId = recordId;
        System.debug(LoggingLevel.DEBUG, 'queryGroupedBySource: ' + q);

        List<SObject> sobs = Database.query(q);
        List<AggregateResult> ars = new List<AggregateResult>();
        for (SObject s : sobs) ars.add((AggregateResult)s);

        for (AggregateResult ar : ars) {
            outList.add(new SourceCountWrapper(
                (String) ar.get(SOURCE_FIELD),
                (Integer) ar.get('expr0'),
                (Datetime) ar.get('expr1')
            ));
        }

        System.debug(LoggingLevel.DEBUG, 'queryGroupedBySource: object=' + objectApiName + ', rows=' + outList.size());
        return outList;
    }

    private static Boolean hasField(String objectApiName, String fieldApiName) {
        Map<String, Schema.SObjectType> globalMap = Schema.getGlobalDescribe();
        if (!globalMap.containsKey(objectApiName)) return false;

        Map<String, Schema.SObjectField> fieldMap =
            globalMap.get(objectApiName).getDescribe().fields.getMap();
        return fieldMap.containsKey(fieldApiName);
    }

    private static List<SourceCountWrapper> queryWebinarTotal(String objectApiName, String lookupField, Id recordId) {
        List<SourceCountWrapper> outList = new List<SourceCountWrapper>();

        String q =
            'SELECT COUNT(Id), MAX(LastModifiedDate) ' +
            'FROM ' + objectApiName + ' ' +
            'WHERE ' + lookupField + ' = :recId';

        Id recId = recordId;
        System.debug(LoggingLevel.DEBUG, 'queryWebinarTotal: ' + q);

        List<SObject> sobs = Database.query(q);
        AggregateResult ar = sobs.isEmpty() ? null : (AggregateResult)sobs[0];

        Integer total = ar == null ? 0 : (Integer) ar.get('expr0');
        Datetime lm = ar == null ? null : (Datetime) ar.get('expr1');

        if (total != null && total > 0) {
            outList.add(new SourceCountWrapper('Webinar', total, lm));
        }

        System.debug(LoggingLevel.DEBUG, 'queryWebinarTotal: object=' + objectApiName + ', total=' + total);
        return outList;
    }

    public class NavDataWrapper {
        @AuraEnabled public List<SourceCountWrapper> enquiry;
        @AuraEnabled public List<SourceCountWrapper> webinar;
        @AuraEnabled public List<SourceCountWrapper> events;
        @AuraEnabled public String latestSource;
    }

    public class SourceCountWrapper {
        @AuraEnabled public String source;
        @AuraEnabled public Integer count;
        @AuraEnabled public Datetime lastModified;

        public SourceCountWrapper(String source, Integer count, Datetime lastModified) {
            this.source = source;
            this.count = count;
            this.lastModified = lastModified;
        }
    }
}