public with sharing class TagLeadController {

    @AuraEnabled(cacheable=true)
    public static List<Lead__c> searchLeads(String keyword) {
        return [
            SELECT Id, Name, Email__c, Phone__c
            FROM Lead__c
            WHERE Name LIKE :('%' + keyword + '%')
                OR Phone__c LIKE :('%' + keyword + '%')
            LIMIT 10
        ];
    }

    @AuraEnabled
    public static void tagOrCreateLead(
        Id callLogId,
        Id leadId,
        String name,
        String course,
        String email,
        String phone,
        Boolean disableRR
    ) {
        Lead__c leadRecord;

        if (leadId != null) {
            leadRecord = [SELECT Id FROM Lead__c WHERE Id = :leadId LIMIT 1];
        } else {
            leadRecord = new Lead__c();
            leadRecord.Name = name;
            leadRecord.Course__c = course;
            leadRecord.Email__c = email;
            leadRecord.Phone__c = phone;
            leadRecord.Disable_Round_Robin__c = disableRR;
            insert leadRecord;
        }

        Call_Log__c log = [SELECT Id FROM Call_Log__c WHERE Id = :callLogId LIMIT 1];
        log.Lead__c = leadRecord.Id;
        update log;
    }
}