@RestResource(urlMapping='/miles-one/webinar-registrations/*')
global without sharing class Webhook_Miles1WebinarRegistration {

    private static final String SERVICE_NAME = 'Miles1 Webinar Registration Webhook';

    global class WebinarRegistrationRequestDTO {
        public String webinar_id;
        public String registrant_id;
        public String registered_email;
        public String joining_url;
        public Integer campaign_id;
    }

    global class WebinarRegistrationResponseDTO {
        public Boolean success;
        public String message;
        public Id recordId;
    }

    @HttpPost
    global static WebinarRegistrationResponseDTO registerWebinar() {
        RestRequest request = RestContext.request;
        String requestBody = truncate(
            request != null && request.requestBody != null
                ? request.requestBody.toString()
                : null
        );

        if (String.isBlank(requestBody)) {
            return buildResponse(false, 'Empty request body', null, requestBody, 400);
        }

        WebinarRegistrationRequestDTO input;
        try {
            input = (WebinarRegistrationRequestDTO) JSON.deserialize(requestBody, WebinarRegistrationRequestDTO.class);
        } catch (Exception e) {
            return buildResponse(false, 'Invalid JSON: ' + e.getMessage(), null, requestBody, 400);
        }

        if (input == null || String.isBlank(input.webinar_id) || String.isBlank(input.registrant_id) || String.isBlank(input.registered_email)) {
            return buildResponse(false, 'webinar_id, registrant_id and registered_email are required', null, requestBody, 400);
        }

        try {
            Webinar__c webinar = fetchWebinar(input.webinar_id);
            if (webinar == null) {
                return buildResponse(false, 'Webinar not found', null, requestBody, 404);
            }

            Email__c emailRecord = fetchEmailRecord(input.registered_email);

            Webinar_Member__c member = new Webinar_Member__c();
            member.Webinar__c = webinar.Id;
            member.Registrant_Id__c = input.registrant_id;
            member.Meeting_Details__c = buildMeetingDetails(input.joining_url);

            if (emailRecord != null) {
                member.Lead__c = emailRecord.Lead__c;
                member.Candidate__c = emailRecord.Candidate__c;
            }

            insert member;

            return buildResponse(true, 'Webinar member created successfully', member.Id, requestBody, 200);
        } catch (DmlException e) {
            return buildResponse(false, 'DML error while creating webinar member: ' + e.getMessage(), null, requestBody, 500);
        } catch (Exception e) {
            return buildResponse(false, 'Unhandled error: ' + e.getMessage(), null, requestBody, 500);
        }
    }

    private static Webinar__c fetchWebinar(String webinarId) {
        List<Webinar__c> webinars = [SELECT Id FROM Webinar__c WHERE Webinar_Id__c = :webinarId LIMIT 1];
        return webinars.isEmpty() ? null : webinars[0];
    }

    private static Email__c fetchEmailRecord(String emailAddress) {
        if (String.isBlank(emailAddress)) {
            return null;
        }

        List<Email__c> emailRecords = [SELECT Id, Lead__c, Candidate__c FROM Email__c WHERE Email__c = :emailAddress ORDER BY Is_Primary__c DESC, CreatedDate DESC LIMIT 1];
        return emailRecords.isEmpty() ? null : emailRecords[0];
    }

    private static String buildMeetingDetails(String joiningUrl) {
        if (String.isBlank(joiningUrl)) {
            return null;
        }
        return '<a href="' + joiningUrl + '" target="_blank">' + joiningUrl + '</a>';
    }

    private static WebinarRegistrationResponseDTO buildResponse(
        Boolean success,
        String message,
        Id recordId,
        String requestBody,
        Integer statusCode
    ) {
        WebinarRegistrationResponseDTO response = new WebinarRegistrationResponseDTO();
        response.success = success;
        response.message = message;
        response.recordId = recordId;

        if (RestContext.response != null) {
            RestContext.response.statusCode = statusCode;
        }

        IntegrationLogUtil.insertLog(
            SERVICE_NAME,
            requestBody,
            truncate(JSON.serialize(response)),
            success ? null : message,
            success ? 'Success' : 'Failed',
            statusCode
        );

        return response;
    }

    private static String truncate(String value) {
        return value != null && value.length() > 3000
            ? value.substring(0, 3000)
            : value;
    }
}