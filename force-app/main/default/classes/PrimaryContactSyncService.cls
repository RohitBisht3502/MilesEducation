public without sharing class PrimaryContactSyncService {

    private static Boolean isSyncInProgress = false;

    public static void syncPrimaryPhoneNumbers(List<Phone_Number__c> newRecords, Map<Id, Phone_Number__c> oldMap) {
        if (isSyncInProgress || newRecords == null || newRecords.isEmpty()) {
            return;
        }

        if (oldMap == null) {
            markPhoneNumbersAsCreated(newRecords);
        }

        Map<Id, String> candidateToPhone = new Map<Id, String>();
        Map<Id, Id> candidateToPrimaryPhoneRecordId = new Map<Id, Id>();
        collectPrimaryPhoneChanges(newRecords, oldMap, candidateToPhone, candidateToPrimaryPhoneRecordId);
        syncCandidateAndLeads(candidateToPhone, null);
        demoteOtherPrimaryPhones(candidateToPrimaryPhoneRecordId);
    }

    public static void syncPrimaryEmails(List<Email__c> newRecords, Map<Id, Email__c> oldMap) {
        if (isSyncInProgress || newRecords == null || newRecords.isEmpty()) {
            return;
        }

        if (oldMap == null) {
            markEmailsAsCreated(newRecords);
        }

        Map<Id, String> candidateToEmail = new Map<Id, String>();
        Map<Id, Id> candidateToPrimaryEmailRecordId = new Map<Id, Id>();
        collectPrimaryEmailChanges(newRecords, oldMap, candidateToEmail, candidateToPrimaryEmailRecordId);
        syncCandidateAndLeads(null, candidateToEmail);
        demoteOtherPrimaryEmails(candidateToPrimaryEmailRecordId);
    }

    private static void collectPrimaryPhoneChanges(
        List<Phone_Number__c> newRecords,
        Map<Id, Phone_Number__c> oldMap,
        Map<Id, String> candidateToPhone,
        Map<Id, Id> candidateToPrimaryPhoneRecordId
    ) {
        Set<Id> leadIds = new Set<Id>();
        List<Phone_Number__c> recordsToSync = new List<Phone_Number__c>();

        for (Phone_Number__c rec : newRecords) {
            if (!shouldSyncPhone(rec, oldMap)) {
                continue;
            }

            recordsToSync.add(rec);
            if (rec.Candidate__c == null && rec.Lead__c != null) {
                leadIds.add(rec.Lead__c);
            }
        }

        Map<Id, Lead__c> leadMap = leadIds.isEmpty()
            ? new Map<Id, Lead__c>()
            : new Map<Id, Lead__c>([
                SELECT Id, Candidate__c
                FROM Lead__c
                WHERE Id IN :leadIds
            ]);

        for (Phone_Number__c rec : recordsToSync) {
            Id candidateId = rec.Candidate__c;
            if (candidateId == null && rec.Lead__c != null && leadMap.containsKey(rec.Lead__c)) {
                candidateId = leadMap.get(rec.Lead__c).Candidate__c;
            }

            if (candidateId != null) {
                candidateToPhone.put(candidateId, rec.Phone__c);
                candidateToPrimaryPhoneRecordId.put(candidateId, rec.Id);
            }
        }
    }

    private static void collectPrimaryEmailChanges(
        List<Email__c> newRecords,
        Map<Id, Email__c> oldMap,
        Map<Id, String> candidateToEmail,
        Map<Id, Id> candidateToPrimaryEmailRecordId
    ) {
        Set<Id> leadIds = new Set<Id>();
        List<Email__c> recordsToSync = new List<Email__c>();

        for (Email__c rec : newRecords) {
            if (!shouldSyncEmail(rec, oldMap)) {
                continue;
            }

            recordsToSync.add(rec);
            if (rec.Candidate__c == null && rec.Lead__c != null) {
                leadIds.add(rec.Lead__c);
            }
        }

        Map<Id, Lead__c> leadMap = leadIds.isEmpty()
            ? new Map<Id, Lead__c>()
            : new Map<Id, Lead__c>([
                SELECT Id, Candidate__c
                FROM Lead__c
                WHERE Id IN :leadIds
            ]);

        for (Email__c rec : recordsToSync) {
            Id candidateId = rec.Candidate__c;
            if (candidateId == null && rec.Lead__c != null && leadMap.containsKey(rec.Lead__c)) {
                candidateId = leadMap.get(rec.Lead__c).Candidate__c;
            }

            if (candidateId != null) {
                candidateToEmail.put(candidateId, rec.Email__c);
                candidateToPrimaryEmailRecordId.put(candidateId, rec.Id);
            }
        }
    }

    private static void demoteOtherPrimaryPhones(Map<Id, Id> candidateToPrimaryPhoneRecordId) {
        if (candidateToPrimaryPhoneRecordId == null || candidateToPrimaryPhoneRecordId.isEmpty()) {
            return;
        }

        isSyncInProgress = true;
        try {
            List<Phone_Number__c> phonesToUpdate = new List<Phone_Number__c>();

            for (Phone_Number__c phoneRec : [
                SELECT Id, Candidate__c, Is_Primary__c
                FROM Phone_Number__c
                WHERE Candidate__c IN :candidateToPrimaryPhoneRecordId.keySet()
                AND Is_Primary__c = true
            ]) {
                if (candidateToPrimaryPhoneRecordId.get(phoneRec.Candidate__c) == phoneRec.Id) {
                    continue;
                }

                phonesToUpdate.add(new Phone_Number__c(
                    Id = phoneRec.Id,
                    Is_Primary__c = false
                ));
            }

            if (!phonesToUpdate.isEmpty()) {
                update phonesToUpdate;
            }
        } finally {
            isSyncInProgress = false;
        }
    }

    private static void demoteOtherPrimaryEmails(Map<Id, Id> candidateToPrimaryEmailRecordId) {
        if (candidateToPrimaryEmailRecordId == null || candidateToPrimaryEmailRecordId.isEmpty()) {
            return;
        }

        isSyncInProgress = true;
        try {
            List<Email__c> emailsToUpdate = new List<Email__c>();

            for (Email__c emailRec : [
                SELECT Id, Candidate__c, Is_Primary__c
                FROM Email__c
                WHERE Candidate__c IN :candidateToPrimaryEmailRecordId.keySet()
                AND Is_Primary__c = true
            ]) {
                if (candidateToPrimaryEmailRecordId.get(emailRec.Candidate__c) == emailRec.Id) {
                    continue;
                }

                emailsToUpdate.add(new Email__c(
                    Id = emailRec.Id,
                    Is_Primary__c = false
                ));
            }

            if (!emailsToUpdate.isEmpty()) {
                update emailsToUpdate;
            }
        } finally {
            isSyncInProgress = false;
        }
    }

    private static void markPhoneNumbersAsCreated(List<Phone_Number__c> newRecords) {
        List<Phone_Number__c> phonesToUpdate = new List<Phone_Number__c>();

        for (Phone_Number__c rec : newRecords) {
            if (rec == null || rec.Id == null || rec.Created_Date__C == 'true') {
                continue;
            }

            phonesToUpdate.add(new Phone_Number__c(
                Id = rec.Id,
                Created_Date__C = 'true'
            ));
        }

        if (phonesToUpdate.isEmpty()) {
            return;
        }

        isSyncInProgress = true;
        try {
            update phonesToUpdate;
        } finally {
            isSyncInProgress = false;
        }
    }

    private static void markEmailsAsCreated(List<Email__c> newRecords) {
        List<Email__c> emailsToUpdate = new List<Email__c>();

        for (Email__c rec : newRecords) {
            if (rec == null || rec.Id == null || rec.Created_Date__c == 'true') {
                continue;
            }

            emailsToUpdate.add(new Email__c(
                Id = rec.Id,
                Created_Date__c = 'true'
            ));
        }

        if (emailsToUpdate.isEmpty()) {
            return;
        }

        isSyncInProgress = true;
        try {
            update emailsToUpdate;
        } finally {
            isSyncInProgress = false;
        }
    }

    private static Boolean shouldSyncPhone(Phone_Number__c rec, Map<Id, Phone_Number__c> oldMap) {
        if (rec == null || rec.Is_Primary__c != true || String.isBlank(rec.Phone__c)) {
            return false;
        }

        if (oldMap == null || !oldMap.containsKey(rec.Id)) {
            return true;
        }

        Phone_Number__c oldRec = oldMap.get(rec.Id);
        return oldRec == null
            || oldRec.Is_Primary__c != true
            || oldRec.Phone__c != rec.Phone__c
            || oldRec.Candidate__c != rec.Candidate__c
            || oldRec.Lead__c != rec.Lead__c;
    }

    private static Boolean shouldSyncEmail(Email__c rec, Map<Id, Email__c> oldMap) {
        if (rec == null || rec.Is_Primary__c != true || String.isBlank(rec.Email__c)) {
            return false;
        }

        if (oldMap == null || !oldMap.containsKey(rec.Id)) {
            return true;
        }

        Email__c oldRec = oldMap.get(rec.Id);
        return oldRec == null
            || oldRec.Is_Primary__c != true
            || oldRec.Email__c != rec.Email__c
            || oldRec.Candidate__c != rec.Candidate__c
            || oldRec.Lead__c != rec.Lead__c;
    }

    private static void syncCandidateAndLeads(Map<Id, String> candidateToPhone, Map<Id, String> candidateToEmail) {
        Set<Id> candidateIds = new Set<Id>();
        if (candidateToPhone != null) {
            candidateIds.addAll(candidateToPhone.keySet());
        }
        if (candidateToEmail != null) {
            candidateIds.addAll(candidateToEmail.keySet());
        }

        if (candidateIds.isEmpty()) {
            return;
        }

        isSyncInProgress = true;
        try {
            List<SObject> recordsToUpdate = new List<SObject>();

            for (Lead candidate : [
                SELECT Id, Phone, Email
                FROM Lead
                WHERE Id IN :candidateIds
            ]) {
                Boolean changed = false;
                Lead updateCandidate = new Lead(Id = candidate.Id);

                if (candidateToPhone != null && candidateToPhone.containsKey(candidate.Id)) {
                    String phoneValue = candidateToPhone.get(candidate.Id);
                    if (candidate.Phone != phoneValue) {
                        updateCandidate.Phone = phoneValue;
                        changed = true;
                    }
                }

                if (candidateToEmail != null && candidateToEmail.containsKey(candidate.Id)) {
                    String emailValue = candidateToEmail.get(candidate.Id);
                    if (candidate.Email != emailValue) {
                        updateCandidate.Email = emailValue;
                        changed = true;
                    }
                }

                if (changed) {
                    recordsToUpdate.add(updateCandidate);
                }
            }

            for (Lead__c leadRec : [
                SELECT Id, Candidate__c, Phone__c, Email__c
                FROM Lead__c
                WHERE Candidate__c IN :candidateIds
            ]) {
                Boolean changed = false;
                Lead__c updateLead = new Lead__c(Id = leadRec.Id);

                if (candidateToPhone != null && candidateToPhone.containsKey(leadRec.Candidate__c)) {
                    String phoneValue = candidateToPhone.get(leadRec.Candidate__c);
                    if (leadRec.Phone__c != phoneValue) {
                        updateLead.Phone__c = phoneValue;
                        changed = true;
                    }
                }

                if (candidateToEmail != null && candidateToEmail.containsKey(leadRec.Candidate__c)) {
                    String emailValue = candidateToEmail.get(leadRec.Candidate__c);
                    if (leadRec.Email__c != emailValue) {
                        updateLead.Email__c = emailValue;
                        changed = true;
                    }
                }

                if (changed) {
                    recordsToUpdate.add(updateLead);
                }
            }

            if (!recordsToUpdate.isEmpty()) {
                update recordsToUpdate;
            }
        } finally {
            isSyncInProgress = false;
        }
    }
}