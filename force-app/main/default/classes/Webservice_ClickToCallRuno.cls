/*
    Author       : ROHIT SINGH BISHT
    Description  : 
*/
@RestResource(urlMapping='/runo/call-log/intiated/*')
global without sharing class Webservice_ClickToCallRuno {

    @HttpPost
    global static void initiateClickToCall() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;

        // Initialize log variables
        String requestBody = '';
        String responseBody = '';
        String status = 'Failed';
        Integer statusCode = 500;
        String errorMessage = '';

        try {
            // Capture incoming request body
            requestBody = req.requestBody.toString();
            if (String.isBlank(requestBody)) {
                statusCode = 400;
                responseBody = '{"error":"Missing request body"}';
                res.statusCode = statusCode;
                res.responseBody = Blob.valueOf(responseBody);

                IntegrationLogUtil.insertLog(
                    'Miles Force → Runo (Click-to-Call)',
                    requestBody,
                    responseBody,
                    'Empty request body received',
                    'Failed',
                    statusCode
                );
                return;
            }

            // Deserialize incoming data
            Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(requestBody);

            // Prepare Runo body
            Map<String, Object> runoBody = new Map<String, Object>{
                'customer'   => data.get('customer'),
                'processName'=> data.get('processName'),
                'assignedTo' => data.get('assignedTo'),
                'priority'   => data.get('priority'),
                'notes'      => data.get('notes'),
                'userFields' => data.get('userFields')
            };

            String jsonBody = JSON.serialize(runoBody);

            // Perform HTTP Callout to Runo
            Http http = new Http();
            HttpRequest httpReq = new HttpRequest();
            httpReq.setEndpoint('https://api.runo.in/v1/crm/allocation?isAutoDialLead=true');
            httpReq.setMethod('POST');
            httpReq.setHeader('Auth-Key', 'MTl5ZG5tcHhqOTE3MjE2NTQ=');
            httpReq.setHeader('Content-Type', 'application/json');
            httpReq.setBody(jsonBody);

            HttpResponse httpRes = http.send(httpReq);
            responseBody = httpRes.getBody();
            statusCode = httpRes.getStatusCode();

            if (statusCode == 200 || statusCode == 201) {
                status = 'Success';
                res.statusCode = 200;
                res.responseBody = Blob.valueOf('{"status":"success","message":"Call initiated successfully."}');
            } else {
                status = 'Failed';
                res.statusCode = statusCode;
                res.responseBody = Blob.valueOf('{"status":"error","message":"Runo API Error"}');
            }

            // Log Integration
            IntegrationLogUtil.insertLog(
                'Miles Force → Runo (Click-to-Call)',
                requestBody,
                responseBody,
                'Runo click-to-call API executed',
                status,
                statusCode
            );

        } catch (Exception ex) {
            errorMessage = ex.getMessage();
            statusCode = 500;
            responseBody = '{"error":"Internal Server Error"}';
            res.statusCode = statusCode;
            res.responseBody = Blob.valueOf(responseBody);

            IntegrationLogUtil.insertLog(
                'Miles Force → Runo (Click-to-Call)',
                requestBody,
                responseBody,
                errorMessage,
                'Failed',
                statusCode
            );
        }
    }
}