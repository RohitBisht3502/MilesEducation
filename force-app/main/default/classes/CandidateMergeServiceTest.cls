@IsTest
private class CandidateMergeServiceTest {

    @IsTest
    static void mergeCandidates_reparentsRelatedRecordsAndUpdatesCandidates() {
        Lead sourceCandidate = new Lead(
            LastName = 'Source Candidate',
            Company = 'Test Company',
            Email = 'source@example.com'
        );
        Lead targetCandidate = new Lead(
            LastName = 'Target Candidate',
            Company = 'Test Company'
        );
        insert new List<Lead>{ sourceCandidate, targetCandidate };

        Lead__c programLead = new Lead__c(
            Name = 'CPA Lead',
            Candidate__c = sourceCandidate.Id,
            Stage__c = 'M3',
            Course__c = 'CPA',
            Disable_Round_Robin__c = false
        );
        Id programRecordTypeId = getLeadRecordTypeId();
        if (programRecordTypeId != null) {
            programLead.RecordTypeId = programRecordTypeId;
        }
        insert programLead;

        insert new Email__c(
            Candidate__c = sourceCandidate.Id,
            Email__c = 'source@example.com',
            Is_Primary__c = true
        );
        insert new Phone_Number__c(
            Candidate__c = sourceCandidate.Id,
            Phone__c = '9999999999',
            Is_Primary__c = true,
            By_Pass_Validation__c = true
        );
        insert new Call_Log__c(
            Candidate__c = sourceCandidate.Id,
            Phone_Number__c = '9999999999',
            Type__c = 'incoming'
        );
        insert new Enquiry__c(
            Name = 'Source Enquiry',
            First_Name__c = 'Source',
            Candidate__c = sourceCandidate.Id
        );

        Test.startTest();
        CandidateMergeService.mergeCandidates(sourceCandidate.Id, targetCandidate.Id, 'approved merge');
        Test.stopTest();

        Lead refreshedSource = [
            SELECT Candidate__c, Is_Merged__c
            FROM Lead
            WHERE Id = :sourceCandidate.Id
        ];
        Lead refreshedTarget = [
            SELECT Phone, Email, Merge_Comments__c
            FROM Lead
            WHERE Id = :targetCandidate.Id
        ];

        System.assertEquals(targetCandidate.Id, refreshedSource.Candidate__c);
        System.assertEquals(true, refreshedSource.Is_Merged__c);
        System.assertEquals('9999999999', refreshedTarget.Phone);
        System.assertEquals('source@example.com', refreshedTarget.Email);
        System.assertEquals('approved merge', refreshedTarget.Merge_Comments__c);

        System.assertEquals(1, [SELECT Count() FROM Lead__c WHERE Id = :programLead.Id AND Candidate__c = :targetCandidate.Id]);
        System.assertEquals(1, [SELECT Count() FROM Email__c WHERE Candidate__c = :targetCandidate.Id AND Email__c = 'source@example.com']);
        System.assertEquals(1, [SELECT Count() FROM Phone_Number__c WHERE Candidate__c = :targetCandidate.Id AND Phone__c = '9999999999']);
        System.assertEquals(1, [SELECT Count() FROM Call_Log__c WHERE Candidate__c = :targetCandidate.Id AND Phone_Number__c = '9999999999']);
        System.assertEquals(1, [SELECT Count() FROM Enquiry__c WHERE Candidate__c = :targetCandidate.Id AND Name = 'Source Enquiry']);
    }

    @IsTest
    static void mergeCandidates_rejectsSameCandidateIds() {
        Lead candidate = new Lead(
            LastName = 'Single Candidate',
            Company = 'Test Company'
        );
        insert candidate;

        try {
            CandidateMergeService.mergeCandidates(candidate.Id, candidate.Id, 'invalid');
            System.assert(false, 'Expected an AuraHandledException for same source and target.');
        } catch (AuraHandledException ex) {
            System.assert(ex.getMessage().contains('cannot be the same'));
        }
    }

    private static Id getLeadRecordTypeId() {
        Schema.DescribeSObjectResult describeResult = Lead__c.SObjectType.getDescribe();
        for (Schema.RecordTypeInfo recordTypeInfo : describeResult.getRecordTypeInfos()) {
            if (recordTypeInfo.isAvailable() && !recordTypeInfo.isMaster()) {
                return recordTypeInfo.getRecordTypeId();
            }
        }
        return null;
    }
}