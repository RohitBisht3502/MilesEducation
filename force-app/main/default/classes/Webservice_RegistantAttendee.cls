/*
    Author       : Salesforce ADMIN
    Description  : Get registrant details for a particular webinar
*/
public without sharing class Webservice_RegistantAttendee {

    /* ================= DTO CLASSES ================= */

    public class PollResponse {
        @AuraEnabled public String question;
        @AuraEnabled public String answer;
        @AuraEnabled public String date_time;
        @AuraEnabled public String pollType;
    }

    public class RegistrantResponse {
        @AuraEnabled public String registrantId;
        @AuraEnabled public String candidateId;
        @AuraEnabled public String email;
        @AuraEnabled public String webinarId;
        @AuraEnabled public Integer duration;
        @AuraEnabled public String joinedAt;
        @AuraEnabled public String leftAt;
        @AuraEnabled public List<PollResponse> pollResponses;
    }

    /* ================= MAIN METHOD ================= */

    @AuraEnabled(cacheable=false)
    public static RegistrantResponse fetchLeadData(String registrantId) {

        String reqPayload;
        String resBody;

        try {

            if (String.isBlank(registrantId)) {
              //  throw new AuraHandledException('Registrant Id is required');
            }

            /* ===== Load Config ===== */
            // List<External_Service_Config__mdt> cfgList = [
            //     SELECT Endpoint_URL__c, Http_Method__c, Api_Key__c,
            //            Api_Key_Header__c, Is_Active__c
            //     FROM External_Service_Config__mdt
            //     WHERE DeveloperName = 'Webinar_Registrant_Details'
            //     LIMIT 1
            // ];

            // if (cfgList.isEmpty() || !cfgList[0].Is_Active__c) {
            //    // throw new AuraHandledException('Service configuration is inactive');
            // }

            // External_Service_Config__mdt cfg = cfgList[0];

            // /* ===== Prepare Callout ===== */
            // HttpRequest req = new HttpRequest();
            // req.setEndpoint(cfg.Endpoint_URL__c);
            // req.setMethod(String.isBlank(cfg.Http_Method__c) ? 'POST' : cfg.Http_Method__c);
            // req.setHeader('Content-Type', 'application/json');

            // if (!String.isBlank(cfg.Api_Key__c) && !String.isBlank(cfg.Api_Key_Header__c)) {
            //     req.setHeader(cfg.Api_Key_Header__c, cfg.Api_Key__c);
            // }

            // reqPayload = JSON.serialize(new Map<String, String>{
            //     'registrantId' => registrantId
            // });

            // req.setBody(reqPayload);

            // Http http = new Http();
            // HttpResponse res = http.send(req);
            // resBody = res.getBody();

            // /* ===== Integration Log ===== */
            // IntegrationLogUtil.insertLog(
            //     'Registrant Details',
            //     reqPayload,
            //     resBody != null && resBody.length() > 3000
            //         ? resBody.substring(0, 3000)
            //         : resBody,
            //     res.getStatus(),
            //     res.getStatusCode() == 200 ? 'Success' : 'Failed',
            //     res.getStatusCode()
            // );

            // if (res.getStatusCode() != 200) {
            //     throw new AuraHandledException('API Error: ' + res.getStatus());
            // }

            // RegistrantResponse response =
            //     (RegistrantResponse) JSON.deserialize(resBody, RegistrantResponse.class);

            // // 🔒 Safety for LWC
            // if (response.pollResponses == null) {
            //     response.pollResponses = new List<PollResponse>();
            // }

                        /* =========================
               FAKE RESPONSE FOR NOW
               ========================= */
            RegistrantResponse fake = new RegistrantResponse();
            fake.registrantId = 'lVsn8VlJQiCbMx1XhRCqYg';
            fake.candidateId  = '00QC100000G20NiMAJ';
            fake.email        = 'rohit.bisht@utilitarianlabs.com';
            fake.webinarId    = '94507930573';
            fake.duration     = 883;
            fake.joinedAt     = '2025-12-16T11:26:07Z';
            fake.leftAt       = null;

            fake.pollResponses = new List<PollResponse>();

            PollResponse p1 = new PollResponse();
            p1.question  = 'Heath Co.’s current ratio is 4:1. Which of the following transactions would normally increase its current ratio?';
            p1.answer    = 'Selling inventory on account.';
            p1.date_time = '2025-12-14 14:17:35';
            p1.pollType  = 'single_choice';
            fake.pollResponses.add(p1);

            PollResponse p2 = new PollResponse();
            p2.question  = 'Have you received your Miles online access [this is subject to realization of your fee payment]?';
            p2.answer    = 'Yes';
            p2.date_time = '2025-12-14 12:27:21';
            p2.pollType  = 'single_choice';
            fake.pollResponses.add(p2);

            PollResponse p3 = new PollResponse();
            p3.question  = 'How many years of work-ex do you have (including any articleship work-ex) ?';
            p3.answer    = '0-5 years work ex';
            p3.date_time = '2025-12-14 12:17:28';
            p3.pollType  = 'single_choice';
            fake.pollResponses.add(p3);

            // Optional log so you can confirm method is being hit
            reqPayload = JSON.serialize(new Map<String, String>{ 'registrantId' => registrantId });
            resBody = JSON.serialize(fake);
             return fake;

            //return response;

        } catch (Exception e) {

            IntegrationLogUtil.insertLog(
                'Registrant Details',
                reqPayload,
                e.getMessage(),
                'Exception',
                'Failed',
                null
            );

            throw new AuraHandledException(e.getMessage());
        }
    }
}