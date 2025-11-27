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
        System.debug('recordId >>>> '+recordId);
        if (recordId == null) return null;

        Lead__c l = [ SELECT Id, Name, Email__c, Phone__c, City__c, Course__c, Stage__c  FROM Lead__c WHERE Id = :recordId LIMIT 1];

        IdentityDTO dto = new IdentityDTO();
        dto.name = l.Name;
        dto.email  = l.Email__c;
        dto.phone  = l.Phone__c;
        dto.city   = l.City__c;
        dto.source = l.Course__c;
        dto.stage = l.Stage__c;
        System.debug(dto);
        return dto;
    }
}