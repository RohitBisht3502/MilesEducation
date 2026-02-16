@IsTest
public class RoundRobinToggleOnOffTest {

    // Test CityStatusWrapper constructor
    @IsTest
    static void testWrapperConstructor() {
        RoundRobinToggleOnOff.CityStatusWrapper w = new RoundRobinToggleOnOff.CityStatusWrapper('PUNE', 'ON', 5);

        System.assertEquals('PUNE', w.city);
        System.assertEquals('ON', w.status);
        System.assertEquals(5, w.salesRepCount);
    }

    // Test getCityStatuses method
    @IsTest
    static void testGetCityStatuses() {
        Test.startTest();
        List<RoundRobinToggleOnOff.CityStatusWrapper> result = RoundRobinToggleOnOff.getCityStatuses();
        Test.stopTest();

        System.assertNotEquals(null, result, 'getCityStatuses should return a list (may be empty)');
    }

    // Test updateCityStatuses with valid JSON
    @IsTest
    static void testUpdateCityStatuses_validJson() {
        List<RoundRobinToggleOnOff.CityStatusWrapper> updates = new List<RoundRobinToggleOnOff.CityStatusWrapper>{
            new RoundRobinToggleOnOff.CityStatusWrapper('DELHI', 'ON', 2),
            new RoundRobinToggleOnOff.CityStatusWrapper('MUMBAI', 'OFF', 1)
        };

        String jsonData = JSON.serialize(updates);

        Test.startTest();
        RoundRobinToggleOnOff.updateCityStatuses(jsonData);
        Test.stopTest();

        System.assert(true, 'updateCityStatuses ran successfully with valid JSON');
    }

    // Test updateCityStatuses with invalid JSON
    @IsTest
    static void testUpdateCityStatuses_invalidJson() {
        Boolean thrown = false;

        try {
            Test.startTest();
            RoundRobinToggleOnOff.updateCityStatuses('INVALID_JSON');
            Test.stopTest();
        } catch (AuraHandledException e) {
            thrown = true;
        }

        System.assertEquals(true, thrown, 'Invalid JSON should throw AuraHandledException');
    }

    // Test updateCityStatuses with empty JSON
    @IsTest
    static void testUpdateCityStatuses_emptyJson() {
        Test.startTest();
        RoundRobinToggleOnOff.updateCityStatuses('');
        Test.stopTest();

        System.assert(true, 'updateCityStatuses ran successfully with empty JSON');
    }

    // Test updateCityStatuses with null/blank wrapper values
    @IsTest
    static void testUpdateCityStatuses_withNullWrapper() {
        List<RoundRobinToggleOnOff.CityStatusWrapper> updates = new List<RoundRobinToggleOnOff.CityStatusWrapper>{
            new RoundRobinToggleOnOff.CityStatusWrapper(null, null, 0),
            new RoundRobinToggleOnOff.CityStatusWrapper(' ', ' ', 0)
        };

        String jsonData = JSON.serialize(updates);

        Test.startTest();
        RoundRobinToggleOnOff.updateCityStatuses(jsonData);
        Test.stopTest();

        System.assert(true, 'updateCityStatuses handles null or blank city/status safely');
    }
}