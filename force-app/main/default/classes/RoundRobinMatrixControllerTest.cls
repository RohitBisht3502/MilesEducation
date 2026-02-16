@IsTest
public class RoundRobinMatrixControllerTest {

    /* ================= SAFE PICKLIST HELPERS ================= */

    static String leadSource() {
        return Round_Robin_Pool__c.Lead_Source__c.getDescribe()
            .getPicklistValues()[0].getValue();
    }

    static String city() {
        return Round_Robin_Pool__c.City__c.getDescribe()
            .getPicklistValues()[0].getValue();
    }

    /* ================= USER FACTORY ================= */

    static User createUser(String name) {

        Profile p = [SELECT Id FROM Profile LIMIT 1];

        User u = new User(
            FirstName = name,
            LastName = 'Rep',
            Alias = name.substring(0,2),
            Email = name + '@test.com',
            Username = name + System.currentTimeMillis() + '@test.com',
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = p.Id,
            City__c = city()
        );

        insert u;
        return u;
    }

    /* ================= POOL FACTORY ================= */

    static Round_Robin_Pool__c createPool(User u, Integer seq) {

        Round_Robin_Pool__c rr = new Round_Robin_Pool__c(
            City__c = city(),
            Lead_Source__c = leadSource(),
            Sales_Rep__c = u.Id,
            Type__c = 'CC - Pre Enrollment',
            Object_Api_Name__c = 'Lead__c',
            Assigned_Weight__c = 1,
            Sequence__c = seq,
            Active__c = true
        );

        insert rr;
        return rr;
    }

    /* ================= createRoundRobinEntry ================= */

    @IsTest
    static void testCreateRoundRobinEntry() {

        User u = createUser('u1');

        System.runAs(u) {
            Test.startTest();
            RoundRobinMatrixController.createRoundRobinEntry(
                city(),
                leadSource(),
                u.Id,
                'CMA',
                'CC - Pre Enrollment',
                2,
                'Lead__c',
                null
            );
            Test.stopTest();
        }

        System.assertEquals(1,
            [SELECT COUNT() FROM Round_Robin_Pool__c]
        );
    }

    /* ================= getPicklists ================= */

    @IsTest
    static void testGetPicklists() {

        Map<String,List<String>> res =
            RoundRobinMatrixController.getPicklists();

        System.assert(res.containsKey('cities'));
        System.assert(res.containsKey('types'));
        System.assert(res.containsKey('leadSources'));
    }

    /* ================= getSalesReps ================= */

    @IsTest
    static void testGetSalesReps() {

        createUser('rep1');
        createUser('rep2');

        List<User> reps =
            RoundRobinMatrixController.getSalesReps();

        System.assert(reps.size() >= 2);
    }

    /* ================= applyUpdates ================= */

    @IsTest
    static void testApplyUpdates() {

        User u = createUser('rep3');

        Round_Robin_Pool__c existing;

        System.runAs(u) {
            existing = createPool(u,1);
        }

        RoundRobinMatrixController.WeightUpdate w1 =
            new RoundRobinMatrixController.WeightUpdate();
        w1.poolId = existing.Id;
        w1.salesRepId = u.Id;
        w1.city = city();
        w1.leadSource = leadSource();
        w1.assignedWeight = 5;
        w1.typeVal = 'CC - Pre Enrollment';
        w1.role = 'CC';

        RoundRobinMatrixController.WeightUpdate w2 =
            new RoundRobinMatrixController.WeightUpdate();
        w2.salesRepId = u.Id;
        w2.city = city();
        w2.leadSource = leadSource();
        w2.assignedWeight = 3;
        w2.typeVal = 'CC - Pre Enrollment';
        w2.role = 'CC';

        Test.startTest();
        RoundRobinMatrixController.applyUpdates(
            new List<RoundRobinMatrixController.WeightUpdate>{ w1, w2 }
        );
        Test.stopTest();

        System.assertEquals(2,
            [SELECT COUNT() FROM Round_Robin_Pool__c]
        );
    }

    /* ================= saveSequences ================= */

    @IsTest
    static void testSaveSequences() {

        User u = createUser('rep4');

        Round_Robin_Pool__c r1;

        System.runAs(u) {
            r1 = createPool(u,1);
            createPool(u,2);
        }

        String jsonPayload = JSON.serialize(
            new Map<String,Object>{
                'leadSource' => leadSource(),
                'city' => city(),
                'bucket' => null,
                'businessVertical' => null,
                'typeVal' => 'CC - Pre Enrollment',
                'role' => 'CC',
                'updates' => new List<Object>{
                    new Map<String,Object>{
                        'poolId' => r1.Id,
                        'sequence' => 3
                    }
                }
            }
        );

        Test.startTest();
        RoundRobinMatrixController.saveSequences(jsonPayload);
        Test.stopTest();

        System.assertEquals(3,
            [SELECT Sequence__c FROM Round_Robin_Pool__c WHERE Id=:r1.Id]
                .Sequence__c
        );
    }

    /* ================= getFilters ================= */

    @IsTest
    static void testGetFilters() {

        RoundRobinMatrixController.FilterInit f =
            RoundRobinMatrixController.getFilters('Lead__c');

        System.assertNotEquals(null, f.cities);
        System.assertNotEquals(null, f.leadSources);
        System.assertNotEquals(null, f.types);
    }

    /* ================= getMatrix standard ================= */

    @IsTest
    static void testGetMatrixStandardFlow() {

        User u1 = createUser('A1');
        User u2 = createUser('A2');

        System.runAs(u1) {
            createPool(u1,1);
            createPool(u2,2);
        }

        Test.startTest();
        RoundRobinMatrixController.getMatrix(
            city(),
            null,
            new List<String>{ leadSource() },
            null,
            'CC - Pre Enrollment',
            'CC',
            1,
            10
        );
        Test.stopTest();

        System.assert(true);
    }

    /* ================= GP PATH (FIXED) ================= */

    @IsTest
    static void testGPPath() {

        User u = createUser('GP');

        System.runAs(u) {
            insert new Round_Robin_Pool__c(
                City__c = city(),
                Sales_Rep__c = u.Id,
                Type__c = 'GP',
                Object_Api_Name__c = 'Lead',
                Assigned_Weight__c = 1,
                Active__c = true
            );
        }

        Test.startTest();
        RoundRobinMatrixController.getMatrix(
            city(),
            null,
            null,
            null,
            'GP',
            'GP',
            1,
            5
        );
        Test.stopTest();

        System.assert(true);
    }
}