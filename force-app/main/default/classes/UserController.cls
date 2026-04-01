/**
* @File Name : UserController.cls
* @Author : Rohit
**/

public class UserController {
    public class MeetingRecordContext {
        @AuraEnabled public Id recordId;
        @AuraEnabled public String name;
        @AuraEnabled public String email;
        @AuraEnabled public String objectApiName;
        @AuraEnabled public List<String> availableCourses;
    }

    @AuraEnabled(cacheable=true)
    public static User getCurrentUserInfo() {
        return [SELECT Id, Name, Email, Title, SmallPhotoUrl, ManagerId, Manager.Name, Manager.Email, Manager.ManagerId, Manager.Manager.Name, Manager.Manager.Email FROM User WHERE Id = :UserInfo.getUserId()];
    }
    
    @AuraEnabled(cacheable=true)
    public static List<User> getAvailableUsers() {
        return [SELECT Id, Name, Email, Title, SmallPhotoUrl FROM User WHERE IsActive = true  AND Email != null  ORDER BY Name LIMIT 200];
    }

    @AuraEnabled(cacheable=true)
    public static MeetingRecordContext getMeetingRecordContext(Id recordId) {
        if (recordId == null) {
            throw new AuraHandledException('recordId is required.');
        }

        MeetingRecordContext context = new MeetingRecordContext();
        context.recordId = recordId;
        context.availableCourses = new List<String>();

        Schema.SObjectType sObjectType = recordId.getSObjectType();
        context.objectApiName = sObjectType.getDescribe().getName();

        if (sObjectType == Lead.SObjectType) {
            Lead leadRecord = [SELECT Id, Name, Email FROM Lead WHERE Id = :recordId LIMIT 1];
            context.name = leadRecord.Name;
            context.email = leadRecord.Email;
            context.availableCourses = getRelatedCoursesByCandidate(recordId);
            return context;
        }

        if (sObjectType == Account.SObjectType) {
            Account accountRecord = [SELECT Id, Name, Email__c FROM Account WHERE Id = :recordId LIMIT 1];
            context.name = accountRecord.Name;
            context.email = accountRecord.Email__c;
            context.availableCourses = getRelatedCoursesByStudent(recordId);
            return context;
        }

        throw new AuraHandledException('Unsupported record type for meeting scheduling: ' + context.objectApiName);
    }

    private static List<String> getRelatedCoursesByCandidate(Id candidateId) {
        List<Lead__c> relatedLeads = [
            SELECT Course__c
            FROM Lead__c
            WHERE Candidate__c = :candidateId
            AND Course__c != null
            ORDER BY CreatedDate DESC
        ];
        return extractCourses(relatedLeads);
    }

    private static List<String> getRelatedCoursesByStudent(Id studentId) {
        List<Lead__c> relatedLeads = [
            SELECT Course__c
            FROM Lead__c
            WHERE Student__c = :studentId
            AND Course__c != null
            ORDER BY CreatedDate DESC
        ];
        return extractCourses(relatedLeads);
    }

    private static List<String> extractCourses(List<Lead__c> relatedLeads) {
        List<String> orderedCourses = new List<String>();
        Set<String> seenCourses = new Set<String>();

        for (Lead__c leadRecord : relatedLeads) {
            String courseName = String.isBlank(leadRecord.Course__c) ? null : leadRecord.Course__c.trim();
            if (String.isBlank(courseName) || seenCourses.contains(courseName)) {
                continue;
            }
            seenCourses.add(courseName);
            orderedCourses.add(courseName);
        }

        return orderedCourses;
    }
}