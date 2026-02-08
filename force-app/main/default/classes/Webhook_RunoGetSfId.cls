/*
    Author       : ROHIT SINGH BISHT
    Description  : Fetch Candidate Id (sf_id) from Call Id
*/
@RestResource(urlMapping='/salesforce/get-sf-id/*')
global without sharing class Webhook_RunoGetSfId {

    global class SuccessResponse {
        public String sf_id;
    }

    global class ErrorResponse {
        public String status;
        public String message;
    }

    @HttpGet
    global static String getSfId() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;

        String serviceName = 'Runo Get SF Id';
        String callId = req != null ? req.params.get('callId') : null;
        String requestPayload = 'callId=' + (callId == null ? '' : callId);

        try {
            if (String.isBlank(callId)) {
                ErrorResponse err = new ErrorResponse();
                err.status = 'failed';
                err.message = 'callId is required';
                res.statusCode = 400;
                String responsePayload = JSON.serialize(err);
                IntegrationLogUtil.insertLog(serviceName, requestPayload, responsePayload, err.message, 'Failed', 400);
                return responsePayload;
            }

            List<Call_Log__c> logs = [
                SELECT Id, Call_Id__c, Lead__c, Lead__r.Candidate__c, Candidate__c
                FROM Call_Log__c
                WHERE Call_Id__c = :callId
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];

            if (logs.isEmpty()) {
                ErrorResponse err = new ErrorResponse();
                err.status = 'failed';
                err.message = 'Call log not found for callId';
                res.statusCode = 404;
                String responsePayload = JSON.serialize(err);
                IntegrationLogUtil.insertLog(serviceName, requestPayload, responsePayload, err.message, 'Failed', 404);
                return responsePayload;
            }

            Id candidateId = (logs[0].Lead__r != null) ? logs[0].Lead__r.Candidate__c : logs[0].Candidate__c;
            if (candidateId == null) {
                ErrorResponse err = new ErrorResponse();
                err.status = 'failed';
                err.message = 'Candidate not found for callId';
                res.statusCode = 404;
                String responsePayload = JSON.serialize(err);
                IntegrationLogUtil.insertLog(serviceName, requestPayload, responsePayload, err.message, 'Failed', 404);
                return responsePayload;
            }

            SuccessResponse out = new SuccessResponse();
            out.sf_id = String.valueOf(candidateId);

            res.statusCode = 200;
            String responsePayload = JSON.serialize(out);
            IntegrationLogUtil.insertLog(serviceName, requestPayload, responsePayload, 'Success', 'Success', 200);
            return responsePayload;

        } catch (Exception e) {
            ErrorResponse err = new ErrorResponse();
            err.status = 'failed';
            err.message = 'Unhandled error: ' + e.getMessage();
            res.statusCode = 500;
            String responsePayload = JSON.serialize(err);
            IntegrationLogUtil.insertLog(serviceName, requestPayload, responsePayload, err.message, 'Failed', 500);
            return responsePayload;
        }
    }
}