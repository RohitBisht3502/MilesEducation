public without sharing class Webservice_WebinarRegistrationsService {

    @future(callout=true)
    public static void sendWebinarRegistrations(Set<Id> webinarMemberIds) {
        if (webinarMemberIds == null || webinarMemberIds.isEmpty()) return;

        External_Service_Config__mdt cfg;
        try {
            cfg = [SELECT Endpoint_URL__c, Http_Method__c, Api_Key__c, Api_Key_Header__c, Is_Active__c FROM External_Service_Config__mdt WHERE DeveloperName = 'Webinar_Registrations' LIMIT 1];
        } catch (Exception e) {
            IntegrationLogUtil.insertLog('Webinar Registrations', null, null, 'Config load error: ' + e.getMessage(), 'Failed', null);
            return;
        }

        if (cfg == null || !cfg.Is_Active__c || String.isBlank(cfg.Endpoint_URL__c)) {
            IntegrationLogUtil.insertLog('Webinar Registrations', null, null, 'Config inactive or missing Endpoint_URL__c', 'Failed', null);
            return;
        }

        String method = String.isBlank(cfg.Http_Method__c) ? 'POST' : cfg.Http_Method__c.trim().toUpperCase();
        if (method != 'POST') method = 'POST';

        List<Webinar_Member__c> members = [
            SELECT Id, Lead__r.Candidate__c,Webinar__r.Webinar_Id__c, Registrant_Id__c FROM Webinar_Member__c WHERE Id IN :webinarMemberIds];
        if (members.isEmpty()) return;

        Http http = new Http();

        for (Webinar_Member__c wm : members) {

            if (String.isBlank(wm.Lead__c) ||
                String.isBlank(wm.Webinar__r.Webinar_Id__c) ||
                String.isBlank(wm.Registrant_Id__c) ||
                String.isBlank((String)wm.Id)) {
                continue;
            }

            Map<String, Object> payload = new Map<String, Object>{
                'CandidateId'          => wm.Lead__r.Candidate__c,
                'Zoom_webinar_id'      => wm.Webinar__r.Webinar_Id__c,
                'Zoom_registration_id' => wm.Registrant_Id__c
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
                String trimmedResBody = (resBody != null && resBody.length() > 3000) ? resBody.substring(0, 3000) : resBody;

                if (code == 200) {
                    IntegrationLogUtil.insertLog('Webinar Registrations', reqBody, trimmedResBody, 'Success', 'Success', code);
                } else {
                    IntegrationLogUtil.insertLog('Webinar Registrations', reqBody, trimmedResBody, 'Non-200 response', 'Failed', code);
                }
            } catch (Exception e) {
                IntegrationLogUtil.insertLog('Webinar Registrations', reqBody, null, 'Callout error: ' + e.getMessage(), 'Failed', null);
            }
        }
    }
}