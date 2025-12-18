/**
 * Syncs webinar registrant attendees from HTTP service with existing Webinar Members
 * Creates Enquiry records for emails not found in Webinar Members
 * Author: Dheeraj Kumar
 * Updated: Based on response key "registrants" and field "participant_email"
 */
public without sharing class EnquiryCreationForZoomWebinar {

    private static final String ERROR_PREFIX = 'EnquiryCreationForZoomWebinar Error: ';

    @AuraEnabled
    public static EmailSyncResultDTO syncWebinarAttendeesAndCreateEnquiries(String webinarId) {
        try {
            if (String.isBlank(webinarId)) {
                throw new AuraHandledException('Webinar ID is required');
            }

            Id currentUserId = UserInfo.getUserId();

            // Step 1: Get live attendees from service
            String responseBody = Webservice_WebinarAttendee.getLiveWebinarAttendees(webinarId);

            // Step 2: Parse response => { "registrants": [ { participant_email, registrant_id }, ... ] }
            Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(responseBody);

            if (responseMap == null || !responseMap.containsKey('registrants')) {
                throw new AuraHandledException('Invalid response from webinar service: missing "registrants"');
            }

            List<Object> registrantsList = (List<Object>) responseMap.get('registrants');

            Set<String> liveAttendeeEmails = new Set<String>();

            for (Object rObj : registrantsList) {
                if (rObj == null) continue;

                Map<String, Object> r = (Map<String, Object>) rObj;
                String email = (r.containsKey('participant_email')) ? String.valueOf(r.get('participant_email')) : null;

                if (String.isNotBlank(email)) {
                    liveAttendeeEmails.add(email.toLowerCase().trim());
                }
            }

            // If no live attendees, return early
            if (liveAttendeeEmails.isEmpty()) {
                return new EmailSyncResultDTO(0, 0, 0, 0);
            }

            // Step 3: Query existing Webinar Members for current user's leads
            List<Webinar_Member__c> webinarMembers = [
                SELECT Id, Lead__c, Lead__r.Email__c
                FROM Webinar_Member__c
                WHERE Webinar__r.Webinar_Id__c = :webinarId
                  AND Lead__r.OwnerId = :currentUserId
                  AND Lead__r.Email__c != null
                  AND Webinar__r.IsActive__c = TRUE
            ];

            Set<String> existingEmails = new Set<String>();
            for (Webinar_Member__c member : webinarMembers) {
                String em = member.Lead__r != null ? member.Lead__r.Email__c : null;
                if (String.isNotBlank(em)) {
                    existingEmails.add(em.toLowerCase().trim());
                }
            }

            // Step 4: Extra emails = live - existing
            Set<String> extraEmails = new Set<String>();
            for (String liveEmail : liveAttendeeEmails) {
                if (!existingEmails.contains(liveEmail)) {
                    extraEmails.add(liveEmail);
                }
            }

            // Step 5: Create Enquiry records
            List<Enquiry__c> newEnquiries = new List<Enquiry__c>();
            for (String extraEmail : extraEmails) {
                Enquiry__c enq = new Enquiry__c();
                enq.Email__c = extraEmail;
                enq.Name = 'Webinar Enquiry - ' + extraEmail;

                // First name logic (safe)
                enq.First_Name__c = extraEmail.contains('@') ? extraEmail.substringBefore('@') : extraEmail;

                newEnquiries.add(enq);
            }

            Integer enquiriesCreated = 0;
            if (!newEnquiries.isEmpty()) {
                insert newEnquiries;
                enquiriesCreated = newEnquiries.size();
            }

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