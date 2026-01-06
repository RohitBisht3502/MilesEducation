// Developer Name : Chirag Sharma 
// Created Date : 26/11/2025
// Last Modified by : Chirag Sharma
// Last Modified Date : 28/11/2025

public with sharing class LeadActivityTimelineController {

    public class ActivityLogDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String activityType;
        @AuraEnabled public String loggingId;
        @AuraEnabled public Decimal availCreditScore;
        @AuraEnabled public String l1;
        @AuraEnabled public String l2;
        @AuraEnabled public Decimal callDurationSeconds;
        @AuraEnabled public String callRecordingUrl;
        @AuraEnabled public String previousLevel;
        @AuraEnabled public String newLevel;
        @AuraEnabled public String actionByName;
        @AuraEnabled public Datetime changedDateTime;
        @AuraEnabled public String description;
        @AuraEnabled public String callLogType; 
        @AuraEnabled public String createdByText; // 👈 NEW
    }

    public class LeadActivityResponse {
        @AuraEnabled public Id leadId;
        @AuraEnabled public String name;
        @AuraEnabled public String phone;
        @AuraEnabled public String email;
        @AuraEnabled public String city;
        @AuraEnabled public String course;
        @AuraEnabled public String source;
        @AuraEnabled public String createdByName;
        @AuraEnabled public List<ActivityLogDTO> logs;
    }

    @AuraEnabled(cacheable=true)
    public static LeadActivityResponse getLeadActivityData(Id leadId) {
        if (leadId == null) {
            return null;
        }

        Lead__c ld = [
            SELECT Id,
                   Name,
                   Phone__c,
                   Email__c,
                   City__c,
                   Course__c,
                   Source__c,
                   CreatedBy.Name
            FROM Lead__c
            WHERE Id = :leadId
            LIMIT 1
        ];

        List<Activity_Log__c> logs = [
            SELECT Id,
                   Name,
                   Activity_Type__c,
            	   Available_Credit_Score__c,
                   Logging_Id__c,
                   Lead__c,
                   L1__c,
                   L2__c,
                   Call_Duration_Seconds__c,
                   Call_Recording_URL__c,
                   Previous_Level__c,
                   New_Level__c,
                   Action_Performed_By__r.Name,
                   Changed_Date_Time__c,
                   Description__c,
                   Created_By__c,
                   Call_Log_Type__c,          // 👈 NEW
                   CreatedDate
            FROM Activity_Log__c
            WHERE Lead__c = :leadId
            ORDER BY CreatedDate DESC
        ];

        LeadActivityResponse resp = new LeadActivityResponse();
        resp.leadId        = ld.Id;
        resp.name          = ld.Name;
        resp.phone         = ld.Phone__c;
        resp.email         = ld.Email__c;
        resp.city          = ld.City__c;
        resp.course        = ld.Course__c;
        resp.source        = ld.Source__c;
        resp.createdByName = ld.CreatedBy != null ? ld.CreatedBy.Name : null;

        resp.logs = new List<ActivityLogDTO>();
        for (Activity_Log__c al : logs) {
            ActivityLogDTO dto      = new ActivityLogDTO();
            dto.id                  = al.Id;
            dto.name                = al.Name;
            dto.activityType        = al.Activity_Type__c;
            dto.availCreditScore    = al.Available_Credit_Score__c;
            dto.loggingId			= al.Logging_Id__c;
            dto.l1                  = al.L1__c;
            dto.l2                  = al.L2__c;
            dto.callDurationSeconds = al.Call_Duration_Seconds__c;
            dto.callRecordingUrl    = al.Call_Recording_URL__c;
            dto.previousLevel       = al.Previous_Level__c;
            dto.newLevel            = al.New_Level__c;
            dto.actionByName        = al.Action_Performed_By__r != null ? al.Action_Performed_By__r.Name : null;
            dto.changedDateTime     = al.Changed_Date_Time__c;
            dto.description         = al.Description__c;
            dto.createdByText       = al.Created_By__c;
            dto.callLogType         = al.Call_Log_Type__c;
            resp.logs.add(dto);
        }

        return resp;
    }
}