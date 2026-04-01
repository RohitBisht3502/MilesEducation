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

                IntegrationLogUtil.insertLog(
                    'Runo call log initiated',
                    requestBody,
                    responseBody,
                    'Empty request body received',
                    'Failed',
                    statusCode
                );

                return new ApiResponse(false, 'Missing request body', null);
            }

            ClickToCallPayload payload = (ClickToCallPayload) JSON.deserialize(requestBody, ClickToCallPayload.class);

            if (payload == null || String.isBlank(payload.callerId) || String.isBlank(payload.contactPhone)) {
                statusCode = 400;
                responseBody = '{"error":"callerId and contactPhone are required"}';
                res.statusCode = statusCode;
                res.responseBody = Blob.valueOf(responseBody);

                IntegrationLogUtil.insertLog(
                    'Runo call log initiated',
                    requestBody,
                    responseBody,
                    'Missing required fields',
                    'Failed',
                    statusCode
                );

                return new ApiResponse(false, 'callerId and contactPhone are required', null);
            }

            if (payload.type != null && payload.type.toLowerCase() == 'incoming') {
                // CUSTOMER PHONE
                String customerPhone = payload.contactPhone != null ? payload.contactPhone.replaceAll('[^0-9]', '') : null;
                String calledId = payload.callerId;

                if (customerPhone != null && customerPhone.length() > 10) {
                    customerPhone = customerPhone.substring(customerPhone.length() - 10);
                }

                // LEAD MATCH
                Lead ld;
                if (customerPhone != null) {
                    List<Lead> leads = [SELECT Id FROM Lead WHERE Phone LIKE :('%' + customerPhone) LIMIT 1];
                    if (!leads.isEmpty()) {
                        ld = leads[0];
                    }
                }

                // USER MATCH
                User matchedUser;
                List<User> users = [SELECT Id, CallerId__c FROM User WHERE CallerId__c = :calledId LIMIT 1];

                if (!users.isEmpty()) {
                    matchedUser = users[0];
                }

                // FIRE EVENT ONLY IF USER FOUND
                if (matchedUser != null) {
                    Runo_Call_Initiate__e eventMsg = new Runo_Call_Initiate__e(
                        Call_Id__c = payload.callerId,
                        Lead_Id__c = ld != null ? ld.Id : null,
                        Phone__c = customerPhone != null ? Decimal.valueOf(customerPhone) : null,
                        Type__c = payload.type,
                        Status__c = 'Initiated',
                        Assigned_User__c = matchedUser.Id
                    );

                    EventBus.publish(eventMsg);
                    System.debug('EVENT FIRED FOR USER: ' + matchedUser.Id);
                } else {
                    System.debug('No user matched → EVENT NOT FIRED');
                }
            }

            status = 'Success';
            statusCode = 200;
            responseBody = '{"status":"success","message":"Call log received."}';
            res.statusCode = statusCode;
            res.responseBody = Blob.valueOf(responseBody);

            IntegrationLogUtil.insertLog(
                'Runo call log initiated',
                requestBody,
                responseBody,
                'Runo call log received',
                status,
                statusCode
            );

            return new ApiResponse(true, 'Call log received', null);

        } catch (Exception ex) {
            errorMessage = ex.getMessage();
            statusCode = 500;
            responseBody = '{"error":"Internal Server Error"}';
            res.statusCode = statusCode;
            res.responseBody = Blob.valueOf(responseBody);

            IntegrationLogUtil.insertLog(
                'Runo call log initiated',
                requestBody,
                responseBody,
                errorMessage,
                'Failed',
                statusCode
            );

            return new ApiResponse(false, 'Error: ' + errorMessage, null);
        }
    }

    public class ClickToCallPayload {
        public String callerId;
        public String contactPhone;
        public String timestamp;
        public String agentNumber;
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