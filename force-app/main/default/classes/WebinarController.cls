public with sharing class WebinarController {

    @AuraEnabled(cacheable=true)
    public static List<WebinarDTO> getWebinarsByNameOnly() {
        List<WebinarDTO> out = new List<WebinarDTO>();
        for (Webinar__c w : [SELECT Id, Name,Webinar_Id__c FROM Webinar__c WHERE IsActive__c = TRUE ORDER BY Name ASC LIMIT 200 ]) {
            WebinarDTO d = new WebinarDTO();
            d.id        = w.Id;
            d.name      = w.Name;
            d.webinarId = w.Webinar_Id__c;
            out.add(d);
        }
        return out;
    }

    @AuraEnabled
    public static Id createWebinarMember(Id leadId, Id webinarId) {
        if (leadId == null || webinarId == null) {
            throw new AuraHandledException('Lead and Webinar are required.');
        }

        List<Webinar_Member__c> wmList = [Select id,Lead__c,Webinar__c from Webinar_Member__c where Lead__c = :leadId and Webinar__c = :webinarId limit 1];
        if (!wmList.isEmpty()) {
            throw new AuraHandledException('This lead is already registered for this webinar.');
        }
        
        return System.enqueueJob(new LeadZoomRegistrationJob(leadId, webinarId));
    }

    public class WebinarDTO {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String webinarId;
    }
}