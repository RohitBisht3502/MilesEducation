/*
    Author       : ROHIT SINGH BISHT
    Description  : 
*/
@RestResource(urlMapping='/runo/call-log')
global without sharing class Webservice_RunoWebhookService {

    global class Ack {
        public Boolean success;
        public String message;
    }

    @HttpPost
    global static void receive() {
        List<Integration_Log__c> logs = new List<Integration_Log__c>();
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;

        String body = req.requestBody != null ? req.requestBody.toString() : null;
        Map<String, String> headers = req.headers;
        Map<String, String> params  = req.params;
        String url = req.requestURI;

        String envelope = JSON.serialize(new Map<String, Object>{
            'url'     => url,
            'headers' => headers,
            'params'  => params,
            'body'    => body
        });

        External_Service_Config__mdt cfg;
        try {
            cfg = [
                SELECT Api_Key__c, Api_Key_Header__c, Is_Active__c FROM External_Service_Config__mdt WHERE DeveloperName = 'Runo_Webhook' LIMIT 1 ];
        } catch (Exception e) {
            logs.add(IntegrationLogUtil.buildLog('Runo Webhook', envelope, null, 'Config load error: ' + e.getMessage(), 'Failed', 500));
            IntegrationLogUtil.insertLogs(logs);
            send(res, 500, false, 'Config load error');
            return;
        }

        String expectedHeader = cfg != null ? cfg.Api_Key_Header__c : null;
        String expectedToken  = cfg != null ? cfg.Api_Key__c        : null;
        String providedToken  = (headers != null && expectedHeader != null) ? headers.get(expectedHeader) : null;

        // if (cfg == null || !cfg.Is_Active__c || String.isBlank(expectedHeader) || String.isBlank(expectedToken) || String.isBlank(providedToken) || providedToken != expectedToken) {
        //     logs.add(IntegrationLogUtil.buildLog('Runo Webhook', envelope, null, 'Unauthorized', 'Failed', 401));
        //     IntegrationLogUtil.insertLogs(logs);
        //     send(res, 401, false, 'Unauthorized');
        //     return;
        // }

        Object parsed;
        try { parsed = JSON.deserializeUntyped(body); } catch (Exception e) { parsed = null; }

        try{
            List<Call_Log__c> recs = DTORunoCallLogs.toRecords(body);
            if (!recs.isEmpty()) insert recs;
            Call_Log__c c = recs[0];

            Integer dur = c.Duration_Seconds__c == null ? null : Integer.valueOf(c.Duration_Seconds__c);
            RunoEventPublisher.publishCallCompleted(c.Call_Id__c,dur,c.Lead__c,c.Phone_Number__c,'Completed');

            logs.add(IntegrationLogUtil.buildLog('Runo Webhook', envelope, JSON.serialize(parsed), null, 'Received', 200));
            IntegrationLogUtil.insertLogs(logs);
            send(res, 200, true, 'OK');
        }catch(Exception e){
            logs.add(IntegrationLogUtil.buildLog('Runo Webhook', envelope, JSON.serialize(parsed), 'Upsert error: ' + e.getMessage(), 'Failed', 500));
            IntegrationLogUtil.insertLogs(logs);
            send(res, 500, false, 'Upsert error');
        }

        // logs.add(IntegrationLogUtil.buildLog('Runo Webhook', envelope, JSON.serialize(parsed), null, 'Received', 200));
        // IntegrationLogUtil.insertLogs(logs);

        // send(res, 200, true, 'OK');
    }

    private static void send(RestResponse res, Integer code, Boolean ok, String msg) {
        Ack a = new Ack();
        a.success = ok;
        a.message = msg;
        res.statusCode = code;
        res.addHeader('Content-Type', 'application/json');
        res.responseBody = Blob.valueOf(JSON.serialize(a));
    }
}