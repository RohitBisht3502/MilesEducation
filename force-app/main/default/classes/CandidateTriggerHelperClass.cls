public without sharing class CandidateTriggerHelperClass {

    public static void handleBeforeInsert(List<Lead> newLeads) {
        BucketAssignmentService.assignBucket((List<SObject>) newLeads, null);
    }

    public static void handleBeforeUpdate(List<Lead> newLeads, Map<Id, Lead> oldMap) {
        BucketAssignmentService.assignBucket((List<SObject>) newLeads, (Map<Id, SObject>) oldMap);
    }

    public static void handleAfterInsert(List<Lead> newLeads) {
        if (newLeads == null || newLeads.isEmpty()) {
            return;
        }

        Set<Id> leadsForZoom = new Set<Id>();

        for (Lead ld : newLeads) {
            Boolean emailOk = String.isNotBlank(ld.Email);
            Boolean wantsWeb = ld.Register_For_Webinar__c == true;
            Boolean webinarAvailable = String.isNotBlank(ld.Interested_Webinar_Id__c);

            if (emailOk && wantsWeb && webinarAvailable) {
                leadsForZoom.add(ld.Id);
            }
        }

        if (!leadsForZoom.isEmpty()) {
            System.enqueueJob(new LeadZoomRegistrationJob(leadsForZoom));
        }
    }

    public static void handleCandidateIdAfterInsert(List<Lead> newLeads) {
        List<Lead> leadsToUpdate = new List<Lead>();
        Map<String, String> cityCodeMap = getCityCodeMap();

        System.debug('handleCandidateIdAfterInsert - newLeads: ' + newLeads);
        System.debug('handleCandidateIdAfterInsert - cityCodeMap: ' + cityCodeMap);

        Map<Id, Lead> leadMap = new Map<Id, Lead>([SELECT Id, City__c, Candidate_Id__c, Candidate_Running_Number__c, Is_Created_Manually__c FROM Lead WHERE Id IN :newLeads AND (City__c != NULL OR Is_Created_Manually__c = true)]);

        System.debug('handleCandidateIdAfterInsert - leadMap: ' + leadMap);

        for (Lead lead : leadMap.values()) {
            System.debug('Processing Lead Id: ' + lead.Id);
            System.debug('Lead City__c: ' + lead.City__c);
            System.debug('Lead Candidate_Id__c: ' + lead.Candidate_Id__c);
            System.debug('Lead Candidate_Running_Number__c: ' + lead.Candidate_Running_Number__c);

            if (String.isNotBlank(lead.City__c) && String.isBlank(lead.Candidate_Id__c)) {
                String cityName = lead.City__c.trim();
                String cityCode = cityCodeMap.get(cityName.toLowerCase());
                String runningNumber = extractRunningNumber(lead.Candidate_Running_Number__c);

                System.debug('Trimmed cityName: ' + cityName);
                System.debug('Resolved cityCode: ' + cityCode);
                System.debug('Extracted runningNumber: ' + runningNumber);

                Lead updatedLead = new Lead(Id = lead.Id);

                if (String.isNotBlank(cityCode)) {
                    updatedLead.Candidate_Id__c = cityCode + '-' + runningNumber;
                    leadsToUpdate.add(updatedLead);

                    System.debug('Generated Candidate_Id__c: ' + updatedLead.Candidate_Id__c);
                    System.debug('Added lead for update: ' + updatedLead);
                } else {
                    System.debug('No city code found for city: ' + cityName);
                }
            } else {
                System.debug('Lead skipped. Either City__c is blank or Candidate_Id__c already exists.');
            }
        }

        System.debug('Final leadsToUpdate size: ' + leadsToUpdate.size());
        System.debug('Final leadsToUpdate list: ' + leadsToUpdate);

        if (!leadsToUpdate.isEmpty()) {
            update leadsToUpdate;
            System.debug('Updated leads successfully.');
        } else {
            System.debug('No leads to update.');
        }
    }

    public static void handleCandidateIdBeforeUpdate(List<Lead> newLeads, Map<Id, Lead> oldLeadsMap) {
        List<Lead> leadsToProcess = new List<Lead>();

        for (Lead newLead : newLeads) {
            Lead oldLead = oldLeadsMap.get(newLead.Id);

            Boolean wasCityBlank = String.isBlank(oldLead.City__c);
            Boolean isCityNowNotBlank = String.isNotBlank(newLead.City__c);
            Boolean isCandidateIdBlank = String.isBlank(newLead.Candidate_Id__c);

            if (wasCityBlank && isCityNowNotBlank && isCandidateIdBlank) {
                leadsToProcess.add(newLead);
            }
        }

        if (!leadsToProcess.isEmpty()) {
            generateCandidateIds(leadsToProcess);
        }
    }

    private static void generateCandidateIds(List<Lead> leads) {
        Map<String, String> cityCodeMap = getCityCodeMap();

        for (Lead lead : leads) {
            if (String.isNotBlank(lead.City__c) && String.isBlank(lead.Candidate_Id__c)) {
                String cityName = lead.City__c.trim();
                String cityCode = cityCodeMap.get(cityName.toLowerCase());
                String runningNumber = extractRunningNumber(lead.Candidate_Running_Number__c);

                if (String.isNotBlank(cityCode)) {
                    lead.Candidate_Id__c = cityCode + '-' + runningNumber;
                }
            }
        }
    }

    private static String extractRunningNumber(String candidateRunningNumber) {
        if (String.isBlank(candidateRunningNumber)) {
            return '100000';
        }

        if (candidateRunningNumber.contains('CRN-')) {
            return candidateRunningNumber.substringAfter('CRN-');
        }

        return candidateRunningNumber;
    }

    public static void handleMilesUuidRecording(List<Lead> newLeads, Map<Id, Lead> oldMap) {
        if (newLeads == null || newLeads.isEmpty()) {
            return;
        }

        Set<String> uuidSet = new Set<String>();
        Map<String, Id> phoneToCandidateId = new Map<String, Id>();

        for (Lead newLead : newLeads) {
            Lead oldLead = oldMap.get(newLead.Id);

            if (newLead.UUID__c != null && (oldLead == null || newLead.UUID__c != oldLead.UUID__c)) {
                uuidSet.add(newLead.UUID__c);
                if (String.isNotBlank(newLead.Phone)) {
                    phoneToCandidateId.put(newLead.Phone, newLead.Id);
                }
            }
        }

        if (uuidSet.isEmpty()) {
            return;
        }

        for (String uuid : uuidSet) {
            Callout_MfSfUntrackToTrackRecording.sendByMilesUuid(uuid);
        }

        if (phoneToCandidateId.isEmpty()) {
            return;
        }

        List<Call_Log__c> logsToUpdate = new List<Call_Log__c>();
        for (Call_Log__c logRec : [
            SELECT Id, Phone_Number__c, Candidate__c
            FROM Call_Log__c
            WHERE Phone_Number__c IN :phoneToCandidateId.keySet()
        ]) {
            Id candidateId = phoneToCandidateId.get(logRec.Phone_Number__c);
            if (candidateId != null && logRec.Candidate__c != candidateId) {
                logRec.Candidate__c = candidateId;
                logRec.Untracked__c = false;
                logsToUpdate.add(logRec);
            }
        }

        if (!logsToUpdate.isEmpty()) {
            update logsToUpdate;
        }
    }

    private static Map<String, String> getCityCodeMap() {
        Map<String, String> cityCodeMap = new Map<String, String>();

        try {
            List<City_Master__mdt> cities = [SELECT MasterLabel, City_Name__c, City_Code__c FROM City_Master__mdt WHERE City_Name__c != NULL AND City_Code__c != NULL];

            for (City_Master__mdt city : cities) {
                String cityName = String.isNotBlank(city.City_Name__c) ? city.City_Name__c : city.MasterLabel;
                cityCodeMap.put(cityName.toLowerCase(), city.City_Code__c);
            }
        } catch (Exception e) {
            System.debug('Error fetching city metadata: ' + e.getMessage());
        }

        return cityCodeMap;
    }

    public static void transferRecordsOnConversion(List<Lead> newLeads, Map<Id, Lead> oldLeadsMap) {
        Map<Id, Id> convertedLeadToAccount = new Map<Id, Id>();

        for (Lead newLead : newLeads) {
            Lead oldLead = oldLeadsMap.get(newLead.Id);

            if (newLead.IsConverted && (oldLead == null || !oldLead.IsConverted) && newLead.ConvertedAccountId != null) {
                convertedLeadToAccount.put(newLead.Id, newLead.ConvertedAccountId);
            }
        }

        if (convertedLeadToAccount.isEmpty()) {
            return;
        }

        Set<Id> convertedLeadIds = convertedLeadToAccount.keySet();

        List<Email__c> emails = [SELECT Id, Candidate__c, Student__c FROM Email__c WHERE Candidate__c IN :convertedLeadIds];
        List<Lead__c> customLeads = [SELECT Id, Candidate__c, Student__c FROM Lead__c WHERE Candidate__c IN :convertedLeadIds];
        List<Phone_Number__c> phoneNumbers = [SELECT Id, Candidate__c, Student__c FROM Phone_Number__c WHERE Candidate__c IN :convertedLeadIds];

        List<SObject> recordsToUpdate = new List<SObject>();

        for (Email__c email : emails) {
            email.Student__c = convertedLeadToAccount.get(email.Candidate__c);
            recordsToUpdate.add(email);
        }

        for (Lead__c customLead : customLeads) {
            customLead.Student__c = convertedLeadToAccount.get(customLead.Candidate__c);
            recordsToUpdate.add(customLead);
        }

        for (Phone_Number__c phone : phoneNumbers) {
            phone.Student__c = convertedLeadToAccount.get(phone.Candidate__c);
            recordsToUpdate.add(phone);
        }

        if (!recordsToUpdate.isEmpty()) {
            update recordsToUpdate;
        }
    }

    public static void syncGpUserToRelatedLeads(List<Lead> newLeads, Map<Id, Lead> oldLeadsMap) {
        if (newLeads == null || newLeads.isEmpty() || oldLeadsMap == null) {
            return;
        }

        Map<Id, Id> candidateToGp = new Map<Id, Id>();

        for (Lead newLead : newLeads) {
            Lead oldLead = oldLeadsMap.get(newLead.Id);

            if (oldLead != null && newLead.GP_User__c != oldLead.GP_User__c && newLead.GP_User__c != null) {
                candidateToGp.put(newLead.Id, newLead.GP_User__c);
            }
        }

        if (candidateToGp.isEmpty()) {
            return;
        }

        List<Lead__c> leadsToUpdate = new List<Lead__c>();

        for (Lead__c relatedLead : [SELECT Id, Candidate__c, GP_SPOC__c FROM Lead__c WHERE Candidate__c IN :candidateToGp.keySet()]) {
            Id gpId = candidateToGp.get(relatedLead.Candidate__c);

            if (gpId != null && relatedLead.GP_SPOC__c != gpId) {
                relatedLead.GP_SPOC__c = gpId;
                leadsToUpdate.add(relatedLead);
            }
        }

        if (!leadsToUpdate.isEmpty()) {
            update leadsToUpdate;
        }
    }

    public static void createBridgeCourseLeads(List<Lead> leads, Map<Id, Lead> oldMap) {
        Set<Id> eligibleCandidateIds = new Set<Id>();
        List<Lead__c> leadsToCreate = new List<Lead__c>();

        for (Lead lead : leads) {
            Boolean isEligible = String.isNotBlank(lead.CPA_Eligibility_Status__c) && (lead.CPA_Eligibility_Status__c == 'Eligible for Exams' || lead.CPA_Eligibility_Status__c == 'Conditional Eligible' || lead.CPA_Eligibility_Status__c == 'Conditionally Eligible');

            if (isEligible) {
                eligibleCandidateIds.add(lead.Id);
            }
        }

        if (eligibleCandidateIds.isEmpty()) {
            return;
        }

        Set<Id> candidatesWithExistingMCom = new Set<Id>();
        for (Lead__c existingLead : [SELECT Candidate__c FROM Lead__c WHERE Candidate__c IN :eligibleCandidateIds AND Course__c = 'MCOM']) {
            candidatesWithExistingMCom.add(existingLead.Candidate__c);
        }

        Id mcomRecordTypeId = Schema.SObjectType.Lead__c.getRecordTypeInfosByDeveloperName().get('MCOM').getRecordTypeId();

        for (Lead lead : leads) {
            if (eligibleCandidateIds.contains(lead.Id) && !candidatesWithExistingMCom.contains(lead.Id)) {
                Lead__c newBridgeLead = new Lead__c();
                newBridgeLead.Name = lead.Name;
                newBridgeLead.Candidate__c = lead.Id;
                newBridgeLead.Email__c = lead.Email;
                newBridgeLead.Phone__c = lead.Phone;
                newBridgeLead.Course__c = 'MCOM';
                newBridgeLead.OwnerId = lead.OwnerId;

                if (mcomRecordTypeId != null) {
                    newBridgeLead.RecordTypeId = mcomRecordTypeId;
                }

                try {
                    newBridgeLead.put('Stage__c', 'B3');
                } catch (Exception e) {
                    System.debug('Stage__c update failed: ' + e.getMessage());
                }

                leadsToCreate.add(newBridgeLead);
                candidatesWithExistingMCom.add(lead.Id);
            }
        }

        if (!leadsToCreate.isEmpty()) {
            try {
                insert leadsToCreate;
            } catch (DmlException e) {
                System.debug('Error creating M.Com Leads: ' + e.getMessage());
            }
        }
    }
}