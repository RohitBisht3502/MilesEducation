@IsTest
public class RoundRobinHelperTest {

    static User createUser() {
        Profile p = [SELECT Id FROM Profile WHERE Name='Standard User' LIMIT 1];
        User u = new User(
            Alias='usr',
            Email='user@test.com',
            EmailEncodingKey='UTF-8',
            LastName='Test',
            LanguageLocaleKey='en_US',
            LocaleSidKey='en_US',
            TimeZoneSidKey='Asia/Kolkata',
            ProfileId=p.Id,
            Username='user'+System.currentTimeMillis()+'@test.com'
        );
        insert u;
        return u;
    }

    static List<Round_Robin_Pool__c> createPool(Integer size) {

        List<Round_Robin_Pool__c> pool = new List<Round_Robin_Pool__c>();

        for (Integer i = 0; i < size; i++) {
            User u = createUser();

            pool.add(new Round_Robin_Pool__c(
                Object_Api_Name__c='Lead__c',
                City__c='DELHI',
                Type__c='CC - Pre Enrollment',
                Sales_Rep__c=u.Id,
                Sequence__c=i+1,
                Assigned_Weight__c=2,
                Current_Assigned_Weight__c=0,
                Total_Assigned__c=0,
                Active__c=true
            ));
        }

        insert pool;
        return pool;
    }

    @IsTest
    static void testKeyGeneration() {

        String key = RoundRobinHelper.keyOf(
            'Lead__c','DELHI','ONLINE','JAVA','CC - Pre Enrollment'
        );

        System.assert(key.contains('Lead__c'));
    }

    @IsTest
    static void testBucketFromKey() {

        String key = 'Lead__c|DELHI|ONLINE|JAVA|CC - Pre Enrollment';

        RoundRobinHelper.BucketRef b =
            RoundRobinHelper.bucketFromKey(key);

        System.assertEquals('Lead__c', b.objectApiName);
        System.assertEquals('DELHI', b.cityUpper);
    }

    @IsTest
    static void testPickNextBasic() {

        List<Round_Robin_Pool__c> pool = createPool(3);

        RoundRobinHelper.PickResult r =
            RoundRobinHelper.pickNext(pool, null);

        System.assertNotEquals(null, r.member);
    }

    @IsTest
    static void testConsumeSlot() {

        List<Round_Robin_Pool__c> pool = createPool(1);

        Round_Robin_Pool__c p = pool[0];

        RoundRobinHelper.consumeSlot(p);

        System.assertEquals(1, p.Current_Assigned_Weight__c);
        System.assertEquals(1, p.Total_Assigned__c);
    }

    @IsTest
    static void testResetCycle() {

        List<Round_Robin_Pool__c> pool = createPool(2);

        for (Round_Robin_Pool__c p : pool) {
            p.Current_Assigned_Weight__c = 5;
        }

        RoundRobinHelper.resetCycle(pool);

        for (Round_Robin_Pool__c p : pool) {
            System.assertEquals(0, p.Current_Assigned_Weight__c);
        }
    }

    @IsTest
    static void testFindEligible() {

        List<Round_Robin_Pool__c> pool = createPool(2);

        Round_Robin_Pool__c eligible =
            RoundRobinHelper.findEligible(pool, null, false);

        System.assertNotEquals(null, eligible);
    }
}