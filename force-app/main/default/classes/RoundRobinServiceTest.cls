@IsTest
public class RoundRobinServiceTest {

    /* ================= TEST USER ================= */

    @testSetup
    static void setupUser() {
        insert new User(
            FirstName='Test',
            LastName='User',
            Alias='tusr',
            Email='tusr@test.com',
            Username='tusr'+System.currentTimeMillis()+'@test.com',
            TimeZoneSidKey='Asia/Kolkata',
            LocaleSidKey='en_US',
            EmailEncodingKey='UTF-8',
            LanguageLocaleKey='en_US',
            ProfileId=[SELECT Id FROM Profile LIMIT 1].Id
        );
    }

    static User getUser() {
        return [SELECT Id FROM User WHERE Alias='tusr' LIMIT 1];
    }

    /* ================= SAFE PICKLIST VALUE ================= */

    static String pick(Schema.SObjectType obj, String fieldApi) {
        Schema.DescribeFieldResult f =
            obj.getDescribe().fields.getMap().get(fieldApi).getDescribe();

        for (Schema.PicklistEntry p : f.getPicklistValues()) {
            if (p.isActive()) return p.getValue();
        }
        return null;
    }

    static String city()   { return pick(Lead.SObjectType,'City__c'); }
    static String source(){ return pick(Lead.SObjectType,'LeadSource'); }
    static String course(){ return pick(Lead.SObjectType,'Course_Bucket__c'); }

    /* ================= DATA FACTORIES ================= */

    static void createPool(String c,String s,String cr) {
        insert new Round_Robin_Pool__c(
            City__c=c,
            Lead_Source__c=s,
            Course_Bucket__c=cr,
            Sales_Rep__c=getUser().Id,
            Type__c='CC - Pre Enrollment',
            Object_Api_Name__c='Lead__c',
            Assigned_Weight__c=1,
            Sequence__c=1,
            Active__c=true
        );
    }

    static Lead createLead(String c,String s,String cr) {
        Lead l = new Lead(
            LastName='Test',
            Company='TestCo',
            City__c=c,
            LeadSource=s,
            Course_Bucket__c=cr
        );
        insert l;
        return l;
    }

    static RoundRobinConfigProvider.Config cfg() {
        RoundRobinConfigProvider.Config c = new RoundRobinConfigProvider.Config();
        c.objectApiName='Lead__c';
        c.cityField='City__c';
        c.sourceField='LeadSource';
        c.courseField='Course_Bucket__c';
        c.typeValue='CC - Pre Enrollment';
        c.assignToField='OwnerId';
        return c;
    }

    /* ================= GUARDS ================= */

    @IsTest static void guardNull() {
        RoundRobinService.assignForRecords(null,cfg());
    }

    @IsTest static void guardEmpty() {
        RoundRobinService.assignForRecords(new List<SObject>(),cfg());
    }

    @IsTest static void guardExecuting() {
        RoundRobinService.isExecuting=true;
        RoundRobinService.assignForRecords(new List<SObject>(),cfg());
        RoundRobinService.isExecuting=false;
    }

    /* ================= STANDARD ASSIGN ================= */

    @IsTest
    static void standardAssignment() {

        String c=city(), s=source(), cr=course();

        createPool(c,s,cr);

        Lead l1=createLead(c,s,cr);
        Lead l2=createLead(c,s,cr);

        Test.startTest();
        RoundRobinService.assignForRecords(
            new List<SObject>{l1,l2}, cfg()
        );
        Test.stopTest();

        for(Lead l : [SELECT OwnerId FROM Lead WHERE Id IN :new List<Id>{l1.Id,l2.Id}])
            System.assertNotEquals(null,l.OwnerId);

        System.assert([SELECT COUNT() FROM Round_Robin_Runtime__c] > 0);
    }

    /* ================= RUNTIME UPDATE ================= */

    @IsTest
    static void runtimeUpdate() {

        String c=city(), s=source(), cr=course();

        createPool(c,s,cr);
        Lead l=createLead(c,s,cr);

        insert new Round_Robin_Runtime__c(
            Key__c='Lead__c|'+c+'|'+s+'|'+cr+'|CC - Pre Enrollment',
            Name='runtime',
            Last_Assigned_User_Id__c=getUser().Id
        );

        Test.startTest();
        RoundRobinService.assignForRecords(
            new List<SObject>{l}, cfg()
        );
        Test.stopTest();

        System.assert([SELECT COUNT() FROM Round_Robin_Runtime__c] > 0);
    }

    /* ================= IGNORE FLAGS ================= */

    @IsTest
    static void ignoreFlags() {

        String c=city(), s=source(), cr=course();

        createPool(c,s,cr); // MUST store real picklist values

        Lead l=createLead(c,'SOMEOTHER','RANDOM');

        RoundRobinConfigProvider.Config cgf=cfg();
        cgf.ignoreSource=true;
        cgf.ignoreCourseBucket=true;

        Test.startTest();
        RoundRobinService.assignForRecords(
            new List<SObject>{l}, cgf
        );
        Test.stopTest();

        Lead r=[SELECT OwnerId FROM Lead WHERE Id=:l.Id];
        System.assertEquals(getUser().Id,r.OwnerId);
    }

    /* ================= NO POOL ================= */

    @IsTest
    static void noPool() {

        Lead l=createLead(city(),source(),course());

        Test.startTest();
        RoundRobinService.assignForRecords(
            new List<SObject>{l}, cfg()
        );
        Test.stopTest();

        System.assertNotEquals(
            null,
            [SELECT OwnerId FROM Lead WHERE Id=:l.Id].OwnerId
        );
    }
}