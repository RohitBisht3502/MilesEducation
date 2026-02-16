@IsTest
public class RunoEventPublisherTest {

    @IsTest
    static void testPublishCallCompleted_AllParams() {
        // Create a Lead for testing
        Lead testLead = new Lead(FirstName='Test', LastName='Lead', Company='TestCo', Phone='1234567890');
        insert testLead;

        // Dummy candidate Id (can use Lead Id again for test purposes)
        Id candidateId = testLead.Id;

        Test.startTest();
        // Call the method with all parameters
        RunoEventPublisher.publishCallCompleted(
            'CALL123',
            120,
            testLead.Id,
            candidateId,
            '1234567890',
            'incoming',
            'completed'
        );
        Test.stopTest();

        // If needed, you can assert that events were published
        // Note: Salesforce doesn't allow direct query on platform events in tests
        // but you can check SaveResult if modified method returns it.
    }

    @IsTest
    static void testPublishCallCompleted_NullIds() {
        Test.startTest();
        // Call method with null leadId and candidateId
        RunoEventPublisher.publishCallCompleted(
            'CALL456',
            60,
            null,
            null,
            '9876543210',
            'missed',
            'failed'
        );
        Test.stopTest();
        // No exceptions should occur
    }

    @IsTest
    static void testPublishCallCompleted_MinimalParams() {
        Test.startTest();
        // Minimal valid call, just phone and call type
        RunoEventPublisher.publishCallCompleted(
            'CALL789',
            30,
            null,
            null,
            '5555555555',
            'incoming',
            'completed'
        );
        Test.stopTest();
    }
}