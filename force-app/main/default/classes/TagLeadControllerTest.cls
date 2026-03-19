@IsTest
public class TagLeadControllerTest {

    @TestSetup
    static void setupData() {
        Id leadRecTypeId = getLeadRecordTypeId();
        String courseValue = getCourseValueForRecordType(leadRecTypeId);

        Lead standardLead = new Lead(
            LastName = 'Candidate Lead',
            Company = 'CandCo',
            Phone = '2222222222',
            Candidate_ID__c = 'CAND123'
        );
        insert standardLead;

        Lead__c customLead = new Lead__c(
            Name = 'Custom Lead',
            Phone__c = '1111111111',
            Email__c = 'test@abc.com',
            Candidate__c = standardLead.Id,
            Stage__c = 'M3',
            Disable_Round_Robin__c = false
        );
        if (courseValue != null) {
            customLead.Course__c = courseValue;
        }
        if (leadRecTypeId != null) {
            customLead.RecordTypeId = leadRecTypeId;
        }
        insert customLead;

        Call_Log__c callLog = new Call_Log__c(
            Phone_Number__c = '1111111111',
            Feedback__c = 'Initial Feedback',
            Untracked__c = true
        );
        insert callLog;
    }

    @IsTest
    static void testSearchLeadsByNameOrPhone() {
        List<Lead__c> results = TagLeadController.searchLeads('Custom');

        results = TagLeadController.searchLeads('1111111111');

        results = TagLeadController.searchLeads('CAND123');
    }

    @IsTest
    static void testTagOrCreateLead_ExistingLead() {
        Lead__c existingLead = [
            SELECT Id, Candidate__c, Name, Phone__c, Email__c
            FROM Lead__c
            WHERE Name = 'Custom Lead'
            LIMIT 1
        ];
        Call_Log__c callLog = [
            SELECT Id
            FROM Call_Log__c
            WHERE Phone_Number__c = '1111111111'
            LIMIT 1
        ];

        TagLeadController.tagOrCreateLead(
            callLog.Id,
            existingLead.Id,
            existingLead.Name,
            getCourseValueForRecordType(getLeadRecordTypeId()),
            existingLead.Email__c,
            existingLead.Phone__c,
            false,
            'L1',
            'L2',
            'Updated feedback',
            '2026-02-16T10:00',
            getLeadRecordTypeId()
        );

        callLog = [
            SELECT Lead__c, Candidate__c, Feedback__c, Untracked__c, Next_Follow_Up_Date__c
            FROM Call_Log__c
            WHERE Id = :callLog.Id
        ];
        existingLead = [SELECT Next_Follow_Up_Date__c FROM Lead__c WHERE Id = :existingLead.Id];

        Integer phoneCount = [
            SELECT Count()
            FROM Phone_Number__c
            WHERE Name = '1111111111'
            AND Candidate__c = :existingLead.Candidate__c
        ];
    }

    @IsTest
    static void testTagOrCreateLead_NewLead() {
        Call_Log__c callLog = new Call_Log__c(
            Phone_Number__c = '9999999999',
            Feedback__c = 'Fresh call',
            Untracked__c = true
        );
        insert callLog;

        Id leadRecTypeId = getLeadRecordTypeId();
        String courseValue = getCourseValueForRecordType(leadRecTypeId);

        TagLeadController.tagOrCreateLead(
            callLog.Id,
            null,
            'New Lead',
            courseValue,
            'newlead@test.com',
            '9999999999',
            true,
            'L1',
            'L2',
            'New feedback',
            '2026-02-16T15:00',
            leadRecTypeId
        );

        Lead__c newLead = [
            SELECT Id, Name, Course__c, Candidate__c, Next_Follow_Up_Date__c, Disable_Round_Robin__c
            FROM Lead__c
            WHERE Name = 'New Lead'
            LIMIT 1
        ];
        Lead standardLead = [SELECT Id FROM Lead WHERE Id = :newLead.Candidate__c LIMIT 1];

        callLog = [
            SELECT Lead__c, Feedback__c, Untracked__c, Next_Follow_Up_Date__c
            FROM Call_Log__c
            WHERE Id = :callLog.Id
        ];
    }

    @IsTest
    static void testMarkPhoneNumberAsSpam() {
        Call_Log__c callLog = [
            SELECT Id
            FROM Call_Log__c
            WHERE Phone_Number__c = '1111111111'
            LIMIT 1
        ];

        Test.startTest();
        TagLeadController.markPhoneNumberStatus(callLog.Id, true, false);
        Test.stopTest();

        Phone_Number__c phoneRecord = [
            SELECT Id, Phone__c, Is_Spam__c, Is_DND__c
            FROM Phone_Number__c
            WHERE Phone__c = '1111111111'
            LIMIT 1
        ];
    }

    @IsTest
    static void testMarkPhoneNumberAsDnd() {
        Call_Log__c callLog = new Call_Log__c(
            Phone_Number__c = '8888888888',
            Feedback__c = 'DND call',
            Untracked__c = true
        );
        insert callLog;

        Test.startTest();
        TagLeadController.markPhoneNumberStatus(callLog.Id, false, true);
        Test.stopTest();

        Phone_Number__c phoneRecord = [
            SELECT Id, Phone__c, Is_Spam__c, Is_DND__c
            FROM Phone_Number__c
            WHERE Phone__c = '8888888888'
            LIMIT 1
        ];
    }

    private static Id getLeadRecordTypeId() {
        Schema.DescribeSObjectResult dsr = Lead__c.SObjectType.getDescribe();
        for (Schema.RecordTypeInfo rti : dsr.getRecordTypeInfos()) {
            if (rti.isAvailable() && !rti.isMaster() && rti.isDefaultRecordTypeMapping()) {
                return rti.getRecordTypeId();
            }
        }
        for (Schema.RecordTypeInfo rti : dsr.getRecordTypeInfos()) {
            if (rti.isAvailable() && !rti.isMaster()) {
                return rti.getRecordTypeId();
            }
        }
        return null;
    }

    private static String getCourseValueForRecordType(Id recordTypeId) {
        if (recordTypeId == null) {
            return null;
        }
        return 'CPA';
    }
}
