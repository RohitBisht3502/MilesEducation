public without sharing class TagLeadController {

    @AuraEnabled(cacheable=true)
    public static List<Lead__c> searchLeads(String keyword) {
        List<Lead__c> results = new List<Lead__c>();
        
        results = [
            SELECT Id, Name, Email__c, Phone__c, Owner.Name, Course__c, Candidate__c, Candidate__r.Name, Candidate__r.Candidate_ID__c
            FROM Lead__c
            WHERE (Name LIKE :('%' + keyword + '%')
                OR Phone__c LIKE :('%' + keyword + '%')
                OR Candidate__r.Name LIKE :('%' + keyword + '%')
                OR Candidate__r.Candidate_ID__c LIKE :('%' + keyword + '%'))
            LIMIT 10
        ];
        
        if (results.isEmpty()) {
            List<Lead> standardLeads = [
                SELECT Id, Candidate_ID__c
                FROM Lead
                WHERE Candidate_ID__c LIKE :('%' + keyword + '%')
                LIMIT 10
            ];
            
            if (!standardLeads.isEmpty()) {
                Set<Id> standardLeadIds = new Set<Id>();
                for (Lead stdLead : standardLeads) {
                    standardLeadIds.add(stdLead.Id);
                }
                
                results = [
                    SELECT Id, Name, Email__c, Phone__c, Owner.Name, Course__c, Candidate__c, Candidate__r.Name, Candidate__r.Candidate_ID__c
                    FROM Lead__c
                    WHERE Candidate__c IN :standardLeadIds
                    LIMIT 10
                ];
            }
        }
        
        return results;
    }

    @AuraEnabled
    public static void tagOrCreateLead(
        Id callLogId, 
        Id leadId, 
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
            SELECT Id, Phone_Number__c
            FROM Call_Log__c
            WHERE Id = :callLogId
            LIMIT 1
        ];

        if (leadId != null) {
            customLeadRecord = [SELECT Id, Candidate__c FROM Lead__c WHERE Id = :leadId LIMIT 1];
            
            callLog.Lead__c = customLeadRecord.Id;
            callLog.Candidate__c = customLeadRecord.Candidate__c;
            callLog.L1__c = l1;
            callLog.L2__c = l2;
            callLog.Feedback__c = feedback;
            callLog.Untracked__c = false;
            update callLog;

            if (String.isNotBlank(nextFollowUpDate)) {
                callLog.Next_Follow_Up_Date__c = parseUiDateTime(nextFollowUpDate);
                update callLog;
            }
            
            if (String.isNotBlank(nextFollowUpDate)) {
                customLeadRecord.Next_Follow_Up_Date__c = parseUiDateTime(nextFollowUpDate);
                update customLeadRecord;
            }
            
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
            update callLog;

            if (String.isNotBlank(nextFollowUpDate)) {
                callLog.Next_Follow_Up_Date__c = parseUiDateTime(nextFollowUpDate);
                update callLog;
            }
            
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
