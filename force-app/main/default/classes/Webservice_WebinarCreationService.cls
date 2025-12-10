/**
*   Author : Rohit Singh Bisht
**/ 
@RestResource(urlMapping='/webinar/createOrUpdate')
global without sharing class Webservice_WebinarCreationService {

    public class ZoomWebinarDTO {
        public String id;              
        public String topic;
        public String agenda;
        public String start_time;
        public Boolean auto_register;
        public String webinar_name;     
    }

    global class WebinarUpsertResponse {
        public Boolean success;
        public String message;
        public Id webinarRecordId;
        public Boolean updated;
    }

    @HttpPost
    global static WebinarUpsertResponse upsertWebinarFromDataLake() {
        WebinarUpsertResponse resp = new WebinarUpsertResponse();
        RestRequest req = RestContext.request;

        if (req == null || req.requestBody == null) {
            resp.success = false;
            resp.message = 'Empty request body';
            return resp;
        }

        ZoomWebinarDTO input;
        try {
            input = (ZoomWebinarDTO)
                JSON.deserialize(req.requestBody.toString(), ZoomWebinarDTO.class);
        } catch (Exception e) {
            resp.success = false;
            resp.message = 'Invalid JSON: ' + e.getMessage();
            return resp;
        }

        if (input == null || String.isBlank(input.id)) {
            resp.success = false;
            resp.message = 'Field "id" (Zoom webinar id) is required';
            return resp;
        }

        try {
            Webinar__c wb;
            Boolean isUpdate = false;

            try {
                wb = [ SELECT Id,Name, Webinar_Id__c,IsActive__c, Topic__c, Agenda__c, Start_Date_Time__c, Auto_Register__c FROM Webinar__c  WHERE Webinar_Id__c = :input.id  LIMIT 1];
                isUpdate = true;
            } catch (QueryException qe) {
                wb = new Webinar__c();
                wb.Webinar_Id__c = input.id;
                isUpdate = false;
            }

            if (input.topic != null) wb.Topic__c = input.topic;
            if (input.agenda != null) wb.Agenda__c = input.agenda;
            if (input.start_time != null) wb.Start_Date_Time__c = parseIsoToDatetime(input.start_time);
            if (input.auto_register != null) wb.Auto_Register__c = input.auto_register;
            if (input.webinar_name != null) wb.Name = input.webinar_name;

			wb.IsActive__c = True;
            if (isUpdate) update wb;
            else insert wb;

            resp.success = true;
            resp.updated = isUpdate;
            resp.webinarRecordId = wb.Id;
            resp.message = isUpdate ? 'Webinar updated successfully' : 'Webinar created successfully';

        } catch (Exception e) {
            resp.success = false;
            resp.message = 'Error while creating/updating webinar: ' + e.getMessage();
        }

        return resp;
    }

    public static Datetime parseIsoToDatetime(String isoString) {
        if (String.isBlank(isoString)) return null;
        return Datetime.valueOf(isoString.replace('T', ' ').replace('Z', ''));
    }
}