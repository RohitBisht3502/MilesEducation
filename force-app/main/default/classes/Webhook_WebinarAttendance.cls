/**
*   Author : Rohit Singh Bisht
*   Purpose: Client webhook to push webinar attendance/registrants to Salesforce
**/
@RestResource(urlMapping='/webinar/attendance')
global without sharing class Webhook_WebinarAttendance {

    global class RegistrantDTO {
        public String participant_email;
        public String registrant_id;
        public String participant_name; 
    }

    global class AttendanceRequestDTO {
        public String webinarId;
        public List<RegistrantDTO> registrants;
    }

    global class AttendanceResponseDTO {
        public Boolean success;
        public String message;
    }

    @HttpPost
    global static AttendanceResponseDTO consumeAttendance() {
        AttendanceResponseDTO resp = new AttendanceResponseDTO();

        RestRequest req = RestContext.request;
        String serviceName = 'Webhook Webinar Attendance';
        String requestPayload = truncate(req != null && req.requestBody != null ? req.requestBody.toString() : null);

        if (req == null || req.requestBody == null || String.isBlank(req.requestBody.toString())) {
            resp.success = false;
            resp.message = 'Empty request body';
            IntegrationLogUtil.insertLog(serviceName, requestPayload, null, resp.message, 'Failed', 400);
            return resp;
        }

        AttendanceRequestDTO input;
        try {
            input = (AttendanceRequestDTO) JSON.deserialize(req.requestBody.toString(), AttendanceRequestDTO.class);
        } catch (Exception e) {
            resp.success = false;
            resp.message = 'Invalid JSON: ' + e.getMessage();
            IntegrationLogUtil.insertLog(serviceName, requestPayload, null, resp.message, 'Failed', 400);
            return resp;
        }

        if (input == null || String.isBlank(input.webinarId)) {
            resp.success = false;
            resp.message = 'webinarId is required';
            IntegrationLogUtil.insertLog(serviceName, requestPayload, null, resp.message, 'Failed', 400);
            return resp;
        }

        if (input.registrants == null || input.registrants.isEmpty()) {
            resp.success = false;
            resp.message = 'registrants list is required';
            IntegrationLogUtil.insertLog(serviceName, requestPayload, null, resp.message, 'Failed', 400);
            return resp;
        }

        try {
            // 1) Get Webinar
            Webinar__c wb = [
                SELECT Id, Webinar_Id__c
                FROM Webinar__c
                WHERE Webinar_Id__c = :input.webinarId
                LIMIT 1
            ];

            // 2) Collect emails from payload
            Set<String> emailSet = new Set<String>();
            Map<String, String> emailToRegistrantId = new Map<String, String>();
            Map<String, String> emailToRegistrantName = new Map<String, String>(); 

            for (RegistrantDTO r : input.registrants) {
                if (r == null || String.isBlank(r.participant_email)) {
                    continue;
                }

                String email = r.participant_email.trim().toLowerCase();
                emailSet.add(email);

                // keep latest values if duplicates come
                emailToRegistrantId.put(email, r.registrant_id);
                emailToRegistrantName.put(email, r.participant_name);
            }

            if (emailSet.isEmpty()) {
                resp.success = false;
                resp.message = 'No valid participant_email found in registrants';
                IntegrationLogUtil.insertLog(serviceName, requestPayload, null, resp.message, 'Failed', 400);
                return resp;
            }

            // 3) Fetch Webinar Members for that webinar + those emails
            List<Webinar_Member__c> webinarMembers = [
                SELECT Id, Webinar__c, Lead__c, Lead__r.Email__c, Registrant_Id__c, Attendance_Status__c
                FROM Webinar_Member__c
                WHERE Webinar__c = :wb.Id
                AND Lead__r.Email__c != null
                AND Lead__r.Email__c IN :emailSet
            ];

            Map<String, Webinar_Member__c> emailToMember = new Map<String, Webinar_Member__c>();
            for (Webinar_Member__c wm : webinarMembers) {
                if (wm.Lead__r != null && !String.isBlank(wm.Lead__r.Email__c)) {
                    emailToMember.put(wm.Lead__r.Email__c.trim().toLowerCase(), wm);
                }
            }

            // 4) Prepare updates + enquiries for missing members
            List<Webinar_Member__c> membersToUpdate = new List<Webinar_Member__c>();
            List<Enquiry__c> enquiriesToInsert = new List<Enquiry__c>();

            for (String email : emailSet) {
                Webinar_Member__c wm = emailToMember.get(email);

                if (wm != null) {
                    wm.Attendance_Status__c = 'Present';
                    wm.Registrant_Id__c = emailToRegistrantId.get(email);
                    membersToUpdate.add(wm);
                } else {
                    // Member not found => create enquiry
                    Enquiry__c enq = new Enquiry__c();
                    enq.Email__c = email;
                    enq.Name = emailToRegistrantName.get(email);
                    enq.First_Name__c = emailToRegistrantName.get(email);
                    enquiriesToInsert.add(enq);
                }
            }

            if (!membersToUpdate.isEmpty()) {
                update membersToUpdate;
            }

            if (!enquiriesToInsert.isEmpty()) {
                insert enquiriesToInsert;
            }

            resp.success = true;
            resp.message = 'Processed successfully';
            IntegrationLogUtil.insertLog(serviceName, requestPayload, truncate(JSON.serialize(resp)), resp.message, 'Success', 200);

        } catch (QueryException qe) {
            resp.success = false;
            resp.message = 'Webinar not found for Id: ' + String.valueOf(input.webinarId);
            IntegrationLogUtil.insertLog(serviceName, requestPayload, null, resp.message, 'Failed', 404);
        } catch (DmlException de) {
            resp.success = false;
            resp.message = 'DML failed while processing attendance: ' + de.getMessage();
            IntegrationLogUtil.insertLog(serviceName, requestPayload, null, resp.message, 'Failed', 500);
        } catch (Exception e) {
            resp.success = false;
            resp.message = 'Error while processing attendance: ' + e.getMessage();
            IntegrationLogUtil.insertLog(serviceName, requestPayload, null, resp.message, 'Failed', 500);
        }

        return resp;
    }

    private static String truncate(String value) {
        return (value != null && value.length() > 3000) ? value.substring(0, 3000) : value;
    }
}