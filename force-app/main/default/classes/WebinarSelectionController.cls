public with sharing class WebinarSelectionController {
    
    /**
     * Wrapper class to return unique webinars with member details
     */
    public class WebinarOption {
        @AuraEnabled public Id webinarId;
        @AuraEnabled public String webinarName;
        @AuraEnabled public String topic;
        @AuraEnabled public DateTime startDateTime;
        @AuraEnabled public DateTime endDateTime;
        @AuraEnabled public String webinarIdExternal;
        @AuraEnabled public Id webinarMemberId;
        @AuraEnabled public String registrantId;
    }
    
    /**
     * Fetches unique Webinars for a Lead through Webinar_Member__c records
     * @param leadId - The ID of the Lead__c record
     * @return List of unique WebinarOption wrappers
     */
    @AuraEnabled(cacheable=true)
    public static List<WebinarOption> getWebinarsForLead(Id leadId) {
        try {
            // Query all Webinar_Member records for this Lead
            List<Webinar_Member__c> webinarMembers = [
                SELECT 
                    Id,
                    Name,
                    Registrant_Id__c,
                    Webinar__c,
                    Webinar__r.Id,
                    Webinar__r.Name,
                    Webinar__r.Topic__c,
                    Webinar__r.Start_Date_Time__c,
                    Webinar__r.End_Date_Time__c,
                    Webinar__r.Webinar_Id__c,
                    Lead__c,
                    CreatedDate
                FROM Webinar_Member__c
                WHERE Lead__c = :leadId
                    AND Registrant_Id__c != null
                    AND Webinar__c != null
                ORDER BY CreatedDate DESC
            ];
            
            // Use a Set to track unique Webinar IDs
            Set<Id> uniqueWebinarIds = new Set<Id>();
            List<WebinarOption> webinarOptions = new List<WebinarOption>();
            
            // Build unique webinar list
            for (Webinar_Member__c wm : webinarMembers) {
                // Only add if we haven't seen this webinar before
                if (!uniqueWebinarIds.contains(wm.Webinar__c)) {
                    uniqueWebinarIds.add(wm.Webinar__c);
                    
                    WebinarOption option = new WebinarOption();
                    option.webinarId = wm.Webinar__r.Id;
                    option.webinarName = wm.Webinar__r.Name;
                    option.topic = wm.Webinar__r.Topic__c;
                    option.startDateTime = wm.Webinar__r.Start_Date_Time__c;
                    option.endDateTime = wm.Webinar__r.End_Date_Time__c;
                    option.webinarIdExternal = wm.Webinar__r.Webinar_Id__c;
                    option.webinarMemberId = wm.Id;
                    option.registrantId = wm.Registrant_Id__c;
                    
                    webinarOptions.add(option);
                }
            }
            
            return webinarOptions;
            
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching webinars for lead: ' + e.getMessage());
        }
    }
    
    /**
     * Legacy method - keeping for backward compatibility
     * Fetches all Webinar_Member__c records related to a Lead
     * @param leadId - The ID of the Lead__c record
     * @return List of Webinar_Member__c records with related Webinar details
     */
    @AuraEnabled(cacheable=true)
    public static List<Webinar_Member__c> getWebinarMembers(Id leadId) {
        try {
            return [
                SELECT 
                    Id,
                    Name,
                    Registrant_Id__c,
                    // Status__c,
                    Webinar__c,
                    Webinar__r.Name,
                    Webinar__r.Topic__c,
                    Webinar__r.Start_Date_Time__c,
                    Webinar__r.End_Date_Time__c,
                    Webinar__r.Webinar_Id__c,
                    Lead__c,
                    Lead_Owner_at_Registration__c,
                    Lead_Stage_at_Registration__c,
                    CreatedDate
                FROM Webinar_Member__c
                WHERE Lead__c = :leadId
                    AND Registrant_Id__c != null
                    AND Webinar__c != null
                ORDER BY CreatedDate DESC
            ];
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching webinar members: ' + e.getMessage());
        }
    }
}