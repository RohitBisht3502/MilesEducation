public without sharing class USPPathwayLeadService {
    @AuraEnabled
    public static Id createUSPPathwayLead(Id accountId) {
        if (accountId == null) {
            throw new AuraHandledException('Account Id is required.');
        }

        Id uspRecordTypeId = getLeadRecordTypeId('US Pathway');
        if (uspRecordTypeId == null) {
            throw new AuraHandledException('US Pathway record type not found.');
        }

        List<Lead__c> existingUsp = [SELECT Id FROM Lead__c WHERE Student__c = :accountId AND RecordTypeId = :uspRecordTypeId LIMIT 1];
        if (!existingUsp.isEmpty()) {
            throw new AuraHandledException('US Pathway lead already exists for this student.');
        }

        List<Lead__c> sourceLeads = [SELECT Id, Name, RecordTypeId, Stage__c FROM Lead__c WHERE Student__c = :accountId ORDER BY CreatedDate DESC LIMIT 1];
        if (sourceLeads.isEmpty()) {
            throw new AuraHandledException('No Lead found for this student.');
        }

        Lead__c newLead = sourceLeads[0].clone(false, true, false, false);
        newLead.Student__c = accountId;
        newLead.Name = sourceLeads[0].Name;
        newLead.RecordTypeId = uspRecordTypeId;
        newLead.Stage__c = 'U3';
        insert newLead;

        return newLead.Id;
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
}
