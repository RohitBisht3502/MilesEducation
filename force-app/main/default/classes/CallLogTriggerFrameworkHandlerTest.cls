@IsTest
public class CallLogTriggerFrameworkHandlerTest {

    private static String pick(Schema.SObjectField f) {
        return f.getDescribe().getPicklistValues()[0].getValue();
    }

    private static Lead createLead() {
        Lead ld = new Lead(
            LastName = 'Test Lead ' + System.currentTimeMillis(),
            Company = 'Test Company',
            Status = 'Open - Not Contacted'
        );
        insert ld;
        return ld;
    }

    private static List<Call_Log__c> createCallLogs(Integer size) {

        Lead ld = createLead();

        List<Call_Log__c> logs = new List<Call_Log__c>();

        for (Integer i = 0; i < size; i++) {
            logs.add(new Call_Log__c(
                Lead__c = ld.Id,
                L1__c = pick(Call_Log__c.L1__c),
                L2__c = pick(Call_Log__c.L2__c),
                Type__c = pick(Call_Log__c.Type__c),
                Duration_Seconds__c = 60,
                Recording_Url__c = 'https://rec.com/' + System.currentTimeMillis() + i
            ));
        }

        insert logs;
        return logs;
    }

    @IsTest
    static void testInsertCreatesActivityLog() {

        createCallLogs(3);

        System.assertEquals(
            3,
            [SELECT COUNT() FROM Activity_Log__c]
        );
    }

    @IsTest
    static void testUpdateTracked() {

        List<Call_Log__c> logs = createCallLogs(2);

        for (Call_Log__c cl : logs) {
            cl.L1__c = pick(Call_Log__c.L1__c);
            cl.Duration_Seconds__c = 120;
        }

        Test.startTest();
        update logs;
        Test.stopTest();

        System.assertEquals(
            2,
            [SELECT COUNT() FROM Activity_Log__c WHERE Name = 'Updated Call Log']
        );
    }

    @IsTest
    static void testBulk() {

        List<Call_Log__c> logs = createCallLogs(40);

        for (Call_Log__c cl : logs) {
            cl.L2__c = pick(Call_Log__c.L2__c);
        }

        Test.startTest();
        update logs;
        Test.stopTest();

        System.assertEquals(
            40,
            [SELECT COUNT() FROM Activity_Log__c WHERE Name = 'Updated Call Log']
        );
    }
}