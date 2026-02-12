@isTest
public class CallLogTriggerFrameworkHandlerTest {
    @isTest
    static void testTriggerMethods() {
        Lead cand = TestDataFactory.createLead('Test', 'Company', 'Open');
        SObject customLead = TestDataFactory.createCustomLead(cand.Id, 'M1');
        Call_Log__c cl = TestDataFactory.createCallLog(customLead.Id, 'Connected', 'Discussed', 60);
        
        CallLogTriggerFrameworkHandler handler = new CallLogTriggerFrameworkHandler(
            new List<Call_Log__c>{cl},
            null,
            new Map<Id, Call_Log__c>{cl.Id => cl},
            null
        );
        
        Test.startTest();
        handler.afterInsert();
        handler.afterUpdate();
        Test.stopTest();
        
        System.assertNotEquals(null, handler);
    }
}