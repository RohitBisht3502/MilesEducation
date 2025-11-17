@RestResource(urlMapping='/runo/call-log/recording/*')
global without sharing class Webservice_RunoCallRecordingWebhook {
    private static final String VENDOR_TOKEN = '4f029d1bcee05d32cdc8a3d32b0fcda7';

    public class RecordingDTO {
        public String callId;
        public String recordingUrl;
    }

    @HttpPost
    global static void handleRunoWebhook() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;

        String requestBody = '';
        String responseBody = '';
        String status = 'Failed';
        Integer statusCode = 500;
        String errorMessage = '';

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
                responseBody = '{"error":"Missing request body"}';
                res.statusCode = statusCode;
                res.responseBody = Blob.valueOf(responseBody);

                IntegrationLogUtil.insertLog('Runo → Miles Force', null, responseBody, 'Empty request body received','Failed', statusCode );
                return;
            }

            RecordingDTO dto = (RecordingDTO)JSON.deserialize(requestBody, RecordingDTO.class);

            if (String.isBlank(dto.callId) || String.isBlank(dto.recordingUrl)) {
                statusCode = 400;
                responseBody = '{"error":"Missing callId or recordingUrl"}';
                res.statusCode = statusCode;
                res.responseBody = Blob.valueOf(responseBody);

                IntegrationLogUtil.insertLog('Runo → Miles Force', requestBody, responseBody, 'Missing required fields (callId/recordingUrl)', 'Failed', statusCode );
                return;
            }

            System.debug('dto.callId   '+dto.callId);
            List<Call_Log__c> logs = [ SELECT Id ,Call_Id__c,Recording_Url__c FROM Call_Log__c  WHERE Call_Id__c = :dto.callId  LIMIT 1 ];
            System.debug('logs   '+logs);
            if (!logs.isEmpty()) {
                update new Call_Log__c(
                    Id = logs[0].Id,
                    Recording_Url__c = dto.recordingUrl
                );
            }

            status = 'Success';
            statusCode = 200;
            responseBody = '{"status":"success","message":"Runo call recording data received"}';
            res.statusCode = statusCode;
            res.responseBody = Blob.valueOf(responseBody);

            IntegrationLogUtil.insertLog( 'Runo → Miles Force', requestBody, responseBody, 'Runo webhook processed successfully', status, statusCode );
           //RunoCallLogHandler.ApiResponse apiResponse = RunoCallLogHandler.processCallLog(requestBody);

           

        } catch (QueryException qe) {
            statusCode = 404;
            responseBody = '{"error":"Call log not found for callId"}';
            res.statusCode = statusCode;
            res.responseBody = Blob.valueOf(responseBody);

            IntegrationLogUtil.insertLog( 'Runo → Miles Force',  requestBody, responseBody, 'Call log not found', 'Failed', statusCode );

        } catch (Exception ex) {
            errorMessage = ex.getMessage();
            statusCode = 500;
            responseBody = '{"error":"Internal Server Error"}';
            res.statusCode = statusCode;
            res.responseBody = Blob.valueOf(responseBody);

            IntegrationLogUtil.insertLog('Runo → Miles Force', requestBody,  responseBody,errorMessage,'Failed', statusCode );
        }
    }
}