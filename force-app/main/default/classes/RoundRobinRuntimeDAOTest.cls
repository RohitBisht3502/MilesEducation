@IsTest
public class RoundRobinRuntimeDAOTest {

   
    @IsTest
    static void testCreateRuntime() {

        String keyVal = 'KEY_CREATE';

        Test.startTest();
        RoundRobinRuntimeDAO.Runtime rt =
            RoundRobinRuntimeDAO.getOrCreateLocked(keyVal);
        Test.stopTest();

        System.assertEquals(keyVal, rt.key);
        System.assertEquals(null, rt.lastAssignedUserId);
        System.assertNotEquals(null, rt.cycleStartedAt);
    }


   @IsTest
static void testFetchRuntimeWithNulls() {

    String keyVal = 'KEY_NULL';

    insert new Round_Robin_Runtime__c(
        Key__c = keyVal,
        Name = keyVal
    );

    Test.startTest();
    RoundRobinRuntimeDAO.Runtime rt =
        RoundRobinRuntimeDAO.getOrCreateLocked(keyVal);
    Test.stopTest();

    System.assertEquals(keyVal, rt.key);
    System.assertEquals(null, rt.lastAssignedUserId);
    System.assertEquals(null, rt.lastAssignedAt);
    System.assertEquals(null, rt.cycleStartedAt); 
}


    @IsTest
    static void testFetchRuntimeWithValues() {

        String keyVal = 'KEY_FULL';

        insert new Round_Robin_Runtime__c(
            Key__c = keyVal,
            Name = keyVal,
            Last_Assigned_User_Id__c = UserInfo.getUserId(),
            Last_Assigned_At__c = System.now(),
            Cycle_Started_At__c = System.now().addMinutes(-5)
        );

        Test.startTest();
        RoundRobinRuntimeDAO.Runtime rt =
            RoundRobinRuntimeDAO.getOrCreateLocked(keyVal);
        Test.stopTest();

        System.assertEquals(UserInfo.getUserId(), rt.lastAssignedUserId);
        System.assertNotEquals(null, rt.lastAssignedAt);
        System.assertNotEquals(null, rt.cycleStartedAt);
    }


    @IsTest
    static void testUpsertInsert() {

        String keyVal = 'KEY_INSERT';

        RoundRobinRuntimeDAO.Runtime rt = new RoundRobinRuntimeDAO.Runtime();
        rt.key = keyVal;
        rt.lastAssignedUserId = UserInfo.getUserId();
        rt.lastAssignedAt = System.now();
        rt.cycleStartedAt = System.now();

        Test.startTest();
        RoundRobinRuntimeDAO.upsertLocked(rt);
        Test.stopTest();

        System.assertEquals(1,
            [SELECT COUNT() FROM Round_Robin_Runtime__c WHERE Key__c = :keyVal]
        );
    }

   
    @IsTest
    static void testUpsertUpdate() {

        String keyVal = 'KEY_UPDATE';

        insert new Round_Robin_Runtime__c(
            Key__c = keyVal,
            Name = keyVal
        );

        RoundRobinRuntimeDAO.Runtime rt = new RoundRobinRuntimeDAO.Runtime();
        rt.key = keyVal;
        rt.lastAssignedUserId = UserInfo.getUserId();
        rt.lastAssignedAt = System.now();
        rt.cycleStartedAt = System.now();

        Test.startTest();
        RoundRobinRuntimeDAO.upsertLocked(rt);
        Test.stopTest();

        Round_Robin_Runtime__c r = [
            SELECT Last_Assigned_User_Id__c, Last_Assigned_At__c
            FROM Round_Robin_Runtime__c
            WHERE Key__c = :keyVal
        ];

        System.assertEquals(
            String.valueOf(UserInfo.getUserId()),
            r.Last_Assigned_User_Id__c
        );
        System.assertNotEquals(null, r.Last_Assigned_At__c);
    }

  
    @IsTest
    static void testUpsertWithNullUser() {

        String keyVal = 'KEY_NULL_USER';

        RoundRobinRuntimeDAO.Runtime rt = new RoundRobinRuntimeDAO.Runtime();
        rt.key = keyVal;
        rt.lastAssignedUserId = null;
        rt.lastAssignedAt = null;
        rt.cycleStartedAt = System.now();

        Test.startTest();
        RoundRobinRuntimeDAO.upsertLocked(rt);
        Test.stopTest();

        Round_Robin_Runtime__c r = [
            SELECT Last_Assigned_User_Id__c
            FROM Round_Robin_Runtime__c
            WHERE Key__c = :keyVal
        ];

        System.assertEquals(null, r.Last_Assigned_User_Id__c);
    }
}