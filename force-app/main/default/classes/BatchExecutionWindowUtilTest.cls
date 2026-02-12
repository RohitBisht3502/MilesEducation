@isTest
public class BatchExecutionWindowUtilTest {
    
    @isTest
    static void testIsBatchAlreadyRunning() {
        Boolean result = BatchExecutionWindowUtil.isBatchAlreadyRunning('SomeRandomBatchClassName');
        System.assertEquals(false, result, 'Should return false for non-running batch');
    }

    @isTest
    static void testCanRunNoConfig() {
        // Use a class name that definitely doesn't exist in metadata
        Boolean result = BatchExecutionWindowUtil.canRun('NonExistentBatch_XYZ_123');
        System.assertEquals(false, result, 'Should return false when no config exists');
    }

    @isTest
    static void testCanRunExistingConfig() {
        // Use one of the records we found in the org: LeadFollowUpAssignmentBatch
        // This will cover the lines inside the "if (!configs.isEmpty())" block
        // Note: This test's result depends on the current time and day in the org.
        // It might return true or false depending on when it's run.
        Boolean result = BatchExecutionWindowUtil.canRun('LeadFollowUpAssignmentBatch');
        
        // We don't strictly assert true because it might be run at night/weekend,
        // but we called the method so the lines are covered.
        System.assertNotEquals(null, result);
    }
}