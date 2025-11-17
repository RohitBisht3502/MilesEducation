public with sharing class RunoCallIdentityService {
    public class IdentityDTO {
        @AuraEnabled public String name;
        @AuraEnabled public String email;
        @AuraEnabled public String phone;
        @AuraEnabled public String city;
        @AuraEnabled public String source;
    }

    @AuraEnabled(cacheable=true)
    public static IdentityDTO getIdentity(Id recordId) {
        System.debug('recordId >>>> '+recordId);
        if (recordId == null) return null;

        Lead l = [ SELECT Id, Name, FirstName, LastName, Email, Phone, MobilePhone, City, LeadSource FROM Lead WHERE Id = :recordId LIMIT 1];

        IdentityDTO dto = new IdentityDTO();
        dto.name = (l.FirstName != null ? l.FirstName + ' ' : '') + (l.LastName != null ? l.LastName : '');
        if (String.isBlank(dto.name)) dto.name = l.Name;

        dto.email  = l.Email;
        dto.phone  = l.MobilePhone != null ? l.MobilePhone : l.Phone;
        dto.city   = l.City;
        dto.source = l.LeadSource;
		System.debug(dto);
        return dto;
		
    }
}