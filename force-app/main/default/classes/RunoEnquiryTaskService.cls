public without sharing class RunoEnquiryTaskService {
    public static void handle(String callType, String phone, String firstName, String email, String userPhone) {
        if (String.isBlank(callType) || String.isBlank(phone)) return;
        String t = callType.toLowerCase();
        if (t != 'incoming' && t != 'missed') return;

        Lead__c linkedLeadC;
        Boolean anyFound = false;
        Id ownerId;

        try {
            List<Lead__c> leadCs = [SELECT Id FROM Lead__c WHERE Phone__c = :phone LIMIT 1];
            if (!leadCs.isEmpty()) {
                linkedLeadC = leadCs[0];
                anyFound = true;
            }
        } catch (Exception e) {}

        try {
            List<Lead> stdLeads = [SELECT Id FROM Lead WHERE Phone = :phone LIMIT 1];
            if (!stdLeads.isEmpty()) anyFound = true;
        } catch (Exception e) {}

        try {
            List<Account> accts = [SELECT Id FROM Account WHERE Phone = :phone LIMIT 1];
            if (!accts.isEmpty()) anyFound = true;
        } catch (Exception e) {}

        try {
            if (!String.isBlank(userPhone)) {
                List<User> owners = [ SELECT Id FROM User WHERE Phone LIKE :('%' + userPhone) OR MobilePhone LIKE :('%' + userPhone) LIMIT 1];
                if (!owners.isEmpty()) {
                    ownerId = owners[0].Id;
                }
            }
        } catch (Exception e) {

        }

        Enquiry__c enquiry = new Enquiry__c(
            Name            = String.isBlank(firstName) ? phone : firstName,
            First_Name__c   = firstName,
            Phone_Number__c = phone,
            Email__c        = email,
            Stage__c        = anyFound ? 'Tracked' : 'Untracked'
        );
        if (linkedLeadC != null) {
            enquiry.Lead__c = linkedLeadC.Id;
        }
        if (ownerId != null) {
            enquiry.OwnerId = ownerId;
        }

        insert enquiry;

        if (anyFound) {
            String subject = 'Follow Up Call (Runo - ' + t + ')';
            Task tsk = MilesExistingEnquiryWebService.createFollowUpTask(enquiry, subject);
        }
    }
}