@isTest
public class BucketAssignmentServiceTest {
    
    @isTest
    static void testAssignBucketInsert() {
        insert new Bucket_Mapping__c(
            Bucket__c = 'Bucket 1',
            Value_Type__c = 'Course',
            Active__c = true,
            Sequence__c = 1,
            Course_Values__c = 'CPA;CMA'
        );
        insert new Bucket_Mapping__c(
            Bucket__c = 'Bucket 2',
            Value_Type__c = 'Source',
            Active__c = true,
            Sequence__c = 1,
            Source_Values__c = 'Blog Makreting;CA-DB'
        );

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
        System.assertEquals('Bucket 1', (String)l.get('Course_Bucket__c'));
        System.assertEquals('Bucket 2', (String)l.get('Source_Bucket__c'));
    }

    @isTest
    static void testAssignBucketUpdate() {
        insert new Bucket_Mapping__c(
            Bucket__c = 'Bucket 1',
            Value_Type__c = 'Course',
            Active__c = true,
            Sequence__c = 1,
            Course_Values__c = 'CMA'
        );
        insert new Bucket_Mapping__c(
            Bucket__c = 'Bucket 2',
            Value_Type__c = 'Source',
            Active__c = true,
            Sequence__c = 1,
            Source_Values__c = 'CA-DB'
        );

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
        System.assertEquals('Bucket 1', (String)newL.get('Course_Bucket__c'));
        System.assertEquals('Bucket 2', (String)newL.get('Source_Bucket__c'));
    }

    @isTest
    static void testEmptyList() {
        BucketAssignmentService.assignBucket(new List<SObject>(), null);
    }
}