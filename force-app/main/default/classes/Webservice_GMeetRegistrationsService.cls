/*
    Author       : ROHIT SINGH BISHT
    Description  : Send GMeet registration data to AWS
*/
public without sharing class Webservice_GMeetRegistrationsService {

    @future(callout=true)
    public static void sendGMeetRegistrations(Set<Id> eventIds) {
        if (eventIds == null || eventIds.isEmpty()) return;

        External_Service_Config__mdt cfg;
        try {
            cfg = [SELECT Endpoint_URL__c, Http_Method__c, Api_Key__c, Api_Key_Header__c, Is_Active__c FROM External_Service_Config__mdt WHERE DeveloperName = 'GMeet_Registrations' LIMIT 1];
        } catch (Exception e) {
            IntegrationLogUtil.insertLog('GMeet Registrations', null, null, 'Config load error: ' + e.getMessage(), 'Failed', null);
            return;
        }

        if (cfg == null || !cfg.Is_Active__c || String.isBlank(cfg.Endpoint_URL__c)) {
            IntegrationLogUtil.insertLog('GMeet Registrations', null, null, 'Config inactive or missing Endpoint_URL__c', 'Failed', null);
            return;
        }

        String method = String.isBlank(cfg.Http_Method__c) ? 'POST' : cfg.Http_Method__c.trim().toUpperCase();
        if (method != 'POST') method = 'POST';

        List<Event> events = [SELECT Id, ConferenceId__c,StartDateTime, EndDateTime, Location, Meeting_type__c FROM Event WHERE Id IN :eventIds];
        if (events.isEmpty()) return;

        Http http = new Http();

        for (Event ev : events) {
            if (String.isBlank(ev.Location) ||
                String.isBlank(ev.Meeting_type__c) ||
                ev.StartDateTime == null ||
                ev.EndDateTime == null ||
                String.isBlank(ev.Id)) {
                continue;
            }

            String startTimeStr = ev.StartDateTime.format('yyyy-MM-dd\'T\'HH:mm:ssZ');
            String endTimeStr   = ev.EndDateTime.format('yyyy-MM-dd\'T\'HH:mm:ssZ');

            Map<String, Object> payload = new Map<String, Object>{
                'meeting_id'   => ev.ConferenceId__c,
                'sf_id'        => ev.Id,
                'meeting_type' => ev.Meeting_type__c,
                'start_time'   => startTimeStr,
                'end_time'     => endTimeStr
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

                if (code == 200) {
                    IntegrationLogUtil.insertLog('GMeet Registrations', reqBody, trimmedResBody, 'Success', 'Success', code);
                } else {
                    IntegrationLogUtil.insertLog('GMeet Registrations', reqBody, trimmedResBody, 'Non-200 response', 'Failed', code);
                }
            } catch (Exception e) {
                IntegrationLogUtil.insertLog('GMeet Registrations', reqBody, null, 'Callout error: ' + e.getMessage(), 'Failed', null);
            }
        }
    }
}