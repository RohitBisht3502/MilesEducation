@IsTest(seeAllData=true)
public class RoundRobinConfigProviderTest {

    @IsTest
    static void testConfigFound() {

        RoundRobinConfigProvider.Config cfg =
            RoundRobinConfigProvider.getConfig('Lead__c', 'CC - Pre Enrollment');

        System.assertNotEquals(null, cfg);
        System.assertEquals('Lead__c', cfg.objectApiName);
        System.assertEquals('CC - Pre Enrollment', cfg.typeValue);
    }

    @IsTest
    static void testConfigMissing() {

        RoundRobinConfigProvider.Config cfg =
            RoundRobinConfigProvider.getConfig('Invalid__c', 'X');

        System.assertEquals(null, cfg);
    }

    @IsTest
    static void testDefaultTypeHandling() {

        RoundRobinConfigProvider.Config cfg =
            RoundRobinConfigProvider.getConfig('Lead__c', null);

        System.assertNotEquals(null, cfg);
    }
}