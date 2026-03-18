public without sharing class SobjectNavBarController {

    private static final String SOURCE_CAIRA_WEBINAR = 'CAIRA Webinar';
    private static final String SOURCE_ZOOM_WEBINAR = 'Zoom Webinar';

    @AuraEnabled(cacheable=true)
    public static NavDataWrapper getNavData(Id recordId) {
        NavDataWrapper res = new NavDataWrapper();
        res.enquiry = new List<SourceCountWrapper>();
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

        System.debug(LoggingLevel.INFO, 'getNavData: recordId=' + recordId + ', sObjName=' + sObjName);

        Map<String, SourceCountWrapper> sourceMap = new Map<String, SourceCountWrapper>();

        if (isLead) {
            mergeCounts(sourceMap, getEnquirySourcesByLead(recordId));
            mergeCounts(sourceMap, getEventSources(recordId));
            mergeCounts(sourceMap, getWebinarSourcesByLead(recordId));
        } else if (isAccount) {
            mergeCounts(sourceMap, getEnquirySourcesByStudent(recordId));
            mergeCounts(sourceMap, getEventSources(recordId));
            mergeCounts(sourceMap, getWebinarSourcesByStudent(recordId));
        } else if (isCandidate) {
            mergeCounts(sourceMap, getEnquirySourcesByCandidate(recordId));
            mergeCounts(sourceMap, getEventSources(recordId));
            mergeCounts(sourceMap, getWebinarSourcesByCandidate(recordId));
        }

        res.enquiry = sourceMap.values();
        res.enquiry.sort();

        Datetime latestDt;
        String latestSrc;

        for (SourceCountWrapper w : res.enquiry) {
            if (w != null && w.lastModified != null && (latestDt == null || w.lastModified > latestDt)) {
                latestDt = w.lastModified;
                latestSrc = w.source;
            }
        }

        if (!String.isBlank(latestSrc)) res.latestSource = latestSrc;

        System.debug(LoggingLevel.INFO, 'getNavData: latestSource=' + res.latestSource + ', enquiryTabs=' + res.enquiry.size());
        return res;
    }

    private static List<SourceCountWrapper> getEnquirySourcesByLead(Id recordId) {
        List<SourceCountWrapper> outList = new List<SourceCountWrapper>();
        for (AggregateResult ar : [
            SELECT Coming_From__c source, COUNT(Id) recordCount, MAX(LastModifiedDate) latestDt
            FROM Enquiry__c
            WHERE Lead__c = :recordId AND Coming_From__c != null AND Coming_From__c != ''
            GROUP BY Coming_From__c
            ORDER BY MAX(LastModifiedDate) DESC
        ]) {
            outList.add(new SourceCountWrapper((String) ar.get('source'), (Integer) ar.get('recordCount'), (Datetime) ar.get('latestDt')));
        }
        return outList;
    }

    private static List<SourceCountWrapper> getEnquirySourcesByStudent(Id recordId) {
        List<SourceCountWrapper> outList = new List<SourceCountWrapper>();
        for (AggregateResult ar : [
            SELECT Coming_From__c source, COUNT(Id) recordCount, MAX(LastModifiedDate) latestDt
            FROM Enquiry__c
            WHERE Student__c = :recordId AND Coming_From__c != null AND Coming_From__c != ''
            GROUP BY Coming_From__c
            ORDER BY MAX(LastModifiedDate) DESC
        ]) {
            outList.add(new SourceCountWrapper((String) ar.get('source'), (Integer) ar.get('recordCount'), (Datetime) ar.get('latestDt')));
        }
        return outList;
    }

    private static List<SourceCountWrapper> getEnquirySourcesByCandidate(Id recordId) {
        List<SourceCountWrapper> outList = new List<SourceCountWrapper>();
        for (AggregateResult ar : [
            SELECT Coming_From__c source, COUNT(Id) recordCount, MAX(LastModifiedDate) latestDt
            FROM Enquiry__c
            WHERE Candidate__c = :recordId AND Coming_From__c != null AND Coming_From__c != ''
            GROUP BY Coming_From__c
            ORDER BY MAX(LastModifiedDate) DESC
        ]) {
            outList.add(new SourceCountWrapper((String) ar.get('source'), (Integer) ar.get('recordCount'), (Datetime) ar.get('latestDt')));
        }
        return outList;
    }

    private static List<SourceCountWrapper> getEventSources(Id recordId) {
        List<SourceCountWrapper> outList = new List<SourceCountWrapper>();
        for (AggregateResult ar : [
            SELECT Meeting_type__c source, COUNT(Id) recordCount, MAX(LastModifiedDate) latestDt
            FROM Event
            WHERE (WhoId = :recordId OR WhatId = :recordId) AND Meeting_type__c != null AND Meeting_type__c != '' AND Stage__c = 'Completed'
            GROUP BY Meeting_type__c
            ORDER BY MAX(LastModifiedDate) DESC
        ]) {
            outList.add(new SourceCountWrapper((String) ar.get('source'), (Integer) ar.get('recordCount'), (Datetime) ar.get('latestDt')));
        }
        return outList;
    }

    private static List<SourceCountWrapper> getWebinarSourcesByLead(Id recordId) {
        List<SourceCountWrapper> outList = new List<SourceCountWrapper>();
        for (AggregateResult ar : [
            SELECT Webinar__r.Type_Of_Webinar__c webinarType, COUNT(Id) recordCount, MAX(LastModifiedDate) latestDt
            FROM Webinar_Member__c
            WHERE Lead__c = :recordId AND Webinar__c != null AND Attendance_Status__c = 'Present'
            GROUP BY Webinar__r.Type_Of_Webinar__c
            ORDER BY MAX(LastModifiedDate) DESC
        ]) {
            outList.add(new SourceCountWrapper(getWebinarSourceLabel((String) ar.get('webinarType')), (Integer) ar.get('recordCount'), (Datetime) ar.get('latestDt')));
        }
        return outList;
    }

    private static List<SourceCountWrapper> getWebinarSourcesByStudent(Id recordId) {
        List<SourceCountWrapper> outList = new List<SourceCountWrapper>();
        for (AggregateResult ar : [
            SELECT Webinar__r.Type_Of_Webinar__c webinarType, COUNT(Id) recordCount, MAX(LastModifiedDate) latestDt
            FROM Webinar_Member__c
            WHERE Student__c = :recordId AND Webinar__c != null AND Attendance_Status__c = 'Present'
            GROUP BY Webinar__r.Type_Of_Webinar__c
            ORDER BY MAX(LastModifiedDate) DESC
        ]) {
            outList.add(new SourceCountWrapper(getWebinarSourceLabel((String) ar.get('webinarType')), (Integer) ar.get('recordCount'), (Datetime) ar.get('latestDt')));
        }
        return outList;
    }

    private static List<SourceCountWrapper> getWebinarSourcesByCandidate(Id recordId) {
        List<SourceCountWrapper> outList = new List<SourceCountWrapper>();
        for (AggregateResult ar : [
            SELECT Webinar__r.Type_Of_Webinar__c webinarType, COUNT(Id) recordCount, MAX(LastModifiedDate) latestDt
            FROM Webinar_Member__c
            WHERE Candidate__c = :recordId AND Webinar__c != null AND Attendance_Status__c = 'Present'
            GROUP BY Webinar__r.Type_Of_Webinar__c
            ORDER BY MAX(LastModifiedDate) DESC
        ]) {
            outList.add(new SourceCountWrapper(getWebinarSourceLabel((String) ar.get('webinarType')), (Integer) ar.get('recordCount'), (Datetime) ar.get('latestDt')));
        }
        return outList;
    }

    private static void mergeCounts(Map<String, SourceCountWrapper> sourceMap, List<SourceCountWrapper> items) {
        for (SourceCountWrapper item : items) {
            if (item == null || String.isBlank(item.source)) {
                continue;
            }

            if (!sourceMap.containsKey(item.source)) {
                sourceMap.put(item.source, new SourceCountWrapper(item.source, item.count, item.lastModified));
                continue;
            }

            SourceCountWrapper existing = sourceMap.get(item.source);
            existing.count += item.count == null ? 0 : item.count;
            if (item.lastModified != null && (existing.lastModified == null || item.lastModified > existing.lastModified)) {
                existing.lastModified = item.lastModified;
            }
        }
    }

    private static String getWebinarSourceLabel(String webinarType) {
        return webinarType != null && webinarType.trim().equalsIgnoreCase('CAIRA')
            ? SOURCE_CAIRA_WEBINAR
            : SOURCE_ZOOM_WEBINAR;
    }

    public class NavDataWrapper {
        @AuraEnabled public List<SourceCountWrapper> enquiry;
        @AuraEnabled public String latestSource;
    }

    public class SourceCountWrapper implements Comparable {
        @AuraEnabled public String source;
        @AuraEnabled public Integer count;
        @AuraEnabled public Datetime lastModified;

        public SourceCountWrapper(String source, Integer count, Datetime lastModified) {
            this.source = source;
            this.count = count;
            this.lastModified = lastModified;
        }

        public Integer compareTo(Object obj) {
            SourceCountWrapper other = (SourceCountWrapper) obj;
            if (other == null) return -1;
            if (this.lastModified == other.lastModified) return 0;
            if (this.lastModified == null) return 1;
            if (other.lastModified == null) return -1;
            return this.lastModified > other.lastModified ? -1 : 1;
        }
    }
}