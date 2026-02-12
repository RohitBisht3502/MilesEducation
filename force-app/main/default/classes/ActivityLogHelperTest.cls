@isTest
public class ActivityLogHelperTest {
    @isTest
    static void testConstructor() {
        ActivityLogHelper helper = new ActivityLogHelper();
        System.assertNotEquals(null, helper, 'Instance should be created');
    }
}