@IsTest
public class TagLeadControllerTest {

    // Static variables to hold test record IDs
    private static Id customLeadId;
    private static Id callLogId;

    @TestSetup
    static void setupData() {
        // Get default Lead__c record type
        Id leadRecTypeId = [SELECT Id 
                             FROM RecordType 
                             WHERE SObjectType='Lead__c' 
                             AND DeveloperName='Master' LIMIT 1].Id;

        // Create a standard Lead (Candidate)
        Lead standardLead = new Lead(
            LastName = 'Candidate Lead',
            Company = 'CandCo',
            Phone = '2222222222',
            Candidate_ID__c = 'CAND123'
        );
        insert standardLead;

        // Create a custom Lead__c linked to standard Lead
        Lead__c customLead = new Lead__c(
            Name = 'Custom Lead',
            Phone__c = '1111111111',
            Email__c = 'test@abc.com',
            Candidate__c = standardLead.Id,
            Course__c = 'CMA',           // valid picklist value
            Stage__c = 'M3',
            Disable_Round_Robin__c = false,
            RecordTypeId = leadRecTypeId
        );
        insert customLead;

        // Store Id for later use
        customLeadId = customLead.Id;

        // Create a Call Log record
        Call_Log__c callLog = new Call_Log__c(
            Phone_Number__c = '1111111111',
            Feedback__c = 'Initial Feedback',
            Untracked__c = true
        );
        insert callLog;

        callLogId = callLog.Id;

        // Create Phone Number record (for uniqueness testing)
        Phone_Number__c phoneNum = new Phone_Number__c(
            Name = '1111111111',
            Lead__c = customLead.Id
        );
        insert phoneNum;
    }

    @IsTest
    static void testSearchLeadsByNameOrPhone() {
        // Search by Name
        List<Lead__c> results = TagLeadController.searchLeads('Custom');
        System.assertEquals(1, results.size(), 'Should find the custom lead by name');

        // Search by Phone
        results = TagLeadController.searchLeads('1111111111');
        System.assertEquals(1, results.size(), 'Should find the custom lead by phone');

        // Search by Candidate_ID__c (standard Lead)
        results = TagLeadController.searchLeads('CAND123');
        System.assertEquals(1, results.size(), 'Should find the custom lead linked to standard lead');
    }

    @IsTest
    static void testTagOrCreateLead_ExistingLead() {
        Lead__c existingLead = [SELECT Id, Candidate__c, Name, Phone__c, Email__c FROM Lead__c WHERE Id = :customLeadId];
        Call_Log__c callLog = [SELECT Id FROM Call_Log__c WHERE Id = :callLogId];

        TagLeadController.tagOrCreateLead(
            callLog.Id,
            existingLead.Id,
            existingLead.Name,
            'CPA',       // valid picklist
            existingLead.Email__c,
            existingLead.Phone__c,
            false,
            null,        // L1 removed
            null,        // L2 removed
            'Updated feedback',
            '2026-02-16T10:00'
        );

        // Verify Call Log updated
        callLog = [SELECT Lead__c, Candidate__c, Feedback__c, Untracked__c, Next_Follow_Up_Date__c 
                   FROM Call_Log__c WHERE Id = :callLogId];
        System.assertEquals(existingLead.Id, callLog.Lead__c, 'Call Log Lead should be linked');
        System.assertEquals('Updated feedback', callLog.Feedback__c);

        // Verify Lead updated with next follow up date
        existingLead = [SELECT Next_Follow_Up_Date__c FROM Lead__c WHERE Id = :customLeadId];
        System.assertNotEquals(null, existingLead.Next_Follow_Up_Date__c);
    }

    @IsTest
    static void testTagOrCreateLead_NewLead() {
        Call_Log__c callLog = [SELECT Id, Phone_Number__c FROM Call_Log__c WHERE Id = :callLogId];

        TagLeadController.tagOrCreateLead(
            callLog.Id,
            null,
            'New Lead',
            'CPA',         // valid picklist
            'newlead@test.com',
            '9999999999',
            true,
            null,          // L1 removed
            null,          // L2 removed
            'New feedback',
            '2026-02-16T15:00'
        );

        // Verify new Lead__c created
        Lead__c newLead = [SELECT Id, Name, Course__c, Candidate__c, Next_Follow_Up_Date__c, Disable_Round_Robin__c
                            FROM Lead__c WHERE Name='New Lead' LIMIT 1];
        System.assertEquals('CPA', newLead.Course__c, 'Course should match picklist value');
        System.assertEquals(true, newLead.Disable_Round_Robin__c);

        // Verify standard Lead created
        Lead standardLead = [SELECT Id FROM Lead WHERE Id = :newLead.Candidate__c LIMIT 1];
        System.assertNotEquals(null, standardLead);

        // Verify Call Log updated
        callLog = [SELECT Lead__c, Feedback__c, Untracked__c, Next_Follow_Up_Date__c 
                   FROM Call_Log__c WHERE Id = :callLogId];
        System.assertEquals(newLead.Id, callLog.Lead__c);
        System.assertEquals('New feedback', callLog.Feedback__c);
    }
}