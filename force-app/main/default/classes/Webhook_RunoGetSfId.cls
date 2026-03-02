/*
    Author       : ROHIT SINGH BISHT
    Description  : Fetch Candidate Id (sf_id) from Call Id
*/
@RestResource(urlMapping='/salesforce/get-sf-id/*')
global without sharing class Webhook_RunoGetSfId {

    global class ApiResponse {
        public Boolean success;
        public String message;
        public String miles_uuid;
    }

    @HttpGet
    global static ApiResponse getSfId() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;

        String serviceName = 'Runo Get SF Id';
        String callId = req != null ? req.params.get('callId') : null;
        String requestPayload = 'callId=' + (callId == null ? '' : callId);
        Integer statusCode = 500;

        ApiResponse out = new ApiResponse();
        out.success = false;

        try {
            if (String.isBlank(callId)) {
                statusCode = 400;
                out.message = 'callId is required';
                IntegrationLogUtil.insertLog(serviceName, requestPayload, null, out.message, 'Failed', statusCode);
                if (res != null) res.statusCode = statusCode;
                return out;
            }

            List<Call_Log__c> logs = [SELECT Id, Call_Id__c, Candidate__c, Student__c FROM Call_Log__c WHERE Call_Id__c = :callId ORDER BY CreatedDate DESC LIMIT 1];

            if (logs.isEmpty()) {
                statusCode = 404;
                out.message = 'Call log not found for callId';
                IntegrationLogUtil.insertLog(serviceName, requestPayload, null, out.message, 'Failed', statusCode);
                if (res != null) res.statusCode = statusCode;
                return out;
            }

            Id candidateId = logs[0].Candidate__c;
            if (candidateId == null) {
                statusCode = 404;
                out.message = 'Candidate not found for callId';
                IntegrationLogUtil.insertLog(serviceName, requestPayload, null, out.message, 'Failed', statusCode);
                if (res != null) res.statusCode = statusCode;
                return out;
            }

            Lead cand = [SELECT Id, UUID__c, IsConverted, ConvertedAccountId FROM Lead WHERE Id = :candidateId LIMIT 1];

            if (cand != null && cand.IsConverted == true) {
                Id accountId = logs[0].Student__c != null ? logs[0].Student__c : cand.ConvertedAccountId;
                if (accountId == null) {
                    statusCode = 404;
                    out.message = 'Student account not found for callId';
                    IntegrationLogUtil.insertLog(serviceName, requestPayload, null, out.message, 'Failed', statusCode);
                    if (res != null) res.statusCode = statusCode;
                    return out;
                }

                Account acc = [SELECT Id, UUID__c FROM Account WHERE Id = :accountId LIMIT 1];

                if (acc == null || String.isBlank(acc.UUID__c)) {
                    statusCode = 404;
                    out.message = 'Student UUID not found for callId';
                    IntegrationLogUtil.insertLog(serviceName, requestPayload, null, out.message, 'Failed', statusCode);
                    if (res != null) res.statusCode = statusCode;
                    return out;
                }

                statusCode = 200;
                out.success = true;
                out.miles_uuid = acc.UUID__c;
                out.message = 'Success';

                String responsePayload = JSON.serialize(out);
                IntegrationLogUtil.insertLog(serviceName, requestPayload, responsePayload, out.message, 'Success', statusCode);
                if (res != null) res.statusCode = statusCode;
                return out;
            }

            if (cand == null || String.isBlank(cand.UUID__c)) {
                statusCode = 404;
                out.message = 'Candidate UUID not found for callId';
                IntegrationLogUtil.insertLog(serviceName, requestPayload, null, out.message, 'Failed', statusCode);
                if (res != null) res.statusCode = statusCode;
                return out;
            }

            statusCode = 200;
            out.success = true;
            out.miles_uuid = cand.UUID__c;
            out.message = 'Success';

            String responsePayload = JSON.serialize(out);
            IntegrationLogUtil.insertLog(serviceName, requestPayload, responsePayload, out.message, 'Success', statusCode);
            if (res != null) res.statusCode = statusCode;
            return out;

        } catch (Exception e) {
            statusCode = 500;
            out.message = 'Unhandled error: ' + e.getMessage();
            IntegrationLogUtil.insertLog(serviceName, requestPayload, null, out.message, 'Failed', statusCode);
            if (res != null) res.statusCode = statusCode;
            return out;
        }
    }
}