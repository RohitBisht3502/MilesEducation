@IsTest
private class PrimaryContactSyncServiceTest {

    @IsTest
    static void syncsPrimaryPhoneOnInsertAndUpdate() {
        Lead candidate = createCandidate('Phone Candidate', '1111111111', 'oldphone@test.com');
        Lead__c customLead = createRelatedLead(candidate.Id, 'Related Phone Lead', '2222222222', 'leadphone@test.com');

        Phone_Number__c firstPrimaryPhone = new Phone_Number__c(
            Candidate__c = candidate.Id,
            Lead__c = customLead.Id,
            Phone__c = '9999999999',
            Is_Primary__c = true,
            By_Pass_Validation__c = true
        );
        insert firstPrimaryPhone;

        candidate = [SELECT Id, Phone, Email FROM Lead WHERE Id = :candidate.Id];
        customLead = [SELECT Id, Phone__c, Email__c FROM Lead__c WHERE Id = :customLead.Id];

        System.assertEquals('9999999999', candidate.Phone);
        System.assertEquals('9999999999', customLead.Phone__c);

        Phone_Number__c secondaryPhone = new Phone_Number__c(
            Candidate__c = candidate.Id,
            Lead__c = customLead.Id,
            Phone__c = '8888888888',
            Is_Primary__c = false,
            By_Pass_Validation__c = true
        );
        insert secondaryPhone;

        secondaryPhone.Is_Primary__c = true;
        update secondaryPhone;

        candidate = [SELECT Id, Phone FROM Lead WHERE Id = :candidate.Id];
        customLead = [SELECT Id, Phone__c FROM Lead__c WHERE Id = :customLead.Id];
        firstPrimaryPhone = [SELECT Id, Is_Primary__c FROM Phone_Number__c WHERE Id = :firstPrimaryPhone.Id];
        secondaryPhone = [SELECT Id, Is_Primary__c FROM Phone_Number__c WHERE Id = :secondaryPhone.Id];

        System.assertEquals('8888888888', candidate.Phone);
        System.assertEquals('8888888888', customLead.Phone__c);
        System.assertEquals(false, firstPrimaryPhone.Is_Primary__c);
        System.assertEquals(true, secondaryPhone.Is_Primary__c);
    }

    @IsTest
    static void syncsPrimaryEmailOnInsertAndUpdate() {
        Lead candidate = createCandidate('Email Candidate', '3333333333', 'oldemail@test.com');
        Lead__c customLead = createRelatedLead(candidate.Id, 'Related Email Lead', '4444444444', 'leadold@test.com');

        Email__c firstPrimaryEmail = new Email__c(
            Candidate__c = candidate.Id,
            Lead__c = customLead.Id,
            Email__c = 'primary@test.com',
            Is_Primary__c = true
        );
        insert firstPrimaryEmail;

        candidate = [SELECT Id, Email FROM Lead WHERE Id = :candidate.Id];
        customLead = [SELECT Id, Email__c FROM Lead__c WHERE Id = :customLead.Id];

        System.assertEquals('primary@test.com', candidate.Email);
        System.assertEquals('primary@test.com', customLead.Email__c);

        Email__c secondaryEmail = new Email__c(
            Candidate__c = candidate.Id,
            Lead__c = customLead.Id,
            Email__c = 'latest@test.com',
            Is_Primary__c = false
        );
        insert secondaryEmail;

        secondaryEmail.Is_Primary__c = true;
        update secondaryEmail;

        candidate = [SELECT Id, Email FROM Lead WHERE Id = :candidate.Id];
        customLead = [SELECT Id, Email__c FROM Lead__c WHERE Id = :customLead.Id];
        firstPrimaryEmail = [SELECT Id, Is_Primary__c FROM Email__c WHERE Id = :firstPrimaryEmail.Id];
        secondaryEmail = [SELECT Id, Is_Primary__c FROM Email__c WHERE Id = :secondaryEmail.Id];

        System.assertEquals('latest@test.com', candidate.Email);
        System.assertEquals('latest@test.com', customLead.Email__c);
        System.assertEquals(false, firstPrimaryEmail.Is_Primary__c);
        System.assertEquals(true, secondaryEmail.Is_Primary__c);
    }

    private static Lead createCandidate(String lastName, String phone, String email) {
        Lead candidate = new Lead(
            LastName = lastName,
            Company = 'Miles Education',
            Phone = phone,
            Email = email
        );
        insert candidate;
        return candidate;
    }

    private static Lead__c createRelatedLead(Id candidateId, String name, String phone, String email) {
        Lead__c customLead = new Lead__c(
            Name = name,
            Candidate__c = candidateId,
            Phone__c = phone,
            Email__c = email,
            Stage__c = 'M3',
            Disable_Round_Robin__c = false
        );

        Id recordTypeId = getLeadRecordTypeId();
        if (recordTypeId != null) {
            customLead.RecordTypeId = recordTypeId;
            customLead.Course__c = 'CPA';
        }

        insert customLead;
        return customLead;
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
}