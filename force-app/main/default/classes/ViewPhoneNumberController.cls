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
    public static String getPhoneNumber(String recordId, String objectApiName) {
        try {
            User currentUser = [SELECT Id, Credit__c 
                               FROM User 
                               WHERE Id = :UserInfo.getUserId() 
                               LIMIT 1];
            
            Decimal currentCredit = currentUser.Credit__c != null ? currentUser.Credit__c : 0;
            
            if (currentCredit <= 0) {
                throw new AuraHandledException('You do not have enough credit to view phone numbers. Current balance: ' + currentCredit.setScale(0));
            }
            
            if (String.isBlank(objectApiName)) {
                throw new AuraHandledException('Object API name is required');
            }
            
            String query = 'SELECT Id, Phone__c FROM ' + 
                          String.escapeSingleQuotes(objectApiName) + 
                          ' WHERE Id = :recordId LIMIT 1';
            
            List<SObject> records = Database.query(query);
            
            if (records.isEmpty()) {
                throw new AuraHandledException('Record not found');
            }
            
            String phoneNumber = (String)records[0].get('Phone__c');
            
            if (String.isBlank(phoneNumber)) {
                throw new AuraHandledException('No phone number available for this record');
            }
            
            currentUser.Credit__c = currentCredit - 1;
            update currentUser;
            
            return phoneNumber;
        } catch (DmlException e) {
            throw new AuraHandledException('Unable to update credits: ' + e.getMessage());
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving phone number: ' + e.getMessage());
        }
    }
    
    public class UserCreditInfo {
        @AuraEnabled public Decimal creditBalance {get; set;}
        @AuraEnabled public String userId {get; set;}
        @AuraEnabled public String userName {get; set;}
    }
}