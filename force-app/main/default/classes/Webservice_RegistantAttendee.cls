/*
    Author       : Salesforce ADMIN
    Description  : Get registrant details for a particular webinar
*/
public without sharing class Webservice_RegistantAttendee {

    public class PollResponse {
        @AuraEnabled public String question;
        @AuraEnabled public String answer;
        @AuraEnabled public String date_time;
        @AuraEnabled public String pollType;
    }

    public class RegistrantResponse {
        @AuraEnabled public String candidateId;
        @AuraEnabled public String email;
        @AuraEnabled public String webinarId;
        @AuraEnabled public Integer duration;
        @AuraEnabled public String joinedAt;
        @AuraEnabled public String leftAt;
        @AuraEnabled public List<PollResponse> pollResponses;
    }

    public class WebinarApiResponse {
        @AuraEnabled public Boolean success;
        @AuraEnabled public Integer count;
        @AuraEnabled public List<RegistrantResponse> data;
    }

    @AuraEnabled(cacheable=false)
    public static RegistrantResponse fetchLeadData(String registrantId) {

        String reqPayload;
        String resBody;

        try {

            if (String.isBlank(registrantId)) {
                throw new AuraHandledException('Registrant Id is required');
            }

            List<External_Service_Config__mdt> cfgList = [SELECT Endpoint_URL__c, Http_Method__c, Api_Key__c, Api_Key_Header__c, Is_Active__c FROM External_Service_Config__mdt WHERE DeveloperName = 'Webinar_Registrant_Details' LIMIT 1];

            if (cfgList.isEmpty() || !cfgList[0].Is_Active__c) {
                throw new AuraHandledException('Service configuration is inactive');
            }

            External_Service_Config__mdt cfg = cfgList[0];

            HttpRequest req = new HttpRequest();

            String endpoint = cfg.Endpoint_URL__c;
            String encodedRegistrantId = EncodingUtil.urlEncode(registrantId, 'UTF-8');
            if (!String.isBlank(endpoint)) {
                if (endpoint.contains('?')) {
                    if (!endpoint.endsWith('?') && !endpoint.endsWith('&')) endpoint += '&';
                } else {
                    endpoint += '?';
                }
                endpoint += 'registrantId=' + encodedRegistrantId;
            }
            req.setEndpoint(endpoint);

            req.setMethod(String.isBlank(cfg.Http_Method__c) ? 'POST' : cfg.Http_Method__c);
            req.setHeader('Content-Type', 'application/json');

            if (!String.isBlank(cfg.Api_Key__c) && !String.isBlank(cfg.Api_Key_Header__c)) {
                req.setHeader(cfg.Api_Key_Header__c, cfg.Api_Key__c);
            }

            Http http = new Http();
            HttpResponse res = http.send(req);
            resBody = res.getBody();

            IntegrationLogUtil.insertLog('Registrant Details', reqPayload, resBody != null && resBody.length() > 3000 ? resBody.substring(0, 3000) : resBody, res.getStatus(), res.getStatusCode() == 200 ? 'Success' : 'Failed', res.getStatusCode() );

            if (res.getStatusCode() != 200) {
                throw new AuraHandledException('API Error: ' + res.getStatus());
            }

            WebinarApiResponse apiResponse = (WebinarApiResponse) JSON.deserialize(resBody, WebinarApiResponse.class);

            if (apiResponse == null || apiResponse.data == null || apiResponse.data.isEmpty()) {
                throw new AuraHandledException('No registrant data found');
            }

            RegistrantResponse response = apiResponse.data[0];

            if (response.pollResponses == null) {
                response.pollResponses = new List<PollResponse>();
            }

            return response;

        } catch (Exception e) {

            IntegrationLogUtil.insertLog('Registrant Details', reqPayload, e.getMessage(), 'Exception', 'Failed', null );

            throw new AuraHandledException(e.getMessage());
        }
    }
}