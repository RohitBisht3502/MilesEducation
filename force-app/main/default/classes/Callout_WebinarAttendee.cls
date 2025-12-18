/*
    Author       : ROHIT SINGH BISHT
    Description  : get Live Attendance of Webinars 
*/
public without sharing class Callout_WebinarAttendee {
    
    @AuraEnabled(cacheable=false)
    public static String getLiveWebinarAttendees(String webinarId) {
        try {
            System.debug(LoggingLevel.INFO, 'Webservice_WebinarAttendee.getLiveWebinarAttendees - start, webinarId=' + webinarId);

            if (String.isBlank(webinarId)) {
                throw new AuraHandledException('Error: webinarId is required');
            }

            External_Service_Config__mdt cfg;
            try {
                cfg = [
                    SELECT Endpoint_URL__c, Http_Method__c, Api_Key__c, Api_Key_Header__c, Is_Active__c FROM External_Service_Config__mdt WHERE DeveloperName = 'Webinar_Live_Attendees' LIMIT 1];
            } catch (Exception ex) {
                System.debug(LoggingLevel.ERROR, 'Webservice_WebinarAttendee.getLiveWebinarAttendees - config load failed: ' + ex.getMessage());
                IntegrationLogUtil.insertLog('Webinar Live Attendees', null, null, 'Config load error: ' + ex.getMessage(), 'Failed', null);
                throw ex;
            }

            if (cfg == null || !cfg.Is_Active__c || String.isBlank(cfg.Endpoint_URL__c)) {
                System.debug(LoggingLevel.WARN, 'Webservice_WebinarAttendee.getLiveWebinarAttendees - config inactive or missing Endpoint_URL__c');
                IntegrationLogUtil.insertLog('Webinar Live Attendees', null, null, 'Config inactive or missing Endpoint_URL__c', 'Failed', null);
                throw new AuraHandledException('Error: Config inactive or missing Endpoint_URL__c');
            }

            HttpRequest req = new HttpRequest();
            String method = String.isBlank(cfg.Http_Method__c) ? 'GET' : cfg.Http_Method__c.trim().toUpperCase();
            if (method != 'GET') method = 'GET';
            req.setMethod(method);

            String baseUrl = cfg.Endpoint_URL__c;
            String delimiter = baseUrl != null && baseUrl.contains('?') ? '&' : '?';
            String finalUrl = baseUrl + delimiter + 'webinarId=' + EncodingUtil.urlEncode(webinarId, 'UTF-8');
            req.setEndpoint(finalUrl);

            System.debug(LoggingLevel.INFO, 'Webservice_WebinarAttendee.getLiveWebinarAttendees - callout endpoint=' + finalUrl + ', method=' + method);

            req.setHeader('Content-Type', 'application/json');
            if (!String.isBlank(cfg.Api_Key__c) && !String.isBlank(cfg.Api_Key_Header__c)) {
                req.setHeader(cfg.Api_Key_Header__c, cfg.Api_Key__c);
            }

            Http http = new Http();
            String reqPayload = JSON.serialize(new Map<String, Object>{
                'endpoint' => finalUrl,
                'method' => method
            });
            HttpResponse res = http.send(req);

            Integer statusCode = res.getStatusCode();
            String resBody = res.getBody();
            String trimmedResBody = (resBody != null && resBody.length() > 3000) ? resBody.substring(0, 3000) : resBody;

            System.debug(LoggingLevel.INFO, 'Webservice_WebinarAttendee.getLiveWebinarAttendees - response statusCode=' + statusCode);

            if (statusCode != 200) {
                System.debug(LoggingLevel.WARN, 'Webservice_WebinarAttendee.getLiveWebinarAttendees - non-200 response body=' + trimmedResBody);
                IntegrationLogUtil.insertLog('Webinar Live Attendees', reqPayload, trimmedResBody, 'Non-200 response', 'Failed', statusCode);
                throw new CalloutException('API Error ' + statusCode + ' ' + resBody);
            }

            IntegrationLogUtil.insertLog('Webinar Live Attendees', reqPayload, trimmedResBody, 'Success', 'Success', statusCode);
            return resBody;

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Webservice_WebinarAttendee.getLiveWebinarAttendees - error: ' + e.getMessage());
            IntegrationLogUtil.insertLog('Webinar Live Attendees', null, null, 'Unhandled error: ' + e.getMessage(), 'Failed', null);
            throw new AuraHandledException('Error: ' + e.getMessage());
        }
    }
}