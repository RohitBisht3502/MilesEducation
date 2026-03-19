public without sharing class TagLeadController {

    public class CandidateCourseWrapper {
        @AuraEnabled public Id leadId;
        @AuraEnabled public String leadName;
        @AuraEnabled public String course;

        public CandidateCourseWrapper(Id leadId, String leadName, String course) {
            this.leadId = leadId;
            this.leadName = leadName;
            this.course = course;
        }
    }

    public class CandidateSearchWrapper {
        @AuraEnabled public Id candidateId;
        @AuraEnabled public String candidateName;
        @AuraEnabled public String ownerName;
        @AuraEnabled public String candidateCode;
        @AuraEnabled public String phone;
        @AuraEnabled public String courseSummary;
        @AuraEnabled public List<CandidateCourseWrapper> relatedLeads = new List<CandidateCourseWrapper>();
    }

    @AuraEnabled(cacheable=true)
    public static List<CandidateSearchWrapper> searchLeads(String keyword) {
        if (String.isBlank(keyword)) {
            return new List<CandidateSearchWrapper>();
        }

        String likeKeyword = '%' + keyword.trim() + '%';
        Set<Id> candidateIds = new Set<Id>();

        for (Lead__c customLead : [
            SELECT Candidate__c
            FROM Lead__c
            WHERE Candidate__c != null
              AND (Name LIKE :likeKeyword
                OR Phone__c LIKE :likeKeyword
                OR Candidate__r.Name LIKE :likeKeyword
                OR Candidate__r.Phone LIKE :likeKeyword
                OR Candidate__r.Candidate_ID__c LIKE :likeKeyword)
            LIMIT 50
        ]) {
            candidateIds.add(customLead.Candidate__c);
        }

        for (Lead candidate : [
            SELECT Id
            FROM Lead
            WHERE Name LIKE :likeKeyword
               OR Phone LIKE :likeKeyword
               OR Candidate_ID__c LIKE :likeKeyword
            LIMIT 50
        ]) {
            candidateIds.add(candidate.Id);
        }

        if (candidateIds.isEmpty()) {
            return new List<CandidateSearchWrapper>();
        }

        Map<Id, CandidateSearchWrapper> wrappersByCandidateId = new Map<Id, CandidateSearchWrapper>();
        List<Id> orderedCandidateIds = new List<Id>();
        for (Lead candidate : [
            SELECT Id, Name, Phone, Candidate_ID__c, Owner.Name
            FROM Lead
            WHERE Id IN :candidateIds
            ORDER BY Name
            LIMIT 10
        ]) {
            CandidateSearchWrapper wrapper = new CandidateSearchWrapper();
            wrapper.candidateId = candidate.Id;
            wrapper.candidateName = candidate.Name;
            wrapper.ownerName = candidate.Owner != null ? candidate.Owner.Name : 'N/A';
            wrapper.candidateCode = candidate.Candidate_ID__c;
            wrapper.phone = candidate.Phone;
            wrappersByCandidateId.put(candidate.Id, wrapper);
            orderedCandidateIds.add(candidate.Id);
        }

        for (Lead__c customLead : [
            SELECT Id, Name, Course__c, Candidate__c
            FROM Lead__c
            WHERE Candidate__c IN :wrappersByCandidateId.keySet()
            ORDER BY CreatedDate DESC
        ]) {
            CandidateSearchWrapper wrapper = wrappersByCandidateId.get(customLead.Candidate__c);
            if (wrapper == null) {
                continue;
            }
            wrapper.relatedLeads.add(new CandidateCourseWrapper(customLead.Id, customLead.Name, customLead.Course__c));
        }

        List<CandidateSearchWrapper> results = new List<CandidateSearchWrapper>();
        for (Id orderedCandidateId : orderedCandidateIds) {
            CandidateSearchWrapper wrapper = wrappersByCandidateId.get(orderedCandidateId);
            Set<String> uniqueCourses = new Set<String>();
            for (CandidateCourseWrapper relatedLead : wrapper.relatedLeads) {
                if (String.isNotBlank(relatedLead.course)) {
                    uniqueCourses.add(relatedLead.course);
                }
            }
            List<String> sortedCourses = new List<String>();
            sortedCourses.addAll(uniqueCourses);
            sortedCourses.sort();
            wrapper.courseSummary = sortedCourses.isEmpty() ? 'No related leads' : String.join(sortedCourses, ', ');
            results.add(wrapper);
        }
        if (results.size() <= 10) {
            return results;
        }

        List<CandidateSearchWrapper> limitedResults = new List<CandidateSearchWrapper>();
        for (Integer index = 0; index < 10; index++) {
            limitedResults.add(results[index]);
        }
        return limitedResults;
    }

    @AuraEnabled
    public static void tagOrCreateLead(
        Id callLogId,
        Id candidateId,
        String name,
        String course,
        String email,
        String phone,
        String city,
        String source,
        String firstName,
        String lastName,
        String countryCode,
        Boolean disableRR,
        String l1,
        String l2,
        String feedback,
        String nextFollowUpDate,
        Id recordTypeId
    ) {
        Lead__c customLeadRecord;

        Call_Log__c callLog = [
            SELECT Id, Phone_Number__c, Lead__c, Candidate__c
            FROM Call_Log__c
            WHERE Id = :callLogId
            LIMIT 1
        ];

        if (candidateId != null) {
            List<Lead> candidates = [SELECT Id FROM Lead WHERE Id = :candidateId LIMIT 1];
            if (candidates.isEmpty()) {
                throw new AuraHandledException('Candidate not found.');
            }

            callLog.Lead__c = null;
            callLog.Candidate__c = candidateId;
            callLog.L1__c = l1;
            callLog.L2__c = l2;
            callLog.Feedback__c = feedback;
            callLog.Untracked__c = false;
            if (String.isNotBlank(nextFollowUpDate)) {
                callLog.Next_Follow_Up_Date__c = parseUiDateTime(nextFollowUpDate);
            }
            update callLog;

            syncPhoneNumbersWithCandidate(callLog.Phone_Number__c, candidateId);
        } else {
            LeadNewOverrideController.Result createResult = LeadNewOverrideController.createLeadByCourse(
                course,
                city,
                firstName,
                lastName,
                countryCode,
                phone,
                email,
                source
            );

            if (createResult == null || createResult.success != true || createResult.leadId == null) {
                throw new AuraHandledException(
                    createResult != null && String.isNotBlank(createResult.message)
                        ? createResult.message
                        : 'Failed to create Lead.'
                );
            }

            customLeadRecord = [
                SELECT Id, Candidate__c, Next_Follow_Up_Date__c, Disable_Round_Robin__c
                FROM Lead__c
                WHERE Id = :createResult.leadId
                LIMIT 1
            ];

            Boolean leadChanged = false;
            if (customLeadRecord.Disable_Round_Robin__c != disableRR) {
                customLeadRecord.Disable_Round_Robin__c = disableRR;
                leadChanged = true;
            }
            if (String.isNotBlank(nextFollowUpDate)) {
                customLeadRecord.Next_Follow_Up_Date__c = parseUiDateTime(nextFollowUpDate);
                leadChanged = true;
            }
            if (leadChanged) {
                update customLeadRecord;
            }

            LeadNewOverrideController.sendLeadToMiles(customLeadRecord.Id);

            callLog.Lead__c = customLeadRecord.Id;
            callLog.Candidate__c = customLeadRecord.Candidate__c;
            callLog.L1__c = l1;
            callLog.L2__c = l2;
            callLog.Feedback__c = feedback;
            callLog.Untracked__c = false;
            if (String.isNotBlank(nextFollowUpDate)) {
                callLog.Next_Follow_Up_Date__c = parseUiDateTime(nextFollowUpDate);
            }
            update callLog;
        }
    }

    @AuraEnabled
    public static void markPhoneNumberStatus(Id callLogId, Boolean isSpam, Boolean isDnd) {
        if (callLogId == null) {
            throw new AuraHandledException('Call log is required.');
        }
        if (isSpam != true && isDnd != true) {
            throw new AuraHandledException('Please select spam or DND.');
        }

        Call_Log__c callLog = [
            SELECT Id, Phone_Number__c
            FROM Call_Log__c
            WHERE Id = :callLogId
            LIMIT 1
        ];

        if (String.isBlank(callLog.Phone_Number__c)) {
            throw new AuraHandledException('Phone number not found on call log.');
        }

        syncPhoneNumberStatus(callLog.Phone_Number__c, isSpam, isDnd);
    }

    private static void syncPhoneNumbersWithCandidate(String rawPhone, Id candidateId) {
        if (candidateId == null || String.isBlank(rawPhone)) {
            return;
        }

        Set<String> variants = Utility.buildPhoneVariants(rawPhone);
        String digits = rawPhone.replaceAll('[^0-9]', '');
        String last10 = String.isBlank(digits) ? null : (digits.length() > 10 ? digits.substring(digits.length() - 10) : digits);
        List<Phone_Number__c> phoneRecords;

        if (!String.isBlank(last10)) {
            String likePattern = '%' + last10;
            phoneRecords = [
                SELECT Id, Lead__c, Candidate__c, Phone__c, Is_Primary__c
                FROM Phone_Number__c
                WHERE Phone__c IN :variants OR Phone__c LIKE :likePattern
            ];
        } else if (!variants.isEmpty()) {
            phoneRecords = [
                SELECT Id, Lead__c, Candidate__c, Phone__c, Is_Primary__c
                FROM Phone_Number__c
                WHERE Phone__c IN :variants
            ];
        } else {
            phoneRecords = new List<Phone_Number__c>();
        }

        if (phoneRecords.isEmpty()) {
            insert new Phone_Number__c(
                Phone__c = !String.isBlank(last10) ? last10 : rawPhone,
                Candidate__c = candidateId,
                Is_Primary__c = true
            );
            return;
        }

        List<Phone_Number__c> updates = new List<Phone_Number__c>();
        for (Phone_Number__c phoneRecord : phoneRecords) {
            Boolean changed = false;
            if (phoneRecord.Candidate__c != candidateId) {
                phoneRecord.Candidate__c = candidateId;
                changed = true;
            }
            if (phoneRecord.Lead__c != null) {
                phoneRecord.Lead__c = null;
                changed = true;
            }
            if (phoneRecord.Is_Primary__c != true) {
                phoneRecord.Is_Primary__c = true;
                changed = true;
            }
            if (changed) {
                updates.add(phoneRecord);
            }
        }
        if (!updates.isEmpty()) {
            update updates;
        }
    }

    private static void syncPhoneNumberStatus(String rawPhone, Boolean isSpam, Boolean isDnd) {
        if (String.isBlank(rawPhone)) {
            return;
        }

        Set<String> variants = Utility.buildPhoneVariants(rawPhone);
        String digits = rawPhone.replaceAll('[^0-9]', '');
        String last10 = String.isBlank(digits) ? null : (digits.length() > 10 ? digits.substring(digits.length() - 10) : digits);
        List<Phone_Number__c> phoneRecords;

        if (!String.isBlank(last10)) {
            String likePattern = '%' + last10;
            phoneRecords = [
                SELECT Id, Phone__c, Is_Spam__c, Is_DND__c
                FROM Phone_Number__c
                WHERE Phone__c IN :variants OR Phone__c LIKE :likePattern
            ];
        } else if (!variants.isEmpty()) {
            phoneRecords = [
                SELECT Id, Phone__c, Is_Spam__c, Is_DND__c
                FROM Phone_Number__c
                WHERE Phone__c IN :variants
            ];
        } else {
            phoneRecords = new List<Phone_Number__c>();
        }

        if (phoneRecords.isEmpty()) {
            insert new Phone_Number__c(
                Phone__c = !String.isBlank(last10) ? last10 : rawPhone,
                Is_Spam__c = isSpam == true,
                Is_DND__c = isDnd == true
            );
            return;
        }

        List<Phone_Number__c> updates = new List<Phone_Number__c>();
        for (Phone_Number__c phoneRecord : phoneRecords) {
            Boolean changed = false;
            if (isSpam == true && phoneRecord.Is_Spam__c != true) {
                phoneRecord.Is_Spam__c = true;
                changed = true;
            }
            if (isDnd == true && phoneRecord.Is_DND__c != true) {
                phoneRecord.Is_DND__c = true;
                changed = true;
            }
            if (changed) {
                updates.add(phoneRecord);
            }
        }

        if (!updates.isEmpty()) {
            update updates;
        }
    }

    private static DateTime parseUiDateTime(String inputDt) {
        if (String.isBlank(inputDt)) return null;

        String dt = inputDt.replace('T', ' ');

        if (dt.length() == 16) {
            dt += ':00';
        }

        return DateTime.valueOf(dt);
    }
}
