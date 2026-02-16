@IsTest
public class SobjectNavBarControllerTest {

    @TestSetup
    static void setupData() {
        // Create a custom Lead__c (only Name is required)
        Lead__c leadRec = new Lead__c(
            Name = 'Test Lead',      
            Phone__c = '1111111111'
        );
        insert leadRec;

        // Create an Account
        Account acc = new Account(Name='Test Account');
        insert acc;

        // Create a standard Lead (Candidate)
        Lead cand = new Lead(
            LastName = 'Candidate Lead',
            Company  = 'CandCo',
            Phone    = '2222222222'
        );
        insert cand;

        // Create Enquiry__c records for Lead__c
        List<Enquiry__c> enquiries = new List<Enquiry__c>{
            new Enquiry__c(Name='E1', Coming_From__c='Website', Lead__c=leadRec.Id),
            new Enquiry__c(Name='E2', Coming_From__c='Referral', Lead__c=leadRec.Id)
        };
        insert enquiries;

        // Create Enquiry__c for Account (Student__c)
        Enquiry__c eAcc = new Enquiry__c(
            Name='E3',
            Coming_From__c='Social Media',
            Student__c=acc.Id
        );
        insert eAcc;

        // Create Enquiry__c for Candidate (Lead)
        Enquiry__c eCand = new Enquiry__c(
            Name='E4',
            Coming_From__c='Event',
            Candidate__c=cand.Id
        );
        insert eCand;
    }

    @IsTest
    static void testGetNavData_NullId() {
        SobjectNavBarController.NavDataWrapper res = SobjectNavBarController.getNavData(null);

        System.assertNotEquals(null, res, 'Wrapper should not be null');
        System.assertEquals('Sources', res.latestSource, 'latestSource default');
        System.assertEquals(0, res.enquiry.size(), 'No enquiry records for null Id');
    }

    @IsTest
    static void testGetNavData_LeadObj() {
        Lead__c leadRec = [SELECT Id FROM Lead__c LIMIT 1];

        SobjectNavBarController.NavDataWrapper res = SobjectNavBarController.getNavData(leadRec.Id);

        System.assertNotEquals(null, res);
        System.assert(res.enquiry.size() > 0, 'Should have enquiry records for Lead__c');
        System.assertEquals('Referral', res.latestSource, 'latestSource should be most recent');
    }

    @IsTest
    static void testGetNavData_AccountObj() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        SobjectNavBarController.NavDataWrapper res = SobjectNavBarController.getNavData(acc.Id);

        System.assertNotEquals(null, res);
        System.assert(res.enquiry.size() > 0, 'Should have enquiry records for Account');
        System.assertEquals('Social Media', res.latestSource, 'latestSource for Account');
    }

    @IsTest
    static void testGetNavData_CandidateObj() {
        Lead cand = [SELECT Id FROM Lead WHERE Phone != null LIMIT 1];

        SobjectNavBarController.NavDataWrapper res = SobjectNavBarController.getNavData(cand.Id);

        System.assertNotEquals(null, res);
        System.assert(res.enquiry.size() > 0, 'Should have enquiry records for Candidate');
        System.assertEquals('Event', res.latestSource, 'latestSource for Candidate');
    }

    @IsTest
    static void testGetNavData_NoEnquiries() {
        Account a = new Account(Name='NoEnquiry');
        insert a;

        SobjectNavBarController.NavDataWrapper res = SobjectNavBarController.getNavData(a.Id);

        System.assertNotEquals(null, res);
        System.assertEquals(0, res.enquiry.size(), 'No Enquiry__c linked, enquiry list should be empty');
        System.assertEquals('Sources', res.latestSource);
    }
}