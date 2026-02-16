@IsTest
public class RunoEnquiryTaskServiceTest {

    @TestSetup
    static void setupData() {
        // Create Standard User for owner lookup
        User u = new User(
            LastName = 'TestUser',
            Alias = 'tuser',
            Email='testuser@example.com',
            Username='testuser'+System.currentTimeMillis()+'@example.com',
            ProfileId = [SELECT Id FROM Profile WHERE Name='Standard User' LIMIT 1].Id,
            TimeZoneSidKey='Asia/Kolkata',
            LocaleSidKey='en_US',
            EmailEncodingKey='UTF-8',
            LanguageLocaleKey='en_US',
            Phone='9998887777'
        );
        insert u;

        // Lead__c with phone
        Lead__c l = new Lead__c(Name='Lead Test', Phone__c='1234567890');
        insert l;

        // Standard Lead
        Lead stdLead = new Lead(FirstName='Std', LastName='Lead', Phone='2345678901', Company='TestCo');
        insert stdLead;

        // Account with phone
        Account acc = new Account(Name='Test Account', Phone='3456789012');
        insert acc;
    }

    @IsTest
    static void testHandleNullCallLog() {
        Test.startTest();
        RunoEnquiryTaskService.handle(null);
        Test.stopTest();
        // Should not throw any exceptions
    }

    @IsTest
    static void testHandleBlankTypeOrPhone() {
        Call_Log__c log1 = new Call_Log__c(Customer_Name__c='Customer1', Phone_Number__c='', Type__c='incoming');
        Call_Log__c log2 = new Call_Log__c(Customer_Name__c='Customer2', Phone_Number__c='123', Type__c='');

        Test.startTest();
        RunoEnquiryTaskService.handle(log1);
        RunoEnquiryTaskService.handle(log2);
        Test.stopTest();
    }

    @IsTest
    static void testHandleInvalidCallType() {
        Call_Log__c log = new Call_Log__c(Customer_Name__c='Customer3', Phone_Number__c='1234567890', Type__c='outgoing');

        Test.startTest();
        RunoEnquiryTaskService.handle(log);
        Test.stopTest();
    }

    @IsTest
    static void testHandleIncomingCallWithFoundLeadAndOwner() {
        Call_Log__c log = new Call_Log__c(
            Customer_Name__c='Test Customer',
            Phone_Number__c='1234567890', // matches Lead__c
            Type__c='incoming',
            User_Phone__c='9998887777'    // matches User.Phone
        );
        insert log;

        Test.startTest();
        RunoEnquiryTaskService.handle(log);
        Test.stopTest();
    }

    @IsTest
    static void testHandleMissedCallWithNoFoundRecords() {
        Call_Log__c log = new Call_Log__c(
            Customer_Name__c='New Customer',
            Phone_Number__c='5555555555', // no match in Lead/Account
            Type__c='missed'
        );
        insert log;

        Test.startTest();
        RunoEnquiryTaskService.handle(log);
        Test.stopTest();
    }
}