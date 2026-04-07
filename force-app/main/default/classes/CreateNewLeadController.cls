/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : CreateNewLeadController
 * Author          : Rohit Singh Bisht

 */

public without sharing class CreateNewLeadController {
    private static final List<String> SUPPORTED_COURSES = new List<String>{
        'CAIRA', 'US Pathway', 'CPA', 'CMA'
    };

    @AuraEnabled(cacheable=true)
    public static List<String> getAvailableCourseTypes(Id recordId) {
        ContextData contextData = getContextData(recordId);
        Set<String> existingCourses = new Set<String>(contextData.existingCourses);

        List<String> availableCourses = new List<String>();
        for (String course : SUPPORTED_COURSES) {
            if (!existingCourses.contains(course)) {
                availableCourses.add(course);
            }
        }
        return availableCourses;
    }

    @AuraEnabled
    public static Id createLead(Id recordId, String courseType) {
        if (String.isBlank(courseType)) {
            throw new AuraHandledException('Course type is required.');
        }

        ContextData contextData = getContextData(recordId);
        String normalizedCourse = normalizeCourse(courseType);
        if (String.isBlank(normalizedCourse)) {
            throw new AuraHandledException('Invalid course type selected.');
        }

        if (contextData.existingCourses.contains(normalizedCourse)) {
            throw new AuraHandledException(normalizedCourse + ' lead already exists for this record.');
        }

        Id leadRecordTypeId = getLeadRecordTypeId(normalizedCourse);
        if (leadRecordTypeId == null) {
            throw new AuraHandledException(normalizedCourse + ' record type not found.');
        }

        Lead__c sourceLead = contextData.sourceLead;
        Lead__c newLead = sourceLead.clone(false, true, false, false);
        newLead.Name = sourceLead.Name;
        newLead.RecordTypeId = leadRecordTypeId;
        newLead.Course__c = normalizedCourse;
        newLead.Stage__c = getDefaultStageForCourse(normalizedCourse);
        newLead.Student__c = contextData.studentId;
        newLead.Candidate__c = contextData.candidateId;
        newLead.Email__c = sourceLead.Email__c;
        newLead.Phone__c = sourceLead.Phone__c;
        insert newLead;

        return newLead.Id;
    }

    @AuraEnabled
    public static Id createUSPPathwayLead(Id accountId) {
        return createLead(accountId, 'US Pathway');
    }

    private static ContextData getContextData(Id recordId) {
        if (recordId == null) {
            throw new AuraHandledException('Record Id is required.');
        }

        Schema.SObjectType sObjectType = recordId.getSObjectType();
        if (sObjectType == Account.SObjectType) {
            return getStudentContext(recordId);
        }
        if (sObjectType == Lead.SObjectType) {
            return getCandidateContext(recordId);
        }
        if (sObjectType == Lead__c.SObjectType) {
            return getCustomLeadContext(recordId);
        }

        throw new AuraHandledException('This action is supported only on Student, Candidate, or Lead records.');
    }

    private static ContextData getStudentContext(Id studentId) {
        List<Lead__c> relatedLeads = [
            SELECT Id, Name, RecordTypeId, Course__c, Stage__c, Email__c, Phone__c, Candidate__c, Student__c, CreatedDate
            FROM Lead__c
            WHERE Student__c = :studentId
            ORDER BY CreatedDate DESC
        ];

        ContextData contextData = new ContextData();
        contextData.studentId = studentId;
        contextData.existingCourses = extractExistingCourses(relatedLeads);

        if (!relatedLeads.isEmpty()) {
            contextData.candidateId = relatedLeads[0].Candidate__c;
            contextData.sourceLead = relatedLeads[0];
            return contextData;
        }

        Account student = [
            SELECT Id, Name, Email__c, Phone
            FROM Account
            WHERE Id = :studentId
            LIMIT 1
        ];
        contextData.sourceLead = buildSourceLead(student.Name, student.Email__c, student.Phone, null, studentId);
        return contextData;
    }

    private static ContextData getCandidateContext(Id candidateId) {
        List<Lead__c> relatedLeads = [
            SELECT Id, Name, RecordTypeId, Course__c, Stage__c, Email__c, Phone__c, Candidate__c, Student__c, CreatedDate
            FROM Lead__c
            WHERE Candidate__c = :candidateId
            ORDER BY CreatedDate DESC
        ];

        ContextData contextData = new ContextData();
        contextData.candidateId = candidateId;
        contextData.existingCourses = extractExistingCourses(relatedLeads);

        if (!relatedLeads.isEmpty()) {
            contextData.studentId = relatedLeads[0].Student__c;
            contextData.sourceLead = relatedLeads[0];
            return contextData;
        }

        Lead candidate = [
            SELECT Id, Name, Email, Phone
            FROM Lead
            WHERE Id = :candidateId
            LIMIT 1
        ];
        contextData.sourceLead = buildSourceLead(candidate.Name, candidate.Email, candidate.Phone, candidateId, null);
        return contextData;
    }

    private static ContextData getCustomLeadContext(Id leadId) {
        Lead__c sourceLead = [
            SELECT Id, Name, RecordTypeId, Course__c, Stage__c, Email__c, Phone__c, Candidate__c, Student__c, CreatedDate
            FROM Lead__c
            WHERE Id = :leadId
            LIMIT 1
        ];

        List<Lead__c> relatedLeads;
        if (sourceLead.Student__c != null && sourceLead.Candidate__c != null) {
            relatedLeads = [
                SELECT Id, Course__c
                FROM Lead__c
                WHERE Student__c = :sourceLead.Student__c OR Candidate__c = :sourceLead.Candidate__c
            ];
        } else if (sourceLead.Student__c != null) {
            relatedLeads = [
                SELECT Id, Course__c
                FROM Lead__c
                WHERE Student__c = :sourceLead.Student__c
            ];
        } else if (sourceLead.Candidate__c != null) {
            relatedLeads = [
                SELECT Id, Course__c
                FROM Lead__c
                WHERE Candidate__c = :sourceLead.Candidate__c
            ];
        } else {
            relatedLeads = new List<Lead__c>{ sourceLead };
        }

        ContextData contextData = new ContextData();
        contextData.studentId = sourceLead.Student__c;
        contextData.candidateId = sourceLead.Candidate__c;
        contextData.sourceLead = sourceLead;
        contextData.existingCourses = extractExistingCourses(relatedLeads);
        return contextData;
    }

    private static Set<String> extractExistingCourses(List<Lead__c> leads) {
        Set<String> existingCourses = new Set<String>();
        for (Lead__c leadRec : leads) {
            String normalizedCourse = normalizeCourse(leadRec.Course__c);
            if (!String.isBlank(normalizedCourse)) {
                existingCourses.add(normalizedCourse);
            }
        }
        return existingCourses;
    }

    private static String normalizeCourse(String courseType) {
        if (String.isBlank(courseType)) return null;
        String courseKey = courseType.trim().toUpperCase();
        if (courseKey.contains('US PATHWAY')) return 'US Pathway';
        if (courseKey.contains('CPA')) return 'CPA';
        if (courseKey.contains('CMA')) return 'CMA';
        if (courseKey.contains('CAIRA')) return 'CAIRA';
        return null;
    }

    private static Id getLeadRecordTypeId(String recordTypeName) {
        if (String.isBlank(recordTypeName)) return null;
        Map<String, Schema.RecordTypeInfo> rtByName =
            Schema.SObjectType.Lead__c.getRecordTypeInfosByName();
        if (rtByName != null && rtByName.containsKey(recordTypeName)) {
            return rtByName.get(recordTypeName).getRecordTypeId();
        }
        return null;
    }

    private static String getDefaultStageForCourse(String course) {
        String courseKey = normalizeCourse(course);
        if (courseKey == 'US Pathway') return 'U3';
        if (courseKey == 'CPA' || courseKey == 'CMA' || courseKey == 'CAIRA') return 'M3';
        return null;
    }

    private static Lead__c buildSourceLead(String name, String email, String phone, Id candidateId, Id studentId) {
        Lead__c sourceLead = new Lead__c();
        sourceLead.Name = String.isBlank(name) ? 'New Lead' : name;
        sourceLead.Email__c = email;
        sourceLead.Phone__c = phone;
        sourceLead.Candidate__c = candidateId;
        sourceLead.Student__c = studentId;
        return sourceLead;
    }

    private class ContextData {
        Id studentId;
        Id candidateId;
        Lead__c sourceLead;
        Set<String> existingCourses = new Set<String>();
    }
}