/*
    Author       : ROHIT SINGH BISHT
    Description  : 
*/
@RestResource(urlMapping='/rrr/call-log2/*')
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

        // Load Metadata Config
        External_Service_Config__mdt cfg;
        try {
            cfg = [
                SELECT Api_Key__c, Api_Key_Header__c, Is_Active__c 
                FROM External_Service_Config__mdt 
                WHERE DeveloperName = 'Runo_Webhook' 
                LIMIT 1
            ];
        } catch (Exception e) {
            logs.add(IntegrationLogUtil.buildLog('Runo Webhook', envelope, null, 'Config load error: '+e.getMessage(), 'Failed', 500));
            IntegrationLogUtil.insertLogs(logs);
            send(res, 500, false, 'Config load error');
            return;
        }

        String expectedHeader = cfg != null ? cfg.Api_Key_Header__c : null;
        String expectedToken  = cfg != null ? cfg.Api_Key__c        : null;
        String providedToken  = (headers != null && expectedHeader != null) ? headers.get(expectedHeader) : null;

        // Optional security check
        // (disabled for now as per your current code)

        Object parsed;
        try { parsed = JSON.deserializeUntyped(body); } 
        catch (Exception e) { parsed = null; }

        try {

        List<Call_Log__c> recs = DTORunoCallLogs.toRecords(body);

        if (recs.isEmpty()) {
            throw new AuraHandledException('DTO returned empty logs – check payload structure.');
        }

        Set<Id> outgoingCandidateIds = new Set<Id>();
        for (Call_Log__c rec : recs) {
            if (rec.Candidate__c != null &&
                rec.Type__c != null &&
                rec.Type__c.toLowerCase().contains('outgoing')) {
                outgoingCandidateIds.add(rec.Candidate__c);
            }
        }

        Map<Id, Id> latestLogIdByCandidate = new Map<Id, Id>();
        if (!outgoingCandidateIds.isEmpty()) {
            for (Call_Log__c existing : [
                SELECT Id, Lead__c,Candidate__c
                FROM Call_Log__c
                WHERE Candidate__c IN :outgoingCandidateIds
                ORDER BY Candidate__c, CreatedDate DESC
            ]) {
                if (!latestLogIdByCandidate.containsKey(existing.Candidate__c)) {
                    latestLogIdByCandidate.put(existing.Candidate__c, existing.Id);
                }
            }
        }

        for (Call_Log__c rec : recs) {
            if (rec.Candidate__c != null &&
                rec.Type__c != null &&
                rec.Type__c.toLowerCase().contains('outgoing')) {

                Id existingId = latestLogIdByCandidate.get(rec.Candidate__c);
                if (existingId != null) {
                    rec.Id = existingId; // upsert will UPDATE this record
                }
            }
        }

        upsert recs;
        System.debug(recs);

            Call_Log__c c = recs[0];
            System.debug( c.Lead__c);
            Integer dur = c.Duration_Seconds__c != null ? Integer.valueOf(c.Duration_Seconds__c) : null;

            // Un-comment this if event publisher is required
            RunoEventPublisher.publishCallCompleted(c.Call_Id__c, dur, c.Lead__c, c.Candidate__c, c.Phone_Number__c, 'Completed');

            String callType = null;
            String phoneFromPayload = null;
            String firstNameFromPayload = null;
            String emailFromPayload = null;

            if (parsed instanceof Map<String, Object>) {
                Map<String, Object> m = (Map<String, Object>) parsed;

                callType = String.valueOf(m.get('type'));
                phoneFromPayload = String.valueOf(m.get('phoneNumber'));
                firstNameFromPayload = String.valueOf(m.get('name'));
                emailFromPayload = String.valueOf(m.get('email'));
            }

            if (String.isBlank(callType)) {
                try { callType = (String) c.get('Call_Type__c'); } catch (Exception ignore) {}
            }

            if (String.isBlank(phoneFromPayload)) {
                phoneFromPayload = c.Phone_Number__c;
            }

            RunoEnquiryTaskService.handle(callType, phoneFromPayload, firstNameFromPayload, emailFromPayload);

            logs.add(IntegrationLogUtil.buildLog('Runo Webhook', envelope, JSON.serialize(parsed), null, 'Received', 200));
            IntegrationLogUtil.insertLogs(logs);
            send(res, 200, true, 'OK');

        } catch (Exception e) {
            logs.add(IntegrationLogUtil.buildLog('Runo Webhook', envelope, JSON.serialize(parsed), 'Upsert error: '+e.getMessage(), 'Failed', 500));
            IntegrationLogUtil.insertLogs(logs);
            send(res, 500, false, 'Upsert error');
        }
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