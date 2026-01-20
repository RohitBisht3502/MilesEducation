public with sharing class MComBulkUploadController {
    
    public class UploadResult {
        @AuraEnabled public Integer successCount;
        @AuraEnabled public Integer errorCount;
        @AuraEnabled public List<String> messages;
        @AuraEnabled public List<String> notFoundEmails;
    }

    @AuraEnabled
    public static UploadResult processMComEnrollment(List<String> emails) {
        UploadResult result = new UploadResult();
        result.messages = new List<String>();
        result.notFoundEmails = new List<String>();
        result.successCount = 0;
        result.errorCount = 0;

        if (emails == null || emails.isEmpty()) {
            result.messages.add('No emails provided.');
            return result;
        }

        // Clean (lowercase, trim)
        Set<String> emailSet = new Set<String>();
        for (String e : emails) {
            if (String.isNotBlank(e)) emailSet.add(e.trim().toLowerCase());
        }
        
        System.debug('Processing ' + emailSet.size() + ' unique emails for M.Com enrollment.');

        // Find Matching M.Com Leads
        // STRICT FILTER: Course__c = 'MCOM' (and optionally RecordType)
        // Note: We Lowercase email for matching to be safe
        List<Lead__c> leadsToUpdate = [
            SELECT Id, Email__c, Stage__c, Name 
            FROM Lead__c 
            WHERE Course__c = 'MCOM' 
            AND Email__c != null
        ];

        // Filter in memory for case-insensitive email matching (SOQL is case-insensitive usually, but using Set contains is strict)
        // Let's rely on SOQL IN :emailSet? SOQL is case insensitive.
        // Actually, let's query WHERE Email__c IN :emailSet.
        
        leadsToUpdate = [
             SELECT Id, Email__c, Stage__c, Name 
             FROM Lead__c 
             WHERE Course__c = 'MCOM' 
             AND Email__c IN :emailSet
        ];

        if (leadsToUpdate.isEmpty()) {
            result.messages.add('No matching M.Com leads found for the provided emails.');
            result.notFoundEmails.addAll(emailSet);
            return result;
        }

        Set<String> foundEmails = new Set<String>();
        List<Lead__c> recordsToSave = new List<Lead__c>();
        
        for (Lead__c l : leadsToUpdate) {
            l.Stage__c = 'B7'; // Enrolled
            recordsToSave.add(l);
            if (l.Email__c != null) foundEmails.add(l.Email__c.trim().toLowerCase());
        }
        
        // Determine which were not found
        for (String e : emailSet) {
            if (!foundEmails.contains(e)) {
                result.notFoundEmails.add(e);
            }
        }

        if (!recordsToSave.isEmpty()) {
            try {
                update recordsToSave;
                result.successCount = recordsToSave.size();
                result.messages.add('Successfully updated ' + result.successCount + ' records to B7 (Enrolled).');
            } catch (Exception e) {
                result.errorCount = recordsToSave.size(); // All failed in this batch
                result.messages.add('Error updating records: ' + e.getMessage());
                return result; // Exit
            }
        }
        
        if (!result.notFoundEmails.isEmpty()) {
            result.messages.add('Could not find M.Com records for ' + result.notFoundEmails.size() + ' emails.');
        }

        return result;
    }
}