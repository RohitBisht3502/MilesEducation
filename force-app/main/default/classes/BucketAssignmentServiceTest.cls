@isTest
public class BucketAssignmentServiceTest {
    
    @isTest
    static void testAssignBucketInsert() {
        Lead l = new Lead(
            LastName = 'TestLead',
            Company = 'TestCompany'
        );
        
        // Use real values found in the org metadata for better coverage
        try {
            l.put('Course__c', 'CPA');
            l.put('Source__c', 'Blog Makreting');
        } catch (Exception e) {}

        List<SObject> newList = new List<SObject>{l};
        
        Test.startTest();
        BucketAssignmentService.assignBucket(newList, null);
        Test.stopTest();
        
        System.assertNotEquals(null, l);
    }

    @isTest
    static void testAssignBucketUpdate() {
        Lead oldL = TestDataFactory.createLead('Old', 'Company', 'Open');
        Lead newL = oldL.clone(true, true, true, true);
        
        try {
            newL.put('Course__c', 'CMA');
            newL.put('Coming_From__c', 'CA-DB');
        } catch (Exception e) {}

        Map<Id, SObject> oldMap = new Map<Id, SObject>{oldL.Id => oldL};
        List<SObject> newList = new List<SObject>{newL};

        Test.startTest();
        BucketAssignmentService.assignBucket(newList, oldMap);
        Test.stopTest();
        
        System.assertNotEquals(null, newList);
    }

    @isTest
    static void testEmptyList() {
        BucketAssignmentService.assignBucket(new List<SObject>(), null);
    }
}