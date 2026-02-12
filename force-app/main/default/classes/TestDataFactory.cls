@isTest
public class TestDataFactory {
    
    public static Lead createLead(String lastName, String company, String status) {
        Lead l = new Lead(
            LastName = lastName,
            Company = company,
            Status = status
        );
        insert l;
        return l;
    }

    public static Account createAccount(String name) {
        Account acc = new Account(Name = name);
        insert acc;
        return acc;
    }

    public static Contact createContact(Id accountId, String firstName, String lastName) {
        Contact con = new Contact(
            AccountId = accountId,
            FirstName = firstName,
            LastName = lastName
        );
        insert con;
        return con;
    }

    public static Call_Log__c createCallLog(Id leadId, String l1, String l2, Decimal duration) {
        Call_Log__c cl = new Call_Log__c(
            Lead__c = leadId,
            L1__c = l1,
            L2__c = l2,
            Duration_Seconds__c = duration,
            Type__c = 'incoming'
        );
        insert cl;
        return cl;
    }

    public static SObject createCustomLead(Id candidateId, String stage) {
        SObjectType targetType = Schema.getGlobalDescribe().get('Lead__c');
        if (targetType == null) return null;
        SObject l = targetType.newSObject();
        l.put('Candidate__c', candidateId);
        l.put('Stage__c', stage);
        insert l;
        return l;
    }

    // Add more methods as needed for specific objects
}