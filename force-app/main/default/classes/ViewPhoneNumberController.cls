/*
    Author             : ROHIT SINGH BISHT
    Description        :
    Group              : Utilitarian Labs
*/

public without sharing class ViewPhoneNumberController {

    @AuraEnabled(cacheable=true)
    public static UserCreditInfo checkUserCredit() {

        try {

            User currentUser = [SELECT Id, Name, Credit__c FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];

            UserCreditInfo info = new UserCreditInfo();
            info.creditBalance = currentUser.Credit__c != null ? currentUser.Credit__c : 0;
            info.userId        = currentUser.Id;
            info.userName      = currentUser.Name;

            return info;

        } 
        catch (Exception e) {

            throw new AuraHandledException('Error checking user credit: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static PhoneResult getPhoneNumber(String recordId, String objectApiName) {

        try {

            User currentUser = [SELECT Id, Name, Email, Credit__c FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];

            Decimal currentCredit = currentUser.Credit__c != null ? currentUser.Credit__c : 0;

            if (currentCredit <= 0) {

                throw new AuraHandledException(
                    'You do not have enough credit to view phone numbers. Current balance: ' +
                    currentCredit.setScale(0)
                );
            }

            String phoneField = getPhoneFieldForObject(objectApiName);
            String emailField = getEmailFieldForObject(objectApiName);

            String query = 'SELECT Id, Name, ' + phoneField + ', ' + emailField +
                           ' FROM ' + String.escapeSingleQuotes(objectApiName) +
                           ' WHERE Id = :recordId LIMIT 1';

            List<SObject> records = Database.query(query);

            if (records.isEmpty()) {

                throw new AuraHandledException('Record not found');
            }

            SObject record = records[0];

            String phoneNumber = (String)record.get(phoneField);
            String emailValue  = (String)record.get(emailField);
            String recordName  = (String)record.get('Name');

            if (String.isBlank(phoneNumber)) {

                throw new AuraHandledException('No phone number available for this record');
            }

            currentUser.Credit__c = currentCredit - 1;
            Decimal creditAfter   = currentUser.Credit__c;

            update currentUser;

            createActivityLog(recordId, objectApiName, recordName, creditAfter, currentUser);

            PhoneResult result = new PhoneResult();
            result.phoneNumber      = phoneNumber;
            result.email            = emailValue;
            result.newCreditBalance = currentUser.Credit__c;

            return result;

        } 
        catch (Exception e) {

            throw new AuraHandledException('Error: ' + e.getMessage());
        }
    }

    private static String getEmailFieldForObject(String objectApiName) {

        switch on objectApiName {

            when 'Lead__c' {
                return 'Email__c';
            }

            when 'Account' {
                return 'PersonEmail';
            }

            when 'Enquiry__c' {
                return 'Email__c';
            }

            when 'Lead' {
                return 'Email';
            }

            when else {
                throw new AuraHandledException('Unsupported object type: ' + objectApiName);
            }
        }
    }

    private static String getPhoneFieldForObject(String objectApiName) {

        switch on objectApiName {

            when 'Lead__c' {
                return 'Phone__c';
            }

            when 'Account' {
                return 'Phone';
            }

            when 'Enquiry__c' {
                return 'Phone_Number__c';
            }

            when 'Lead' {
                return 'Phone';
            }

            when else {
                throw new AuraHandledException('Unsupported object type: ' + objectApiName);
            }
        }
    }

    private static void createActivityLog(
        String recordId,
        String objectApiName,
        String recordName,
        Decimal creditAfter,
        User currentUser
    ) {

        try {

            Activity_log__c log = new Activity_log__c();

            Datetime now = Datetime.now();
            String timestamp = now.format('dd/MM/yyyy hh:mm a');

            String activityName = 'View Phone - ' + (String.isNotBlank(recordName) ? recordName : objectApiName);

            if (activityName.length() > 75) {
                activityName = activityName.left(75);
            }

            activityName += ' - ' + timestamp;

            if (activityName.length() > 80) {
                activityName = activityName.left(80);
            }

            log.Name                       = activityName;
            log.Action_Performed_By__c     = currentUser.Id;
            log.Activity_Type__c           = 'View Phone Number';
            log.Available_Credit_Score__c  = creditAfter;

            String loggingId = 'ID: ' + currentUser.Id;
            log.Logging_Id__c = loggingId;

            switch on objectApiName {

                when 'Lead__c' {
                    log.Lead__c = recordId;
                }

                when 'Account' {
                    log.Student__c = recordId;
                }

                when 'Enquiry__c' {
                    log.Enquiry__c = recordId;
                }

                when 'Lead' {
                    log.Candidate__c = recordId;
                }

                when else {
                    throw new AuraHandledException(
                        'Unsupported object type for activity log: ' + objectApiName
                    );
                }
            }

            ActivityLogService.insertLogs(new List<Activity_Log__c>{ log });

        } 
        catch (Exception e) {

            System.debug('Error creating activity log: ' + e.getMessage());
            System.debug('Error line: ' + e.getLineNumber());
            System.debug('Error stack trace: ' + e.getStackTraceString());
        }
    }

    public class UserCreditInfo {

        @AuraEnabled
        public Decimal creditBalance { get; set; }

        @AuraEnabled
        public String userId { get; set; }

        @AuraEnabled
        public String userName { get; set; }
    }

    public class PhoneResult {

        @AuraEnabled
        public String phoneNumber { get; set; }

        @AuraEnabled
        public String email { get; set; }

        @AuraEnabled
        public Decimal newCreditBalance { get; set; }
    }
}