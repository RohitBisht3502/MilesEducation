public with sharing class ViewPhoneNumberController {
    
    @AuraEnabled(cacheable=true)
    public static UserCreditInfo checkUserCredit() {
        try {
            User currentUser = [SELECT Id, Name, Credit__c 
                               FROM User 
                               WHERE Id = :UserInfo.getUserId() 
                               LIMIT 1];
            
            UserCreditInfo info = new UserCreditInfo();
            info.creditBalance = currentUser.Credit__c != null ? currentUser.Credit__c : 0;
            info.userId = currentUser.Id;
            info.userName = currentUser.Name;
            
            return info;
        } catch (Exception e) {
            throw new AuraHandledException('Error checking user credit: ' + e.getMessage());
        }
    }
    
    @AuraEnabled
    public static PhoneResult getPhoneNumber(String recordId, String objectApiName) {
        try {
            // Get current user with credit
            User currentUser = [SELECT Id, Name, Email, Credit__c 
                               FROM User 
                               WHERE Id = :UserInfo.getUserId() 
                               LIMIT 1];
            
            Decimal currentCredit = currentUser.Credit__c != null ? currentUser.Credit__c : 0;
            
            // Check if user has enough credit
            if (currentCredit <= 0) {
                throw new AuraHandledException('You do not have enough credit to view phone numbers. Current balance: ' + currentCredit.setScale(0));
            }
            
            // Query the Lead record
            String query = 'SELECT Id, Name, Phone__c FROM ' + 
                          String.escapeSingleQuotes(objectApiName) + 
                          ' WHERE Id = :recordId LIMIT 1';
            
            List<SObject> records = Database.query(query);
            
            if (records.isEmpty()) {
                throw new AuraHandledException('Record not found');
            }
            
            String phoneNumber = (String)records[0].get('Phone__c');
            String leadName = (String)records[0].get('Name');
            
            if (String.isBlank(phoneNumber)) {
                throw new AuraHandledException('No phone number available for this record');
            }
            
            
            
            // Decrement credit by 1
            currentUser.Credit__c = currentCredit - 1;
            
            // Store credit before deduction
            Decimal creditAfter = currentUser.Credit__c;
            update currentUser;
            
            // Create activity log
            createActivityLog(recordId, leadName, creditAfter, currentUser);
            
            // Return result with phone number and new credit
            PhoneResult result = new PhoneResult();
            result.phoneNumber = phoneNumber;
            result.newCreditBalance = currentUser.Credit__c;
            
            return result;
            
        } catch (Exception e) {
            throw new AuraHandledException('Error: ' + e.getMessage());
        }
    }
    
    // Method to create Activity_log__c record
    private static void createActivityLog(String leadId, String leadName, Decimal creditAfter, User currentUser) {
        try {
            // Create Activity_log__c record
            Activity_log__c log = new Activity_log__c();
            
            // Set Name field
            Datetime now = Datetime.now();
            String timestamp = now.format('MM/dd/yyyy hh:mm a');
            String activityName = 'View Phone - ' + (String.isNotBlank(leadName) ? leadName : 'Lead');
            
            // Truncate if too long
            if (activityName.length() > 75) {
                activityName = activityName.left(75);
            }
            activityName += ' - ' + timestamp;
            
            if (activityName.length() > 80) {
                activityName = activityName.left(80);
            }
            
            log.Name = activityName;
            
            // Set all required fields
            log.Action_Performed_By__c = currentUser.Id;        // Lookup to User
            log.Activity_Type__c = 'View Phone Number';         // Picklist value
            log.Lead__c = leadId;                               // Lookup to Lead__c
            log.Available_Credit_Score__c = creditAfter;       // Number field
            
            // Set Logging_Id__c field (required) with user information
            String loggingId = 'User: ' + currentUser.Name + 
                             ' ID: ' + currentUser.Id;
            log.Logging_Id__c = loggingId;
            
            // Insert the record
            insert log;
            
        } catch (Exception e) {
            // Log error but don't throw - we don't want to fail the main operation
            System.debug('Error creating activity log: ' + e.getMessage());
            System.debug('Error line: ' + e.getLineNumber());
            System.debug('Error stack trace: ' + e.getStackTraceString());
        }
    }
    
    // Wrapper class for credit check
    public class UserCreditInfo {
        @AuraEnabled public Decimal creditBalance {get; set;}
        @AuraEnabled public String userId {get; set;}
        @AuraEnabled public String userName {get; set;}
    }
    
    // Wrapper class for phone result
    public class PhoneResult {
        @AuraEnabled public String phoneNumber {get; set;}
        @AuraEnabled public Decimal newCreditBalance {get; set;}
    }
}