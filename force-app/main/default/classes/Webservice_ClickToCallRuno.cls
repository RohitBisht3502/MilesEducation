/**
     * Author: Rohit singh bisht
     * Purpose: Accept click-to-call payload from webhook clients and log it.
     */
@RestResource(urlMapping='/runo/call-log/intiated/*')
global without sharing class Webservice_ClickToCallRuno {
    @HttpPost
    global static ApiResponse initiateClickToCall() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;

        String requestBody = '';
        String responseBody = '';
        String status = 'Failed';
        Integer statusCode = 500;
        String errorMessage = '';

        try {
            requestBody = req.requestBody.toString();
            if (String.isBlank(requestBody)) {
                statusCode = 400;
                responseBody = '{"error":"Missing request body"}';
                res.statusCode = statusCode;
                res.responseBody = Blob.valueOf(responseBody);
                IntegrationLogUtil.insertLog('Runo call log initiated', requestBody, responseBody, 'Empty request body received', 'Failed', statusCode);
                return new ApiResponse(false, 'Missing request body', null);
            }
ClickToCallPayload payload = (ClickToCallPayload) JSON.deserialize(requestBody, ClickToCallPayload.class);

if (payload == null || String.isBlank(payload.callerId) || String.isBlank(payload.contactPhone)) {
    statusCode = 400;
    responseBody = '{"error":"callerId and contactPhone are required"}';
    res.statusCode = statusCode;
    res.responseBody = Blob.valueOf(responseBody);
    IntegrationLogUtil.insertLog('Runo call log initiated', requestBody, responseBody, 'Missing required fields', 'Failed', statusCode);
    return new ApiResponse(false, 'callerId and contactPhone are required', null);
}

// ADD THIS BLOCK HERE
if (payload.type != null && payload.type.toLowerCase() == 'incoming') {

    // STEP 1: Clean phone
    String cleanPhone = payload.contactPhone != null 
        ? payload.contactPhone.replaceAll('[^0-9]', '') 
        : null;

    //  ADD LEAD MAPPING HERE
    Lead ld;

    if (cleanPhone != null) {
        List<Lead> leads = [
            SELECT Id 
            FROM Lead 
            WHERE Phone LIKE :('%' + cleanPhone) 
            LIMIT 1
        ];

        if (!leads.isEmpty()) {
            ld = leads[0];
        }
    }

    //  THEN CREATE EVENT
    Runo_Call_Initiate__e eventMsg = new Runo_Call_Initiate__e(
        Call_Id__c = payload.callerId,
        Lead_Id__c = ld != null ? ld.Id : null,   // 
        Phone__c = cleanPhone != null ? Decimal.valueOf(cleanPhone) : null,
        Type__c = payload.type,
        Status__c = 'Initiated'
    );

    EventBus.publish(eventMsg);
}
            status = 'Success';
            statusCode = 200;
            responseBody = '{"status":"success","message":"Call log received."}';
            res.statusCode = statusCode;
            res.responseBody = Blob.valueOf(responseBody);

            IntegrationLogUtil.insertLog('Runo call log initiated', requestBody, responseBody, 'Runo call log received', status, statusCode);
            return new ApiResponse(true, 'Call log received', null);
        } catch (Exception ex) {
            errorMessage = ex.getMessage();
            statusCode = 500;
            responseBody = '{"error":"Internal Server Error"}';
            res.statusCode = statusCode;
            res.responseBody = Blob.valueOf(responseBody);
            IntegrationLogUtil.insertLog('Runo call log initiated', requestBody, responseBody, errorMessage, 'Failed', statusCode);
            return new ApiResponse(false, 'Error: ' + errorMessage, null);
        }
    }

    public class ClickToCallPayload {
        public String callerId;
        public String contactPhone;
        public String timestamp;
        public String type;
    }

    global class ApiResponse {
        public Boolean success;
        public String message;
        public String recordId;
        public ApiResponse(Boolean success, String message, String recordId) {
            this.success = success;
            this.message = message;
            this.recordId = recordId;
        }
    }
}