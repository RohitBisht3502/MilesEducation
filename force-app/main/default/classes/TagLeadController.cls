public with sharing class TagLeadController {

    @AuraEnabled(cacheable=true)
    public static List<Lead__c> searchLeads(String keyword) {
        // Search by Name, Phone, or Candidate ID from standard Lead
        List<Lead__c> results = new List<Lead__c>();
        
        // First, search custom leads directly by Name or Phone
        results = [
            SELECT Id, Name, Email__c, Phone__c, Owner.Name
            FROM Lead__c
            WHERE (Name LIKE :('%' + keyword + '%')
                OR Phone__c LIKE :('%' + keyword + '%'))
            LIMIT 10
        ];
        
        // If no results, search by Candidate ID in standard Lead
        if (results.isEmpty()) {
            List<Lead> standardLeads = [
                SELECT Id, Candidate_ID__c
                FROM Lead
                WHERE Candidate_ID__c LIKE :('%' + keyword + '%')
                LIMIT 10
            ];
            
            if (!standardLeads.isEmpty()) {
                Set<Id> standardLeadIds = new Set<Id>();
                for (Lead stdLead : standardLeads) {
                    standardLeadIds.add(stdLead.Id);
                }
                
                // Find custom leads linked to these standard leads
                results = [
                    SELECT Id, Name, Email__c, Phone__c, Owner.Name
                    FROM Lead__c
                    WHERE Candidate__c IN :standardLeadIds
                    LIMIT 10
                ];
            }
        }
        
        return results;
    }

    @AuraEnabled
    public static void tagOrCreateLead(
        Id callLogId, 
        Id leadId, 
        String name, 
        String course, 
        String email, 
        String phone, 
        Boolean disableRR, 
        String l1, 
        String l2, 
        String feedback,
        String nextFollowUpDate
    ) {
        Lead__c customLeadRecord;
        
        // Get Call Log phone number
        Call_Log__c callLog = [
            SELECT Id, Phone_Number__c
            FROM Call_Log__c
            WHERE Id = :callLogId
            LIMIT 1
        ];

        if (leadId != null) {
            // Tagging existing lead
            customLeadRecord = [SELECT Id, Candidate__c FROM Lead__c WHERE Id = :leadId LIMIT 1];
            
            // Update Call Log with Lead, L1, L2, and Feedback values
            callLog.Lead__c = customLeadRecord.Id;
            callLog.Candidate__c = customLeadRecord.Candidate__c;
            callLog.L1__c = l1;
            callLog.L2__c = l2;
            callLog.Feedback__c = feedback;
            callLog.Untracked__c = false;
            update callLog;

            if (String.isNotBlank(nextFollowUpDate)) {
                callLog.Next_Follow_Up_Date__c = parseUiDateTime(nextFollowUpDate);
                update callLog;
            }
            
            // Update Lead's Next Follow Up Date if provided
            if (String.isNotBlank(nextFollowUpDate)) {
                customLeadRecord.Next_Follow_Up_Date__c = parseUiDateTime(nextFollowUpDate);
                update customLeadRecord;
            }
            
            // Create Phone Number record only if it doesn't exist
            createPhoneNumberRecordIfNotExists(callLog.Phone_Number__c, customLeadRecord.Id);
            
        } else {
            // Creating new lead
            
            // Step 1: Create Standard Lead (Candidate)
            Lead standardLead = new Lead();
            standardLead.LastName = name;
            standardLead.Email = email;
            standardLead.Phone = phone;
            standardLead.Company = 'N/A'; // Required field
            insert standardLead;
            
            // Step 2: Create Custom Lead
            customLeadRecord = new Lead__c();
            customLeadRecord.Name = name;
            customLeadRecord.Course__c = course;
            customLeadRecord.Stage__c = 'M3';
            customLeadRecord.Email__c = email;
            customLeadRecord.Phone__c = phone;
            customLeadRecord.Candidate__c = standardLead.Id;
            customLeadRecord.Disable_Round_Robin__c = disableRR;
            
            // Set Next Follow Up Date if provided
            if (String.isNotBlank(nextFollowUpDate)) {
                customLeadRecord.Next_Follow_Up_Date__c = parseUiDateTime(nextFollowUpDate);
            }
            
            insert customLeadRecord;
            
            // Step 3: Update Call Log with Lead, L1, L2, and Feedback
            callLog.Lead__c = customLeadRecord.Id;
            callLog.L1__c = l1;
            callLog.L2__c = l2;
            callLog.Feedback__c = feedback;
            callLog.Untracked__c = false;
            update callLog;

            if (String.isNotBlank(nextFollowUpDate)) {
                callLog.Next_Follow_Up_Date__c = parseUiDateTime(nextFollowUpDate);
                update callLog;
            }
            
            // Step 4: Create Phone Number record only if it doesn't exist
            createPhoneNumberRecordIfNotExists(callLog.Phone_Number__c, customLeadRecord.Id);
        }
    }
    
    private static void createPhoneNumberRecordIfNotExists(String phoneNumber, Id leadId) {
        if (String.isNotBlank(phoneNumber)) {
            // Check if phone number already exists for this lead
            List<Phone_Number__c> existingPhones = [
                SELECT Id 
                FROM Phone_Number__c 
                WHERE Name = :phoneNumber 
                AND Lead__c = :leadId 
                LIMIT 1
            ];
            
            // Only create if it doesn't exist
            if (existingPhones.isEmpty()) {
                Phone_Number__c phoneRec = new Phone_Number__c();
                phoneRec.Name = phoneNumber;
                phoneRec.Lead__c = leadId;
                insert phoneRec;
            }
        }
    }

    private static DateTime parseUiDateTime(String inputDt) {
        if (String.isBlank(inputDt)) return null;

        String dt = inputDt.replace('T', ' ');

        // If seconds missing, append :00
        if (dt.length() == 16) {
            dt += ':00';
        }

        return DateTime.valueOf(dt);
    }
}