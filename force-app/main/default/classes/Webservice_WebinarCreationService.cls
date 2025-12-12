/**
*   Author : Rohit Singh Bisht
**/ 
@RestResource(urlMapping='/webinar/create')
global without sharing class Webservice_WebinarCreationService {

    public class ZoomWebinarDTO {
        public String id;              
        public String topic;
        public String agenda;
        public String start_time;
        public Boolean auto_register;
        public Integer duration;
        public String webinar_name;     
    }

    global class WebinarUpsertResponse {
        public Boolean success;
        public String message;
        public Id webinarRecordId;
    }

    @HttpPost
    global static WebinarUpsertResponse upsertWebinarFromDataLake() {
        WebinarUpsertResponse resp = new WebinarUpsertResponse();
        RestRequest req = RestContext.request;
        String requestBody = (req != null && req.requestBody != null) ? req.requestBody.toString() : null;
        String trimmedRequestBody = requestBody != null && requestBody.length() > 3000 ? requestBody.substring(0, 3000) : requestBody;

        if (req == null || req.requestBody == null) {
            resp.success = false;
            resp.message = 'Empty request body';
            IntegrationLogUtil.insertLog('Webinar Creation', trimmedRequestBody, null, resp.message, 'Failed', 400);
            return resp;
        }

        ZoomWebinarDTO input;
        try {
            input = (ZoomWebinarDTO)
                JSON.deserialize(req.requestBody.toString(), ZoomWebinarDTO.class);
        } catch (Exception e) {
            resp.success = false;
            resp.message = 'Invalid JSON: ' + e.getMessage();
            IntegrationLogUtil.insertLog('Webinar Creation', trimmedRequestBody, null, resp.message, 'Failed', 400);
            return resp;
        }

        if (input == null || String.isBlank(input.id)) {
            resp.success = false;
            resp.message = 'Field "id" (Zoom webinar id) is required';
            IntegrationLogUtil.insertLog('Webinar Creation', trimmedRequestBody, null, resp.message, 'Failed', 400);
            return resp;
        }

        try {
            Webinar__c wb;

            try {
                wb = [
                    SELECT Id, Name, Webinar_Id__c, IsActive__c, Topic__c, Agenda__c, Start_Date_Time__c, Auto_Register__c, Duration__c
                    FROM Webinar__c WHERE Webinar_Id__c = :input.id LIMIT 1];
                resp.success = false;
                resp.webinarRecordId = wb.Id;
                resp.message = 'Webinar already exists';
                String respJson = JSON.serialize(resp);
                String trimmedRespJson = respJson != null && respJson.length() > 3000 ? respJson.substring(0, 3000) : respJson;
                IntegrationLogUtil.insertLog('Webinar Creation', trimmedRequestBody, trimmedRespJson, resp.message, 'Success', 200);
                return resp;
            } catch (QueryException qe) {
                wb = new Webinar__c();
                wb.Webinar_Id__c = input.id;
            }

            if (input.topic != null) wb.Topic__c = input.topic;
            if (input.agenda != null) wb.Agenda__c = input.agenda;
            if (input.start_time != null) wb.Start_Date_Time__c = parseIsoToDatetime(input.start_time);
            if (input.auto_register != null) wb.Auto_Register__c = input.auto_register;
            if (input.webinar_name != null) wb.Name = input.webinar_name;
            if (input.duration != null) wb.Duration__c = input.duration;

            wb.IsActive__c = true;
            insert wb;

            resp.success = true;
            resp.webinarRecordId = wb.Id;
            resp.message = 'Webinar created successfully';
            String respJson = JSON.serialize(resp);
            String trimmedRespJson = respJson != null && respJson.length() > 3000 ? respJson.substring(0, 3000) : respJson;
            IntegrationLogUtil.insertLog('Webinar Creation', trimmedRequestBody, trimmedRespJson, resp.message, 'Success', 200);

        } catch (Exception e) {
            resp.success = false;
            resp.message = 'Error while creating/updating webinar: ' + e.getMessage();
            String respJson = JSON.serialize(resp);
            String trimmedRespJson = respJson != null && respJson.length() > 3000 ? respJson.substring(0, 3000) : respJson;
            IntegrationLogUtil.insertLog('Webinar Creation', trimmedRequestBody, trimmedRespJson, resp.message, 'Failed', 500);
        }

        return resp;
    }

    public static Datetime parseIsoToDatetime(String isoString) {
        if (String.isBlank(isoString)) return null;
        return Datetime.valueOf(isoString.replace('T', ' ').replace('Z', ''));
    }
}