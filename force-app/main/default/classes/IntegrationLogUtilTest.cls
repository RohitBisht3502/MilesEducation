@IsTest
public class IntegrationLogUtilTest {

    private static String unique() {
        return String.valueOf(System.currentTimeMillis()) + Math.random();
    }

    @IsTest
    static void testBuildLog() {

        String u = unique();

        Integration_Log__c log = IntegrationLogUtil.buildLog(
            'API-' + u,
            'REQ-' + u,
            'RES-' + u,
            null,
            'SUCCESS',
            200
        );

        System.assertEquals('API-' + u, log.Integration_Type__c);
        System.assertEquals('REQ-' + u, log.Request_Payload__c);
        System.assertEquals('RES-' + u, log.Response_Payload__c);
    }

    @IsTest
    static void testInsertLog() {

        String u = unique();

        Test.startTest();
        IntegrationLogUtil.insertLog(
            'API-' + u,
            'REQ-' + u,
            'RES-' + u,
            null,
            'SUCCESS',
            201
        );
        Test.stopTest();

        System.assertEquals(
            1,
            [SELECT COUNT() FROM Integration_Log__c]
        );
    }

    @IsTest
    static void testInsertLogsBulk() {

        List<Integration_Log__c> logs = new List<Integration_Log__c>();

        for (Integer i = 0; i < 5; i++) {
            String u = unique();

            logs.add(
                IntegrationLogUtil.buildLog(
                    'API-' + u,
                    'REQ-' + u,
                    'RES-' + u,
                    null,
                    'SUCCESS',
                    200
                )
            );
        }

        Test.startTest();
        IntegrationLogUtil.insertLogs(logs);
        Test.stopTest();

        System.assertEquals(
            5,
            [SELECT COUNT() FROM Integration_Log__c]
        );
    }

    @IsTest
    static void testInsertLogsNullSafe() {

        Test.startTest();
        IntegrationLogUtil.insertLogs(null);
        IntegrationLogUtil.insertLogs(new List<Integration_Log__c>());
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Integration_Log__c]);
    }
}