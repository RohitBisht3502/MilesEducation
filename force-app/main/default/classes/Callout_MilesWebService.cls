/*
    Author      : 
    Description : Sends manual lead data to Data Lake and updates UUID on Lead.
    Used For    : Manual lead sync with Data Lake.
*/
public with sharing class Callout_MilesWebService implements Database.AllowsCallouts {

    public class MilesRequestWrapper {
        public String first_name;
        public String last_name;
        public String country_code;
        public String phone;
        public String email;
        public String city;
        public Integer course_id;
        public String coming_from;
        public Integer campaign_id;
        public String campaign_tk;
        public Boolean whatsapp_opt_in;
        public Boolean call_opt_in;
        public Boolean email_opt_in;
        public Boolean sms_opt_in;
        public Boolean register_for_webinar;
        public String interested_for_work_in_us;
        public String page_full_url;
        public String url_page_path;
        public String nationality;
        public Integer city_id;
        public Boolean is_created_manually;
    }

    public class MilesResponseWrapper {
        public Boolean status;
        public Integer statusCode;
        public String path;
        public MilesResult result;
    }

    public class MilesResult {
        public String uuid;
    }

    @future(callout=true)
    public static void sendLeadToMiles(Id leadId) {
        System.debug('leadId: ' + leadId);

        try {
            Lead__c ld = [SELECT Id, Name, Phone__c, Email__c, City__c, Course__c, Lead__c FROM Lead__c WHERE Id = :leadId LIMIT 1];

            MilesRequestWrapper reqBody = new MilesRequestWrapper();
            reqBody.first_name = ld.Name;
            reqBody.last_name = ld.Name;
            reqBody.country_code = '+91';
            reqBody.phone = ld.Phone__c;
            reqBody.email = ld.Email__c;
            reqBody.city = ld.City__c;
            reqBody.course_id = 1;
            reqBody.coming_from = 'Salesforce';
            reqBody.campaign_id = 1;
            reqBody.campaign_tk = null;
            reqBody.whatsapp_opt_in = true;
            reqBody.call_opt_in = true;
            reqBody.email_opt_in = true;
            reqBody.sms_opt_in = true;
            reqBody.register_for_webinar = false;
            reqBody.interested_for_work_in_us = 'no';
            reqBody.page_full_url = 'https://www.mileseducation.com/contact-us';
            reqBody.url_page_path = '/contact-us';
            reqBody.nationality = 'Indian';
            reqBody.city_id = 8;
            reqBody.is_created_manually = true;

            String requestBody = JSON.serialize(reqBody);
            System.debug('Miles API Request Body: ' + requestBody);

            External_Service_Config__mdt config = [SELECT Endpoint_URL__c, Http_Method__c, Api_Key__c, Api_Key_Header__c, Is_Active__c FROM External_Service_Config__mdt WHERE DeveloperName = 'Miles_Lead_Creation' LIMIT 1];

            if (config == null || !config.Is_Active__c) {
                System.debug('Miles API Config is inactive');
                return;
            }

            Http http = new Http();
            HttpRequest req = new HttpRequest();
            req.setEndpoint(config.Endpoint_URL__c);
            req.setMethod(config.Http_Method__c);
            req.setHeader('Content-Type', 'application/json');
            req.setHeader(config.Api_Key_Header__c, config.Api_Key__c);
            req.setBody(requestBody);

            HttpResponse res = http.send(req);
            String responseBody = res.getBody();

            System.debug('Miles API Response: ' + responseBody);

            if (res.getStatusCode() == 200 || res.getStatusCode() == 201) {
                MilesResponseWrapper responseObj = (MilesResponseWrapper) JSON.deserialize(responseBody, MilesResponseWrapper.class);

                if (responseObj != null && responseObj.result != null) {
                    String uuid = responseObj.result.miles_uuid;

                    if (!String.isBlank(uuid)) {
                        System.debug('UUID FROM API: ' + uuid);
                        System.debug('Candidate Lead Id: ' + ld.Lead__c);

                        if (ld.Lead__c != null) {
                            Lead stdLead = new Lead();
                            stdLead.Id = ld.Lead__c;
                            stdLead.UUID__c = uuid;
                            update stdLead;

                            System.debug('UUID UPDATED IN LEAD');
                        } else {
                            System.debug('Lead Lookup is NULL');
                        }
                    }
                }

                IntegrationLogUtil.insertLogs(new List<Integration_Log__c>{IntegrationLogUtil.buildLog('Miles Callout', requestBody, responseBody, 'Response received from Miles API', 'SUCCESS', res.getStatusCode())});
            } else {
                IntegrationLogUtil.insertLogs(new List<Integration_Log__c>{IntegrationLogUtil.buildLog('Miles Callout', requestBody, responseBody, 'Miles API returned non-success status', 'FAILED', res.getStatusCode())});
            }

        } catch (Exception e) {
            System.debug('Miles Callout Error: ' + e.getMessage());
            IntegrationLogUtil.insertLogs(new List<Integration_Log__c>{IntegrationLogUtil.buildLog('Miles Callout', null, null, 'Error during Miles API Callout: ' + e.getMessage(), 'FAILED', 500)});
        }
    }
}
