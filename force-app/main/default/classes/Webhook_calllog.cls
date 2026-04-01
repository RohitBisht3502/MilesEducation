@RestResource(urlMapping='/webhookcalllog/creation/')
global without sharing class Webhook_calllog {

    //Request Wrapper
    global class CallLogRequest {
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

    // Response Wrapper
    global class CallLogResponse {
        public Boolean success;
        public String message;
        public Id recordId;
    }

    @HttpPost
    global static CallLogResponse createOrUpdateCallLog() {

        RestRequest req = RestContext.request;
        String reqBody = (req != null && req.requestBody != null) 
            ? req.requestBody.toString() : null;

        //  Empty Body Check
        if (String.isBlank(reqBody)) {
            return generateResponse(false, 'Empty request body', null, reqBody, 400);
        }

        // Deserialize Request
        CallLogRequest input;
        try {
            input = (CallLogRequest) JSON.deserialize(reqBody, CallLogRequest.class);
        } catch (Exception e) {
            return generateResponse(false, 'Invalid JSON: ' + e.getMessage(), null, reqBody, 400);
        }

        // Validate Required Fields
        if (String.isBlank(input.sf_candidate_id) || String.isBlank(input.sf_user_id)) {
            return generateResponse(false, 'sf_candidate_id and sf_user_id are required', null, reqBody, 400);
        }

        try {

            //  Fetch Lead 
            List<Lead> candList = [
                SELECT Id 
                FROM Lead 
                WHERE Candidate_ID__c = :input.sf_candidate_id
                LIMIT 1
            ];

            if (candList.isEmpty()) {
                return generateResponse(false, 'Candidate not found', null, reqBody, 404);
            }

            Lead cand = candList[0];

            // Fetch Call Log 
            List<Call_Log__c> logs = [
                SELECT Id, OwnerId
                FROM Call_Log__c
                WHERE Lead__c = :cand.Id
                AND OwnerId = :input.sf_user_id
                LIMIT 1
            ];

            //  If not found 
            if (logs.isEmpty()) {
                return generateResponse(
                    false,
                    'No Call Log Found for given Candidate and User',
                    null,
                    reqBody,
                    404
                );
            }

            //  Update existing record
            Call_Log__c log = logs[0];

            //  Map Fields
            log.Start_Time__c = parseDateTime(input.start_date);
            log.End_Time__c = parseDateTime(input.end_date);
            log.exotel_call_id__c = input.exotel_call_id;
            log.Duration_Seconds__c = input.duration;
            log.Status__c = input.call_status;
            log.Type__c = input.call_type;
            log.Recording_Url__c = input.call_recording_url;
            log.Call_Id__c = input.exotel_call_id;

            //  Update Record
            update log;

            //  Success Response
            return generateResponse(
                true,
                'Call Log Updated Successfully',
                log.Id,
                reqBody,
                200
            );

        } catch (Exception e) {

            return generateResponse(
                false,
                'Error: ' + e.getMessage(),
                null,
                reqBody,
                500
            );
        }
    }

    // FIXED METHOD 
    private static CallLogResponse generateResponse(Boolean success, String msg, Id recId, String reqBody, Integer statusCode) {

        CallLogResponse resp = new CallLogResponse();
        resp.success = success;
        resp.message = msg;
        resp.recordId = recId;

        //  Convert response to JSON 
        String responseJson = JSON.serialize(resp);

        // CORRECT PARAMETER ORDER
        IntegrationLogUtil.insertLog(
            'Call Log API',
            truncate(reqBody),   
            responseJson,        
            msg,                 
            success ? 'Success' : 'Failed',
            statusCode
        );

        return resp;
    }

    // DateTime Parser
    private static Datetime parseDateTime(String dt) {
        if (String.isBlank(dt)) return null;

        try {
            return Datetime.valueOfGmt(dt.replace('T',' ').replace('Z',''));
        } catch (Exception e) {
            return null;
        }
    }

    // Truncate Large Request
    private static String truncate(String input) {
        if (input == null) return null;
        return input.length() > 3000 ? input.substring(0, 3000) : input;
    }
}