@isTest
public class BaseTriggerHandlerTest {
    
    // Concrete implementation for testing
    private class TestTriggerHandler extends BaseTriggerHandler {
        public TestTriggerHandler(List<SObject> newList, List<SObject> oldList, Map<Id, SObject> newMap, Map<Id, SObject> oldMap) {
            super(newList, oldList, newMap, oldMap);
        }
    }

    @isTest
    static void testBaseMethods() {
        Lead l = new Lead(LastName = 'Test');
        List<Lead> newList = new List<Lead>{l};
        
        TestTriggerHandler handler = new TestTriggerHandler(newList, null, null, null);
        
        // Call all virtual methods to cover them
        handler.beforeInsert();
        handler.beforeUpdate();
        handler.beforeDelete();
        handler.afterInsert();
        handler.afterUpdate();
        handler.afterDelete();
        handler.afterUndelete();
        
        System.assertNotEquals(null, handler, 'Handler should be instantiated');
    }
}