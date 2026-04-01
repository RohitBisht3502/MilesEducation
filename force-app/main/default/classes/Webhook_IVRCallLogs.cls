@RestResource(urlMapping='/ivr/calllogs/creation/')
global without sharing class Webhook_IVRCallLogs {

    private static final String SERVICE_NAME = 'IVR Call Logs';

    global class CallLogRequestDTO {
        public String sf_candidate_id;
        public String sf_user_id;
        public String start_date;
        public String end_date;
        public String exotel_call_id;
        public Integer duration;
        public String call_status;
        public String call_type;
        public String call_recording_url;
    }

    global class CallLogResponseDTO {
        public Boolean success;
        public String message;
        public Id recordId;
    }

    @HttpPost
    global static CallLogResponseDTO updateCallLog() {
        RestRequest request = RestContext.request;
        String requestBody = truncate(
            request != null && request.requestBody != null
                ? request.requestBody.toString()
                : null
        );

        if (String.isBlank(requestBody)) {
            return buildResponse(false, 'Empty request body', null, requestBody, 400);
        }

        CallLogRequestDTO input;
        try {
            input = (CallLogRequestDTO) JSON.deserialize(requestBody, CallLogRequestDTO.class);
        } catch (Exception e) {
            return buildResponse(false, 'Invalid JSON: ' + e.getMessage(), null, requestBody, 400);
        }

        if (input == null || String.isBlank(input.sf_candidate_id) || String.isBlank(input.sf_user_id)) {
            return buildResponse(
                false,
                'sf_candidate_id and sf_user_id are required',
                null,
                requestBody,
                400
            );
        }

        try {
            Lead candidate = fetchCandidate(input.sf_candidate_id);
            if (candidate == null) {
                return buildResponse(false, 'Candidate not found', null, requestBody, 404);
            }

            Id ownerId = parseId(input.sf_user_id);
            if (ownerId == null) {
                return buildResponse(false, 'Invalid sf_user_id', null, requestBody, 400);
            }

            Call_Log__c callLog = fetchCallLog(candidate.Id, ownerId);
            if (callLog == null) {
                return buildResponse(
                    false,
                    'No call log found for the given candidate and user',
                    null,
                    requestBody,
                    404
                );
            }

            callLog.Start_Time__c = parseDateTime(input.start_date);
            callLog.End_Time__c = parseDateTime(input.end_date);
            callLog.exotel_call_id__c = input.exotel_call_id;
            callLog.Duration_Seconds__c = input.duration;
            callLog.Status__c = input.call_status;
            callLog.Type__c = input.call_type;
            callLog.Recording_Url__c = input.call_recording_url;
            callLog.Call_Id__c = input.exotel_call_id;

            update callLog;

            return buildResponse(
                true,
                'Call log updated successfully',
                callLog.Id,
                requestBody,
                200
            );
        } catch (DmlException e) {
            return buildResponse(
                false,
                'DML error while updating call log: ' + e.getMessage(),
                null,
                requestBody,
                500
            );
        } catch (Exception e) {
            return buildResponse(
                false,
                'Unhandled error: ' + e.getMessage(),
                null,
                requestBody,
                500
            );
        }
    }

    private static Lead fetchCandidate(String candidateId) {
        List<Lead> candidates = [SELECT Id FROM Lead WHERE Candidate_ID__c = :candidateId LIMIT 1];
        return candidates.isEmpty() ? null : candidates[0];
    }

    private static Call_Log__c fetchCallLog(Id leadId, Id ownerId) {
        List<Call_Log__c> callLogs = [SELECT Id, OwnerId FROM Call_Log__c WHERE Lead__c = :leadId AND OwnerId = :ownerId LIMIT 1];
        return callLogs.isEmpty() ? null : callLogs[0];
    }

    private static CallLogResponseDTO buildResponse(
        Boolean success,
        String message,
        Id recordId,
        String requestBody,
        Integer statusCode
    ) {
        CallLogResponseDTO response = new CallLogResponseDTO();
        response.success = success;
        response.message = message;
        response.recordId = recordId;

        if (RestContext.response != null) {
            RestContext.response.statusCode = statusCode;
        }

        IntegrationLogUtil.insertLog(SERVICE_NAME, requestBody, truncate(JSON.serialize(response)), message, success ? 'Success' : 'Failed', statusCode);

        return response;
    }

    private static Datetime parseDateTime(String value) {
        if (String.isBlank(value)) {
            return null;
        }

        try {
            return Datetime.valueOfGmt(value.replace('T', ' ').replace('Z', ''));
        } catch (Exception e) {
            return null;
        }
    }

    private static Id parseId(String value) {
        if (String.isBlank(value)) {
            return null;
        }

        try {
            return (Id) value;
        } catch (Exception e) {
            return null;
        }
    }

    private static String truncate(String value) {
        return (value != null && value.length() > 3000)
            ? value.substring(0, 3000)
            : value;
    }
}