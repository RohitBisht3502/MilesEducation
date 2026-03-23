@IsTest
private class LeadTriggerHelperClassTest {

    @IsTest
    static void syncLeadNameWithCandidate_onInsertAndCandidateChange() {
        Lead firstCandidate = new Lead(
            LastName = 'First Candidate',
            Company = 'Test Company'
        );
        Lead secondCandidate = new Lead(
            LastName = 'Second Candidate',
            Company = 'Test Company'
        );
        insert new List<Lead>{ firstCandidate, secondCandidate };

        Lead__c leadRecord = new Lead__c(
            Name = 'Temporary Name',
            Candidate__c = firstCandidate.Id
        );
        insert leadRecord;

        leadRecord = [
            SELECT Id, Name, Candidate__c
            FROM Lead__c
            WHERE Id = :leadRecord.Id
        ];
        System.assertEquals(firstCandidate.Name, leadRecord.Name);

        leadRecord.Candidate__c = secondCandidate.Id;
        update leadRecord;

        leadRecord = [
            SELECT Id, Name, Candidate__c
            FROM Lead__c
            WHERE Id = :leadRecord.Id
        ];
        System.assertEquals(secondCandidate.Id, leadRecord.Candidate__c);
        System.assertEquals(secondCandidate.Name, leadRecord.Name);
    }
}