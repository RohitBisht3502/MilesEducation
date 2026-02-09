/*
    Author       : ROHIT SINGH BISHT
    Description  : 
*/
@RestResource(urlMapping='/salesforce/recording/*')
global without sharing class Webservice_RunoCallRecordingWebhook {
    private static final String VENDOR_TOKEN = '4f029d1bcee05d32cdc8a3d32b0fcda7';

    global class RecordingDTO {
        public String callId;
        public String recordingUrl;
    }

    global class ApiResponse {
        public Boolean success;
        public String message;
    }

    @HttpPost
    global static ApiResponse handleRunoWebhook() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;

        String requestBody = '';
        Integer statusCode = 500;
        ApiResponse out = new ApiResponse();
        out.success = false;

        try {
            String token = req.headers.get('x-vendor-token');

            // if (String.isBlank(token) || token != VENDOR_TOKEN) {
            //     statusCode = 401;
            //     responseBody = '{"error":"Unauthorized - Invalid token"}';
            //     res.statusCode = statusCode;
            //     res.responseBody = Blob.valueOf(responseBody);
            //     IntegrationLogUtil.insertLog( 'Runo → Miles Force',  null,  responseBody, 'Invalid or missing token in request header', 'Failed',  statusCode );
            //     return;
            // }

            requestBody = req.requestBody.toString();

            if (String.isBlank(requestBody)) {
                statusCode = 400;
                out.message = 'Missing request body';
                IntegrationLogUtil.insertLog('Runo → Miles Force', null, null, out.message, 'Failed', statusCode );
                if (res != null) res.statusCode = statusCode;
                return out;
            }

            RecordingDTO dto = (RecordingDTO)JSON.deserialize(requestBody, RecordingDTO.class);

            if (String.isBlank(dto.callId) || String.isBlank(dto.recordingUrl)) {
                statusCode = 400;
                out.message = 'Missing callId or recordingUrl';
                IntegrationLogUtil.insertLog('Runo → Miles Force', requestBody, null, out.message, 'Failed', statusCode );
                if (res != null) res.statusCode = statusCode;
                return out;
            }

            System.debug('dto.callId   '+dto.callId);
            List<Call_Log__c> logs = [ SELECT Id ,Call_Id__c,Recording_Url__c FROM Call_Log__c  WHERE Call_Id__c = :dto.callId ORDER BY CreatedDate DESC LIMIT 1 ];
            System.debug('logs   '+logs);

            if (logs.isEmpty()) {
                statusCode = 404;
                out.message = 'Call log not found for callId';
                IntegrationLogUtil.insertLog('Runo → Miles Force', requestBody, null, out.message, 'Failed', statusCode );
                if (res != null) res.statusCode = statusCode;
                return out;
            }

            update new Call_Log__c(
                Id = logs[0].Id,
                Recording_Url__c = dto.recordingUrl
            );

            statusCode = 200;
            out.success = true;
            out.message = 'Recording received and processed successfully';
            IntegrationLogUtil.insertLog( 'Runo → Miles Force', requestBody, JSON.serialize(out), out.message, 'Success', statusCode );
            if (res != null) res.statusCode = statusCode;
            return out;
           //RunoCallLogHandler.ApiResponse apiResponse = RunoCallLogHandler.processCallLog(requestBody);

           

        } catch (QueryException qe) {
            statusCode = 404;
            out.message = 'Call log not found for callId';
            IntegrationLogUtil.insertLog( 'Runo → Miles Force',  requestBody, null, out.message, 'Failed', statusCode );
            if (res != null) res.statusCode = statusCode;
            return out;

        } catch (Exception ex) {
            statusCode = 500;
            out.message = 'Unhandled error: ' + ex.getMessage();
            IntegrationLogUtil.insertLog(
                'Runo → Miles Force',
                requestBody,
                null,
                out.message,
                'Failed',
                statusCode
            );
            if (res != null) res.statusCode = statusCode;
            return out;
        }

    }
}

