/*
    Author       : ROHIT SINGH BISHT
    Description  : 
*/
public without sharing class RunoEnquiryTaskService {
    public static void handle(Call_Log__c callLog) {
        if (callLog == null) return;
        String callType = callLog.Type__c;
        String phone = callLog.Phone_Number__c;
        String firstName = callLog.Customer_Name__c;
        String userPhone = callLog.User_Phone__c;

        if (String.isBlank(callType) || String.isBlank(phone)) return;
        String t = callType.toLowerCase();
        if (t != 'incoming' && t != 'missed') return;

        Boolean anyFound = false;
        Id ownerId;

        try {
            List<Lead__c> leadCs = [ SELECT Id FROM Lead__c WHERE Phone__c = :phone LIMIT 1 ];
            if (!leadCs.isEmpty()) anyFound = true;
        } catch (Exception e) {}

        try {
            List<Lead> stdLeads = [ SELECT Id FROM Lead WHERE Phone = :phone LIMIT 1];
            if (!stdLeads.isEmpty()) anyFound = true;
        } catch (Exception e) {}

        try {
            List<Account> accts = [ SELECT Id FROM Account WHERE Phone = :phone LIMIT 1 ];
            if (!accts.isEmpty()) anyFound = true;
        } catch (Exception e) {}

        try {
            if (!String.isBlank(userPhone)) {
                List<User> owners = [SELECT Id FROM User WHERE Phone LIKE :('%' + userPhone) OR MobilePhone LIKE :('%' + userPhone) LIMIT 1];
                if (!owners.isEmpty()) ownerId = owners[0].Id;
            }
        } catch (Exception e) {}

        String subject = 'Follow Up Call (Runo - ' + t + ', ' + (anyFound ? 'Tracked' : 'Untracked') + ')';

        MilesExistingEnquiryWebService.createFollowUpTask(callLog, subject, ownerId);
    }
}