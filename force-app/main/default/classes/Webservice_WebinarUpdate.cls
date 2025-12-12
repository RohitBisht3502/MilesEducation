/**
*   Author : Rohit Singh Bisht
**/ 
@RestResource(urlMapping='/webinar/update')
global without sharing class Webservice_WebinarUpdate {

    global class WebinarUpdateRequest {
        public String webinarId;
        public Datetime startDateTime;
        public Integer duration;
        public String status;
    }

    global class WebinarUpdateResponse {
        public Boolean success;
        public String message;
    }

    @HttpPost
    global static WebinarUpdateResponse updateWebinar() {
        WebinarUpdateResponse resp = new WebinarUpdateResponse();
        RestRequest req = RestContext.request;

        if (req == null || req.requestBody == null) {
            resp.success = false;
            resp.message = 'Empty request body';
            return resp;
        }

        WebinarUpdateRequest input;
        try {
            input = (WebinarUpdateRequest) JSON.deserialize(req.requestBody.toString(), WebinarUpdateRequest.class);
        } catch (Exception e) {
            resp.success = false;
            resp.message = 'Invalid JSON: ' + e.getMessage();
            return resp;
        }

        if (input == null || input.webinarId == null) {
            resp.success = false;
            resp.message = 'webinarId is required';
            return resp;
        }

        // if (input.startDateTime == null && input.duration == null) {
        //     resp.success = false;
        //     resp.message = 'Provide at least startDateTime or duration';
        //     return resp;
        // }

        try {
            Webinar__c wb = [SELECT Id,Webinar_Id__c, Start_Date_Time__c, Duration__c, Status__c  FROM Webinar__c WHERE Webinar_Id__c = :input.webinarId LIMIT 1];

            if (input.startDateTime != null) {
                wb.Start_Date_Time__c = input.startDateTime;
            }
            if (input.duration != null) {
                wb.Duration__c = input.duration;
            }
            if (input.status != null) {
                wb.Status__c = input.status;
            }

            update wb;

            resp.success = true;
            resp.message = 'Webinar updated successfully';
        } catch (QueryException qe) {
            resp.success = false;
            resp.message = 'Webinar not found for Id: ' + String.valueOf(input.webinarId);
        } catch (Exception e) {
            resp.success = false;
            resp.message = 'Error while updating webinar: ' + e.getMessage();
        }

        return resp;
    }
}