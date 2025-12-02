// file: RunoCallIdentityService.cls
public without sharing  class RunoCallIdentityService {
    public class IdentityDTO {
        @AuraEnabled public String name;
        @AuraEnabled public String email;
        @AuraEnabled public String phone;
        @AuraEnabled public String city;
        @AuraEnabled public String source;
         @AuraEnabled public String stage;
    }

    @AuraEnabled(cacheable=true)
    public static IdentityDTO getIdentity(Id recordId) {
        System.debug('RunoCallIdentityService.getIdentity recordId >>> ' + recordId);
        if (recordId == null) return null;

        SObjectType sObjType = recordId.getSObjectType();

        if (sObjType == Lead__c.SObjectType) {
            Lead__c l = [ SELECT Id, Name, Email__c, Phone__c, City__c, Course__c, Stage__c FROM Lead__c WHERE Id = :recordId LIMIT 1];

            IdentityDTO dto = new IdentityDTO();
            dto.name   = l.Name;
            dto.email  = l.Email__c;
            dto.phone  = l.Phone__c;
            dto.city   = l.City__c;
            dto.source = l.Course__c;
            dto.stage  = l.Stage__c;
            System.debug('RunoCallIdentityService.getIdentity DTO (Lead) = ' + dto);
            return dto;
        }

        if (sObjType == Call_Log__c.SObjectType) {
            Call_Log__c cl = [SELECT Id, Customer_Name__c, Phone_Number__c FROM Call_Log__c WHERE Id = :recordId LIMIT 1 ];

            IdentityDTO dto = new IdentityDTO();
            dto.name   = cl.Customer_Name__c;
            dto.email  = 'NA';
            dto.phone  = cl.Phone_Number__c;
            dto.city   = 'NA';
            dto.source = 'NA';
            dto.stage  = 'NA';
            System.debug('RunoCallIdentityService.getIdentity DTO (Call_Log__c) = ' + dto);
            return dto;
        }

        return null;
    }
}