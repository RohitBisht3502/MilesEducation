/**
    * Syncs webinar attendees from HTTP service with existing Webinar Members
    * Creates Enquiry records for emails not found in Webinar Members
    * Author: Dheeraj Kumar
    * @param webinarId - The Webinar ID to sync
    * @return EmailSyncResultDTO with sync statistics
    */


public without sharing class EnquiryCreationForZoomWebinar {
    
    private static final String ERROR_PREFIX = 'EnquiryCreationForZoomWebinar Error: ';

    @AuraEnabled
    public static EmailSyncResultDTO syncWebinarAttendeesAndCreateEnquiries(String webinarId) {
        try {
            // Validate input
            if (String.isBlank(webinarId)) {
                throw new AuraHandledException('Webinar ID is required');
            }
            
            Id currentUserId = UserInfo.getUserId();
            
            // Step 1: Get live attendee emails from HTTP service
            String responseBody = Webservice_WebinarAttendee.getLiveWebinarAttendees(webinarId);
            
            // Parse JSON response
            Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
            
            if (responseMap == null || !responseMap.containsKey('attendees')) {
                throw new AuraHandledException('Invalid response from webinar service');
            }
            
            List<Object> attendeesList = (List<Object>) responseMap.get('attendees');
            Set<String> liveAttendeeEmails = new Set<String>();
            
            // Normalize emails to lowercase for comparison
            for (Object emailObj : attendeesList) {
                String email = String.valueOf(emailObj).toLowerCase().trim();
                if (String.isNotBlank(email)) {
                    liveAttendeeEmails.add(email);
                }
            }
            
            // Step 2: Query existing Webinar Members for current user's leads
            List<Webinar_Member__c> webinarMembers = [
                SELECT Id, Lead__c, Lead__r.Email__c
                FROM Webinar_Member__c
                WHERE Webinar__r.Webinar_Id__c = :webinarId
                AND Lead__r.OwnerId = :currentUserId
                AND Lead__r.Email__c != null
                AND Webinar__r.IsActive__c = TRUE
            ];
            
            // Collect existing emails (normalize to lowercase)
            Set<String> existingEmails = new Set<String>();
            for (Webinar_Member__c member : webinarMembers) {
                if (String.isNotBlank(member.Lead__r.Email__c)) {
                    existingEmails.add(member.Lead__r.Email__c.toLowerCase().trim());
                }
            }
            
            // Step 3: Find extra emails (present in live attendees but not in webinar members)
            Set<String> extraEmails = new Set<String>();
            for (String liveEmail : liveAttendeeEmails) {
                if (!existingEmails.contains(liveEmail)) {
                    extraEmails.add(liveEmail);
                }
            }
            
            // Step 4: Create Enquiry records for extra emails
            List<Enquiry__c> newEnquiries = new List<Enquiry__c>();
            for (String extraEmail : extraEmails) {
                Enquiry__c enq = new Enquiry__c();
                enq.Email__c = extraEmail;
                enq.Name = 'Webinar Enquiry - ' + extraEmail;
                enq.First_Name__c = extraEmail.contains('@') ? extraEmail.substringBefore('@') : extraEmail;
                newEnquiries.add(enq);
            }
            
            // Insert new enquiries
            Integer enquiriesCreated = 0;
            if (!newEnquiries.isEmpty()) {
                insert newEnquiries;
                enquiriesCreated = newEnquiries.size();
            }
            
            // Return result
            return new EmailSyncResultDTO(
                liveAttendeeEmails.size(),
                existingEmails.size(),
                extraEmails.size(),
                enquiriesCreated
            );
            
        } catch (Exception e) {
            logError('syncWebinarAttendeesAndCreateEnquiries failed', e);
            throw new AuraHandledException(ERROR_PREFIX + e.getMessage());
        }
    }


    private static void logError(String context, Exception e) {
        System.debug(LoggingLevel.ERROR, context + ' → ' + e.getMessage());
        System.debug(LoggingLevel.ERROR, e.getStackTraceString());
    }

    /**
     * DTO class for email sync results
     */
    public class EmailSyncResultDTO {
        @AuraEnabled public Integer totalLiveAttendees { get; private set; }
        @AuraEnabled public Integer matchedWithMembers { get; private set; }
        @AuraEnabled public Integer extraEmailsFound { get; private set; }
        @AuraEnabled public Integer enquiriesCreated { get; private set; }
        
        public EmailSyncResultDTO(Integer total, Integer matched, Integer extra, Integer created) {
            this.totalLiveAttendees = total;
            this.matchedWithMembers = matched;
            this.extraEmailsFound = extra;
            this.enquiriesCreated = created;
        }
    }
}




// EnquiryCreationForZoomWebinar.syncWebinarAttendeesAndCreateEnquiries('WEBINAR12345');