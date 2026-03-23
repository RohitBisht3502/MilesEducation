@IsTest
private class CandidateTriggerHelperClassTest {

    @IsTest
    static void syncRelatedLeadNames_onCandidateNameChange() {
        Lead candidate = new Lead(
            LastName = 'Original Candidate',
            Company = 'Test Company'
        );
        insert candidate;

        Lead__c relatedLead = new Lead__c(
            Name = candidate.Name,
            Candidate__c = candidate.Id
        );
        insert relatedLead;

        candidate.LastName = 'Updated Candidate';
        update candidate;

        relatedLead = [
            SELECT Id, Name, Candidate__c
            FROM Lead__c
            WHERE Id = :relatedLead.Id
        ];
        System.assertEquals(candidate.Id, relatedLead.Candidate__c);
        System.assertEquals('Updated Candidate', relatedLead.Name);
    }
}