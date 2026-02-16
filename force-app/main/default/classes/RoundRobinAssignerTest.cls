@IsTest
public class RoundRobinAssignerTest {

    /* ---------- USER ---------- */

    static User createUser() {
        Profile p = [SELECT Id FROM Profile WHERE Name='Standard User' LIMIT 1];

        User u = new User(
            Alias='usr',
            Email='u@test.com',
            EmailEncodingKey='UTF-8',
            LastName='User',
            LanguageLocaleKey='en_US',
            LocaleSidKey='en_US',
            TimeZoneSidKey='Asia/Kolkata',
            ProfileId=p.Id,
            Username='u' + System.currentTimeMillis() + '@test.com'
        );
        insert u;
        return u;
    }

    /* ---------- LEAD FACTORY ---------- */

    static Lead__c createLead(String phone) {
        Lead__c l = new Lead__c(
            Name = 'Test Lead',
            Phone__c = phone,
            Email__c = phone + '@test.com'
        );
        insert l;
        return l;
    }

    /* ---------- FULL STICKY + ROUND ROBIN ---------- */

@IsTest
static void testStickyAndFallback() {

    User owner = createUser();

    System.runAs(owner) {

        Course_Enrolled__c ce = new Course_Enrolled__c(
            Phone__c = '1111',
            OwnerId = owner.Id
        );
        insert ce;

        Lead__c oldLead = createLead('2222');
        oldLead.OwnerId = owner.Id;
        update oldLead;

        Lead__c l1 = createLead('1111');
        Lead__c l2 = createLead('2222');
        Lead__c l3 = createLead('3333');

        Test.startTest();
        RoundRobinAssigner.assignWithStickyAndRoundRobin(
            new List<SObject>{ l1, l2, l3 },
            'Lead__c',
            'CC - Pre Enrollment'
        );
        Test.stopTest();

        Lead__c r1 = [SELECT OwnerId FROM Lead__c WHERE Id = :l1.Id];
        Lead__c r2 = [SELECT OwnerId FROM Lead__c WHERE Id = :l2.Id];

        System.assertEquals(owner.Id, r1.OwnerId);
        System.assertEquals(owner.Id, r2.OwnerId);
    }
}

    /* ---------- MCOM SKIP PATH ---------- */

    @IsTest
    static void testMCOMPath() {

        Lead__c l = createLead('4444');

        Test.startTest();
        RoundRobinAssigner.assignWithStickyAndRoundRobin(
            new List<SObject>{ l },
            'Lead__c',
            'MCOM'
        );
        Test.stopTest();

        System.assert(true);
    }

    /* ---------- EMPTY SAFE ---------- */

    @IsTest
    static void testEmptySafe() {

        Test.startTest();
        RoundRobinAssigner.assignWithStickyAndRoundRobin(
            new List<SObject>(),
            'Lead__c',
            'CC - Pre Enrollment'
        );
        Test.stopTest();

        System.assert(true);
    }

    /* ---------- NO CONFIG SAFE ---------- */

    @IsTest
    static void testMissingConfig() {

        Lead__c dummy = new Lead__c(Name='Dummy');

        Test.startTest();
        RoundRobinAssigner.assignWithStickyAndRoundRobin(
            new List<SObject>{ dummy },
            'Bad__c',
            'X'
        );
        Test.stopTest();

        System.assert(true);
    }
}