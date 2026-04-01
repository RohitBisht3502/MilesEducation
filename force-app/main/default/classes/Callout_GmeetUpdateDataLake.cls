public without sharing class Callout_GmeetUpdateDataLake {

    private static final String SERVICE_NAME = 'GMeet Update Data Lake';
    private static final String CONFIG_NAME = 'GMeet_Reschedule';
    private static final String STATUS_RESCHEDULED = 'rescheduled';
    private static final String STATUS_CANCELLED = 'cancelled';

    @future(callout=true)
    public static void sendUpdates(List<Id> eventIds) {
        if (eventIds == null || eventIds.isEmpty()) {
            return;
        }

        External_Service_Config__mdt cfg;
        try {
            cfg = [
                SELECT Endpoint_URL__c, Http_Method__c, Api_Key__c, Api_Key_Header__c, Is_Active__c FROM External_Service_Config__mdt WHERE DeveloperName = :CONFIG_NAME LIMIT 1];
        } catch (Exception e) {
            IntegrationLogUtil.insertLog(SERVICE_NAME, null, null, 'Config load error: ' + e.getMessage(), 'Failed', null);
            return;
        }

        if (cfg == null || !cfg.Is_Active__c || String.isBlank(cfg.Endpoint_URL__c)) {
            IntegrationLogUtil.insertLog(SERVICE_NAME, null, null, 'Config inactive or missing Endpoint_URL__c', 'Failed', null);
            return;
        }

        String method = String.isBlank(cfg.Http_Method__c) ? 'POST' : cfg.Http_Method__c.trim().toUpperCase();
        if (method != 'POST') {
            method = 'POST';
        }

        List<Event> events = [SELECT Id, Event_Id__c, ConferenceId__c, Stage__c, StartDateTime, EndDateTime FROM Event WHERE Id IN :eventIds];
        if (events.isEmpty()) {
            return;
        }

        Http http = new Http();

        for (Event ev : events) {
            if (String.isBlank(ev.Event_Id__c)) {
                continue;
            }

            Boolean isCancelled = isCancelledStage(ev.Stage__c);

            Map<String, Object> payload = new Map<String, Object>{
                'event_id' => ev.Event_Id__c,
                'status' => isCancelled ? STATUS_CANCELLED : STATUS_RESCHEDULED,
                'start_time' => formatDateTimeForDataLake(ev.StartDateTime),
                'end_time' => formatDateTimeForDataLake(ev.EndDateTime)
            };

            String reqBody = JSON.serialize(payload);

            HttpRequest req = new HttpRequest();
            req.setEndpoint(cfg.Endpoint_URL__c);
            req.setMethod(method);
            req.setHeader('Content-Type', 'application/json');
            if (!String.isBlank(cfg.Api_Key__c) && !String.isBlank(cfg.Api_Key_Header__c)) {
                req.setHeader(cfg.Api_Key_Header__c, cfg.Api_Key__c);
            }
            req.setBody(reqBody);

            try {
                HttpResponse res = http.send(req);
                Integer code = res.getStatusCode();
                String resBody = res.getBody();
                String trimmedResBody = resBody != null && resBody.length() > 3000 ? resBody.substring(0, 3000) : resBody;

                if (code >= 200 && code < 300) {
                    IntegrationLogUtil.insertLog(SERVICE_NAME, reqBody, trimmedResBody, 'Success', 'Success', code);
                } else {
                    IntegrationLogUtil.insertLog(SERVICE_NAME, reqBody, trimmedResBody, 'Non-2xx response', 'Failed', code);
                }
            } catch (Exception e) {
                IntegrationLogUtil.insertLog(SERVICE_NAME, reqBody, null, 'Callout error: ' + e.getMessage(), 'Failed', null);
            }
        }
    }

    private static Boolean isCancelledStage(String stageValue) {
        return stageValue == 'Cancelled' || stageValue == 'Canceled';
    }

    private static String formatDateTimeForDataLake(Datetime value) {
        return value == null ? null : value.format('yyyy-MM-dd\'T\'HH:mm:ssZ', 'Asia/Kolkata');
    }
}