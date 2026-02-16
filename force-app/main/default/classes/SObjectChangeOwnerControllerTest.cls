@IsTest
public class SObjectChangeOwnerControllerTest {

     @TestSetup
    static void setupData() {
        // Create a user for owner change
        Profile p = [SELECT Id FROM Profile WHERE Name='Standard User' LIMIT 1];
        User u = new User(
            LastName='UserTest',
            Alias='utest',
            Email='user'+System.currentTimeMillis()+'@example.com',
            Username='user'+System.currentTimeMillis()+'@example.com',
            ProfileId=p.Id,
            TimeZoneSidKey='Asia/Kolkata',
            LocaleSidKey='en_US',
            EmailEncodingKey='UTF-8',
            LanguageLocaleKey='en_US',
            IsActive=true
        );
        insert u;

        // Create Accounts to test with
        List<Account> accs = new List<Account>();
        for(Integer i=0; i<3; i++) {
            accs.add(new Account(Name='Test Account '+i));
        }
        insert accs;
    }
    @IsTest
    static void testConstructorWithSelectedRecords() {
        List<Account> accounts = [SELECT Id FROM Account LIMIT 2];
        ApexPages.StandardSetController ssc = new ApexPages.StandardSetController(accounts);
        ssc.setSelected(accounts);

        SObjectChangeOwnerController ctrl = new SObjectChangeOwnerController(ssc);

        System.assertNotEquals(null, ctrl.recordIds);
        System.assertEquals(accounts.size(), ctrl.recordIds.size());
        System.assertEquals('Account', ctrl.objectApiName);
    }

    @IsTest
    static void testGetUsers() {
        List<Account> accounts = [SELECT Id FROM Account LIMIT 1];
        ApexPages.StandardSetController ssc = new ApexPages.StandardSetController(accounts);
        SObjectChangeOwnerController ctrl = new SObjectChangeOwnerController(ssc);

        List<SelectOption> options = ctrl.getUsers();
        System.assert(options.size() > 1, 'Should include all active users plus default option');
        System.assertEquals('-- Select User --', options[0].getLabel());
    }

 /*@IsTest
    static void testUpdateOwnerValidations() {
        // Fetch a valid user Id
        Id validUserId = [SELECT Id FROM User WHERE IsActive = true LIMIT 1].Id;
        Account acc = [SELECT Id FROM Account LIMIT 1];

        // No user selected
        ApexPages.StandardSetController ssc1 = new ApexPages.StandardSetController(new List<Account>{acc});
        ssc1.setSelected(new List<SObject>{acc});
        SObjectChangeOwnerController ctrl1 = new SObjectChangeOwnerController(ssc1);
        ctrl1.selectedUserId = null;
        ctrl1.changeReason = 'Some reason';

        PageReference pr1 = ctrl1.updateOwner();
        System.assertEquals(null, pr1);
        System.assertEquals(1, ApexPages.getMessages().size(), 'Should show error for no user');
        ApexPages.getMessages().clear();

        //️⃣ No reason provided
        ApexPages.StandardSetController ssc2 = new ApexPages.StandardSetController(new List<Account>{acc});
        ssc2.setSelected(new List<SObject>{acc});
        SObjectChangeOwnerController ctrl2 = new SObjectChangeOwnerController(ssc2);
        ctrl2.selectedUserId = validUserId;
        ctrl2.changeReason = '';  // blank reason

        PageReference pr2 = ctrl2.updateOwner();
        System.assertEquals(null, pr2);
        System.assertEquals(1, ApexPages.getMessages().size(), 'Should show error for blank reason');
        ApexPages.getMessages().clear();

        //️⃣ No records selected
        ApexPages.StandardSetController ssc3 = new ApexPages.StandardSetController(new List<Account>());
        SObjectChangeOwnerController ctrl3 = new SObjectChangeOwnerController(ssc3);
        ctrl3.selectedUserId = validUserId;
        ctrl3.changeReason = 'Reason';

        PageReference pr3 = ctrl3.updateOwner();
        System.assertEquals(null, pr3);
        System.assertEquals(1, ApexPages.getMessages().size(), 'Should show error for no records');
    }
*/
    @IsTest
    static void testUpdateOwnerSuccess() {
        List<Account> accounts = [SELECT Id, OwnerId FROM Account LIMIT 2];
        ApexPages.StandardSetController ssc = new ApexPages.StandardSetController(accounts);
        ssc.setSelected(accounts);

        SObjectChangeOwnerController ctrl = new SObjectChangeOwnerController(ssc);
        ctrl.selectedUserId = [SELECT Id FROM User WHERE IsActive = true LIMIT 1].Id;
        ctrl.changeReason = 'Testing ownership change';

        PageReference pr = ctrl.updateOwner();
        System.assertNotEquals(null, pr);
        System.assert(pr.getUrl().contains('Account'));

        // Verify owners updated
        List<Account> updated = [SELECT Id, OwnerId FROM Account WHERE Id IN :ctrl.recordIds];
        for (Account a : updated) {
            System.assertEquals(ctrl.selectedUserId, a.OwnerId);
        }

        // Verify activity logs created
        List<Activity_Log__c> logs = [SELECT Id, Activity_Type__c, Description__c FROM Activity_Log__c WHERE Activity_Type__c = 'Owner Change'];
        System.assertEquals(updated.size(), logs.size());
    }
}