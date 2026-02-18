/*
    Author       : ROHIT SINGH BISHT
    Description  : Fetch live webinar attendees (callout) and sync Webinar Members:
	            * - Present if email returned by API
                * - Absent if not returned by API
                * - Create Enquiry + Webinar Member for emails not found in Webinar Members
*/

public without sharing class WebinarLiveAttendanceSyncService {

    public class LiveAttendanceResponseDTO { public List<RegistrantDTO> registrants; }
    public class RegistrantDTO {
        public String participant_email;
        public String registrant_id;
        public String participant_name;
        public Decimal duration;
    }

    public static void enqueueSync(Set<Id> webinarRecordIds) {
        System.debug(LoggingLevel.INFO, 'WebinarLiveAttendanceSyncService.enqueueSync | webinarRecordIds size=' +
            (webinarRecordIds == null ? 0 : webinarRecordIds.size()));
        if (webinarRecordIds == null || webinarRecordIds.isEmpty()) return;

        syncFuture(new List<Id>(webinarRecordIds));
    }

    @future(callout=true)
    public static void syncFuture(List<Id> webinarRecordIds) {

        System.debug(LoggingLevel.INFO, 'syncFuture START | recordIds=' + webinarRecordIds);

        try {
            if (webinarRecordIds == null || webinarRecordIds.isEmpty()) {
                System.debug(LoggingLevel.WARN, 'syncFuture EXIT | empty webinarRecordIds');
                return;
            }

            List<Webinar__c> webinars = [
                SELECT Id, Webinar_Id__c
                FROM Webinar__c
                WHERE Id IN :webinarRecordIds AND Webinar_Id__c != null
            ];
            System.debug(LoggingLevel.INFO, 'syncFuture | webinars found=' + webinars.size());

            for (Webinar__c wbRec : webinars) {

                System.debug(LoggingLevel.INFO, '--- Processing Webinar__c | Id=' + wbRec.Id + ' | Webinar_Id__c=' + wbRec.Webinar_Id__c);

                if (String.isBlank(wbRec.Webinar_Id__c)) {
                    System.debug(LoggingLevel.WARN, 'Skip webinar | Webinar_Id__c blank | Id=' + wbRec.Id);
                    continue;
                }

                // 1) Call external API 
                String resBody;
                try {
                    System.debug(LoggingLevel.INFO, 'Callout start | webinarId=' + wbRec.Webinar_Id__c);
                    resBody = Callout_WebinarAttendee.getLiveWebinarAttendees(wbRec.Webinar_Id__c);
                    System.debug(LoggingLevel.INFO, 'Callout success | bodyLen=' + (resBody == null ? 0 : resBody.length()));
                } catch (Exception calloutEx) {
                    System.debug(LoggingLevel.ERROR, 'Callout failed | webinarId=' + wbRec.Webinar_Id__c + ' | err=' + calloutEx.getMessage());
                    continue;
                }

                // 2) Parse response
                LiveAttendanceResponseDTO input = parseResponse(resBody);
                Integer regCount = (input == null || input.registrants == null) ? 0 : input.registrants.size();
                System.debug(LoggingLevel.INFO, 'Parse result | registrants=' + regCount);

                if (regCount == 0) {
                    System.debug(LoggingLevel.WARN, 'No registrants in response | webinarId=' + wbRec.Webinar_Id__c);
                    continue;
                }

                // 3) Build email maps
                Set<String> emailSet = new Set<String>();
                Map<String, String> emailToRegistrantId = new Map<String, String>();
                Map<String, String> emailToRegistrantName = new Map<String, String>();
                Map<String, Decimal> emailToDuration = new Map<String, Decimal>();

                for (RegistrantDTO r : input.registrants) {
                    if (r == null || String.isBlank(r.participant_email)) continue;

                    String email = r.participant_email.trim().toLowerCase();
                    emailSet.add(email);
                    emailToRegistrantId.put(email, r.registrant_id);
                    emailToRegistrantName.put(email, r.participant_name);
                    if (r.duration != null) {
                        emailToDuration.put(email, r.duration);
                    }
                }

                System.debug(LoggingLevel.INFO, 'Emails collected | distinctEmails=' + emailSet.size());

                if (emailSet.isEmpty()) {
                    System.debug(LoggingLevel.WARN, 'No valid participant_email found after cleanup | webinarId=' + wbRec.Webinar_Id__c);
                    continue;
                }

                // 4) Load members (for present + absent)
                List<Webinar_Member__c> allMembers = [
                    SELECT Id, Webinar__c, Lead__c, Lead__r.Email__c, Registrant_Id__c, Attendance_Status__c
                    FROM Webinar_Member__c
                    WHERE Webinar__c = :wbRec.Id
                ];
                System.debug(LoggingLevel.INFO, 'Members loaded | totalMembers=' + allMembers.size());

                Map<String, Webinar_Member__c> emailToMember = new Map<String, Webinar_Member__c>();
                for (Webinar_Member__c wm : allMembers) {
                    if (wm.Lead__r != null && !String.isBlank(wm.Lead__r.Email__c)) {
                        emailToMember.put(wm.Lead__r.Email__c.trim().toLowerCase(), wm);
                    }
                }
                System.debug(LoggingLevel.INFO, 'Member email map built | mappedEmails=' + emailToMember.size());

                // 5) Prepare present updates + enquiry inserts + new webinar member inserts
                List<Webinar_Member__c> membersToUpdate = new List<Webinar_Member__c>();
                List<Enquiry__c> enquiriesToInsert = new List<Enquiry__c>();
                Map<String, Enquiry__c> emailToNewEnquiry = new Map<String, Enquiry__c>();
                Set<Id> memberIdsPresent = new Set<Id>();

                Integer presentCount = 0;
                Integer enquiryCount = 0;

                for (String email : emailSet) {
                    Webinar_Member__c wm = emailToMember.get(email);

                    if (wm != null) {
                        wm.Attendance_Status__c = 'Present';
                        wm.Registrant_Id__c = emailToRegistrantId.get(email);
                        if (emailToDuration.containsKey(email)) {
                            wm.Duration__c = emailToDuration.get(email);
                        }
                        membersToUpdate.add(wm);
                        memberIdsPresent.add(wm.Id);
                        presentCount++;
                    } else {
                        // Member not found => create enquiry (and later create webinar member tagged to enquiry)
                        Enquiry__c enq = new Enquiry__c();
                        enq.Email__c = email;
                        enq.Name = String.isBlank(emailToRegistrantName.get(email)) ? email : emailToRegistrantName.get(email);
                        enq.First_Name__c = emailToRegistrantName.get(email);

                        enquiriesToInsert.add(enq);
                        emailToNewEnquiry.put(email, enq);
                        enquiryCount++;
                    }
                }

                System.debug(LoggingLevel.INFO, 'Present computed | present=' + presentCount + ' | enquiryToCreate=' + enquiryCount);

                // 6) Mark absent for remaining members
                Integer absentMarked = 0;
                for (Webinar_Member__c wm : allMembers) {
                    if (wm == null) continue;

                    if (!memberIdsPresent.contains(wm.Id)) {
                        if (wm.Attendance_Status__c != 'Absent') {
                            wm.Attendance_Status__c = 'Absent';
                            membersToUpdate.add(wm);
                            absentMarked++;
                        }
                    }
                }
                System.debug(LoggingLevel.INFO, 'Absent computed | newlyAbsent=' + absentMarked);

                // 7) DML
                if (!membersToUpdate.isEmpty()) {
                    System.debug(LoggingLevel.INFO, 'Updating members | count=' + membersToUpdate.size());
                    update membersToUpdate;
                } else {
                    System.debug(LoggingLevel.INFO, 'No member updates required');
                }

                // Insert enquiries first (needed for tagging)
                if (!enquiriesToInsert.isEmpty()) {
                    System.debug(LoggingLevel.INFO, 'Inserting enquiries | count=' + enquiriesToInsert.size());
                    insert enquiriesToInsert;
                } else {
                    System.debug(LoggingLevel.INFO, 'No enquiries to insert');
                }

                // Create Webinar Members for newly created enquiries + tag them
                List<Webinar_Member__c> membersToInsert = new List<Webinar_Member__c>();
                if (!emailToNewEnquiry.isEmpty()) {
                    for (String email : emailToNewEnquiry.keySet()) {
                        Enquiry__c enqInserted = emailToNewEnquiry.get(email);
                        if (enqInserted == null || enqInserted.Id == null) continue;

                        Webinar_Member__c newWm = new Webinar_Member__c();
                        newWm.Webinar__c = wbRec.Id;
                        newWm.Attendance_Status__c = 'Present';
                        newWm.Registrant_Id__c = emailToRegistrantId.get(email);
                        if (emailToDuration.containsKey(email)) {
                            newWm.Duration__c = emailToDuration.get(email);
                        }

                        // Tag Webinar Member to Enquiry (update field API name if needed)
                        newWm.Enquiry__c = enqInserted.Id;

                        membersToInsert.add(newWm);
                    }
                }

                if (!membersToInsert.isEmpty()) {
                    System.debug(LoggingLevel.INFO, 'Inserting new Webinar Members (tagged to Enquiry) | count=' + membersToInsert.size());
                    insert membersToInsert;
                } else {
                    System.debug(LoggingLevel.INFO, 'No new Webinar Members to insert');
                }

                System.debug(LoggingLevel.INFO, '--- Webinar processed DONE | Id=' + wbRec.Id +
                    ' | presentEmails=' + emailSet.size() +
                    ' | membersUpdated=' + membersToUpdate.size() +
                    ' | enquiriesCreated=' + enquiriesToInsert.size() +
                    ' | membersInserted=' + membersToInsert.size() +
                    ' | absentMarked=' + absentMarked);
            }

            System.debug(LoggingLevel.INFO, 'syncFuture END');

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'syncFuture FATAL | err=' + e.getMessage() + ' | line=' + e.getLineNumber());
        }
    }

    public static LiveAttendanceResponseDTO parseResponse(String resBody) {
        if (String.isBlank(resBody)) return null;

        try {
            return (LiveAttendanceResponseDTO) JSON.deserialize(resBody, LiveAttendanceResponseDTO.class);
        } catch (Exception ex1) {
            System.debug(LoggingLevel.WARN, 'parseResponse typed failed | ' + ex1.getMessage());
            try {
                Map<String, Object> m = (Map<String, Object>) JSON.deserializeUntyped(resBody);
                if (m == null || !m.containsKey('registrants')) return null;

                List<Object> regs = (List<Object>) m.get('registrants');
                LiveAttendanceResponseDTO dto = new LiveAttendanceResponseDTO();
                dto.registrants = new List<RegistrantDTO>();

                if (regs != null) {
                    for (Object o : regs) {
                        Map<String, Object> rmap = (Map<String, Object>) o;
                        RegistrantDTO r = new RegistrantDTO();
                        r.participant_email = (String) rmap.get('participant_email');
                        r.registrant_id = (String) rmap.get('registrant_id');
                        r.participant_name = (String) rmap.get('participant_name');
                        r.duration = parseDecimal(rmap.get('duration'));
                        if (r.duration == null) {
                            r.duration = parseDecimal(rmap.get('participant_duration'));
                        }
                        dto.registrants.add(r);
                    }
                }
                return dto;
            } catch (Exception ex2) {
                System.debug(LoggingLevel.ERROR, 'parseResponse untyped failed | ' + ex2.getMessage());
                return null;
            }
        }
    }

    private static Decimal parseDecimal(Object value) {
        if (value == null) return null;
        try {
            if (value instanceof Decimal) return (Decimal) value;
            if (value instanceof Integer) return Decimal.valueOf(String.valueOf(value));
            if (value instanceof Long) return Decimal.valueOf(String.valueOf(value));
            if (value instanceof Double) return Decimal.valueOf(String.valueOf(value));
            return Decimal.valueOf(String.valueOf(value));
        } catch (Exception ex) {
            return null;
        }
    }
}