public without sharing class Callout_MfSfUntrackToTrackRecording {
    private static final String SERVICE_NAME = 'MF SF Untrack To Track Recording';
    private static final String CONFIG_DEVELOPER_NAME = 'Mf_Sf_Untrack_To_Track_Recording';

    @future(callout=true)
    public static void sendByMilesUuid(String milesUuid) {
        if (String.isBlank(milesUuid)) {
            return;
        }

        String normalizedUuid = milesUuid.trim();
        List<String> callIds = fetchCallIds(normalizedUuid);

        if (callIds.isEmpty()) {
            IntegrationLogUtil.insertLog(SERVICE_NAME, JSON.serialize(new Payload(normalizedUuid, new List<String>())), null, 'No call logs found for miles uuid', 'Failed', null);
            return;
        }

        sendPayload(new Payload(normalizedUuid, callIds));
    }

    private static List<String> fetchCallIds(String milesUuid) {
        Set<String> uniqueCallIds = new Set<String>();

        List<Lead> candidates = [SELECT Id FROM Lead WHERE UUID__c = :milesUuid LIMIT 1];

        if (!candidates.isEmpty()) {
            for (Call_Log__c logRec : [SELECT Call_Id__c FROM Call_Log__c WHERE Candidate__c = :candidates[0].Id AND Call_Id__c != null]) {
                uniqueCallIds.add(logRec.Call_Id__c);
            }
        } else {
            List<Account> students = [SELECT Id FROM Account WHERE UUID__c = :milesUuid LIMIT 1];

            if (!students.isEmpty()) {
                for (Call_Log__c logRec : [SELECT Call_Id__c FROM Call_Log__c WHERE Student__c = :students[0].Id AND Call_Id__c != null]) {
                    uniqueCallIds.add(logRec.Call_Id__c);
                }
            }
        }

        List<String> callIds = new List<String>();
        callIds.addAll(uniqueCallIds);
        return callIds;
    }

    private static void sendPayload(Payload payload) {
        External_Service_Config__mdt cfg = loadConfig();
        String requestPayload = JSON.serialize(payload);

        if (cfg == null || !cfg.Is_Active__c || String.isBlank(cfg.Endpoint_URL__c)) {
            IntegrationLogUtil.insertLog(SERVICE_NAME, requestPayload, null, 'Inactive or missing endpoint', 'Failed', null);
            return;
        }

        HttpRequest req = new HttpRequest();
        req.setEndpoint(cfg.Endpoint_URL__c);
        req.setMethod(String.isBlank(cfg.Http_Method__c) ? 'POST' : cfg.Http_Method__c.trim().toUpperCase());
        req.setHeader('Content-Type', 'application/json');

        if (!String.isBlank(cfg.Api_Key__c) && !String.isBlank(cfg.Api_Key_Header__c)) {
            req.setHeader(cfg.Api_Key_Header__c, cfg.Api_Key__c);
        }

        req.setBody(requestPayload);

        try {
            HttpResponse res = new Http().send(req);
            Integer statusCode = res.getStatusCode();
            String responseBody = truncate(res.getBody());

            if (statusCode >= 200 && statusCode < 300) {
                IntegrationLogUtil.insertLog(SERVICE_NAME, requestPayload, responseBody, 'Success', 'Success', statusCode);
            } else {
                IntegrationLogUtil.insertLog(SERVICE_NAME, requestPayload, responseBody, 'Non-success response', 'Failed', statusCode);
            }
        } catch (Exception e) {
            IntegrationLogUtil.insertLog(SERVICE_NAME, requestPayload, null, 'Callout error: ' + e.getMessage(), 'Failed', null);
        }
    }

    private static External_Service_Config__mdt loadConfig() {
        try {
            return [SELECT Endpoint_URL__c, Http_Method__c, Api_Key__c, Api_Key_Header__c, Is_Active__c FROM External_Service_Config__mdt WHERE DeveloperName = :CONFIG_DEVELOPER_NAME LIMIT 1];
        } catch (Exception e) {
            IntegrationLogUtil.insertLog(SERVICE_NAME, null, null, 'Metadata load error: ' + e.getMessage(), 'Failed', null);
            return null;
        }
    }

    private static String truncate(String value) {
        return (value != null && value.length() > 3000) ? value.substring(0, 3000) : value;
    }

    public class Payload {
        public String miles_uuid;
        public List<String> callIds;

        public Payload(String milesUuid, List<String> callIds) {
            this.miles_uuid = milesUuid;
            this.callIds = callIds;
        }
    }
}