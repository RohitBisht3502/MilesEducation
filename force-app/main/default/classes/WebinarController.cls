public with sharing class WebinarController {

    // Return only Id & Name
    @AuraEnabled(cacheable=true)
    public static List<WebinarDTO> getWebinarsByNameOnly() {
        List<WebinarDTO> out = new List<WebinarDTO>();
        for (Webinar__c w : [SELECT Id, Name FROM Webinar__c WHERE IsActive__c = TRUE ORDER BY Name ASC LIMIT 200 ]) {
            WebinarDTO d = new WebinarDTO();
            d.id = w.Id;
            d.name = w.Name;
            out.add(d);
        }
        return out;
    }

    // Create Webinar Member (Lead ↔ Webinar) with duplicate prevention
    // @AuraEnabled
    // public static Id createWebinarMember(Id leadId, Id webinarId) {
    //     if (leadId == null || webinarId == null) {
    //         throw new AuraHandledException('Lead and Webinar are required.');
    //     }

    //     // Prevent duplicate registration for same Lead + Webinar
    //     List<Webinar_Member__c> existing = [ SELECT Id FROM Webinar_Member__c WHERE Lead__c = :leadId AND Webinar__c = :webinarId  LIMIT 1];
    //     if (!existing.isEmpty()) {
    //         return existing[0].Id;
    //     }

    //     Webinar_Member__c wm = new Webinar_Member__c(
    //         Lead__c = leadId,
    //         Webinar__c = webinarId
    //     );
    //     insert wm;
    //     return wm.Id;
    // }
    
        @AuraEnabled
    public static Id createWebinarMember(Id leadId, Id webinarId) {
        if (leadId == null || webinarId == null) {
            throw new AuraHandledException('Lead and Webinar are required.');
        }
        // Enqueue async job (will call Zoom & upsert Webinar_Member__c with Meeting_Details__c)
        return System.enqueueJob(new LeadZoomRegistrationJob(leadId, webinarId));
    }

    // Minimal DTO
    public class WebinarDTO {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
    }
}