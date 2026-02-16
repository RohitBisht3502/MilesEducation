@IsTest
public class RoundRobinPoolHelpersTest {

    /* ========= Test Setup ========= */

    static Round_Robin_Pool__c createPool(Integer weight) {
        Round_Robin_Pool__c pool = new Round_Robin_Pool__c(
            City__c = 'Delhi',
            Lead_Source__c = 'Website',
            Type__c = 'CC - Pre Enrollment',
            Object_Api_Name__c = 'Lead__c',
            Assigned_Weight__c = weight,
            Active__c = true
        );
        insert pool;
        return pool;
    }

    /* ========= Weight Change Creates Log ========= */

    @IsTest
    static void testWeightChangeCreatesLog() {

        Round_Robin_Pool__c pool = createPool(1);

        Round_Robin_Pool__c oldPool =
            [SELECT Assigned_Weight__c FROM Round_Robin_Pool__c WHERE Id=:pool.Id];

        pool.Assigned_Weight__c = 5;

        Test.startTest();
        RoundRobinPoolHelpers.handleWeightChange(
            new List<Round_Robin_Pool__c>{ pool },
            new Map<Id,Round_Robin_Pool__c>{ pool.Id => oldPool }
        );
        Test.stopTest();

        List<Activity_Log__c> logs = [
            SELECT Previous_weight__c, New_Assinged_Weight__c, Activity_Type__c
            FROM Activity_Log__c
            WHERE Round_Robin_Pool__c = :pool.Id
        ];

        System.assertEquals(1, logs.size());
        System.assertEquals(1, logs[0].Previous_weight__c);
        System.assertEquals(5, logs[0].New_Assinged_Weight__c);
        System.assertEquals('WEIGHT UPDATED', logs[0].Activity_Type__c);
    }

    /* ========= No Change = No Log ========= */

    @IsTest
    static void testNoWeightChangeNoLog() {

        Round_Robin_Pool__c pool = createPool(3);

        Round_Robin_Pool__c oldPool =
            [SELECT Assigned_Weight__c FROM Round_Robin_Pool__c WHERE Id=:pool.Id];

        // Same weight (no change)
        pool.Assigned_Weight__c = 3;

        Test.startTest();
        RoundRobinPoolHelpers.handleWeightChange(
            new List<Round_Robin_Pool__c>{ pool },
            new Map<Id,Round_Robin_Pool__c>{ pool.Id => oldPool }
        );
        Test.stopTest();

        System.assertEquals(0,
            [SELECT COUNT() FROM Activity_Log__c]
        );
    }

    /* ========= Bulk Scenario ========= */

    @IsTest
    static void testBulkWeightChanges() {

        Round_Robin_Pool__c p1 = createPool(1);
        Round_Robin_Pool__c p2 = createPool(2);

        Map<Id,Round_Robin_Pool__c> oldMap = new Map<Id,Round_Robin_Pool__c>{
            p1.Id => p1.clone(false,true,false,false),
            p2.Id => p2.clone(false,true,false,false)
        };

        p1.Assigned_Weight__c = 4; // change
        p2.Assigned_Weight__c = 2; // no change

        Test.startTest();
        RoundRobinPoolHelpers.handleWeightChange(
            new List<Round_Robin_Pool__c>{ p1, p2 },
            oldMap
        );
        Test.stopTest();

        System.assertEquals(1,
            [SELECT COUNT() FROM Activity_Log__c]
        );
    }
}