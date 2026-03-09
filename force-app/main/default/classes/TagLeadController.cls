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
            
            createPhoneNumberRecordIfNotExists(callLog.Phone_Number__c, customLeadRecord.Candidate__c);
            
        } else {
            Lead standardLead = new Lead();
            standardLead.LastName = name;
            standardLead.Email = email;
            standardLead.Phone = phone;
            standardLead.Company = 'N/A';
            insert standardLead;
            
            customLeadRecord = new Lead__c();
            customLeadRecord.Name = name;
            
            // Determine Record Type based on Course Name
            Id finalRecordTypeId = null;
            if (String.isNotBlank(course)) {
                String trimmedCourse = course.trim();
                Schema.DescribeSObjectResult dsr = Lead__c.SObjectType.getDescribe();
                
                // Try to find Record Type that matches the Course Label
                Schema.RecordTypeInfo matchRti = dsr.getRecordTypeInfosByName().get(trimmedCourse);
                if (matchRti != null && matchRti.isAvailable() && !matchRti.isMaster()) {
                    finalRecordTypeId = matchRti.getRecordTypeId();
                }
            }

            // Fallback: If no course-specific record type, use passed ID or find default
            if (finalRecordTypeId == null) {
                finalRecordTypeId = recordTypeId;
                if (finalRecordTypeId == null || String.valueOf(finalRecordTypeId).endsWith('AAA')) {
                    Schema.DescribeSObjectResult dsr = Lead__c.SObjectType.getDescribe();
                    for (Schema.RecordTypeInfo rti : dsr.getRecordTypeInfos()) {
                        if (rti.isAvailable() && !rti.isMaster() && rti.isDefaultRecordTypeMapping()) {
                            finalRecordTypeId = rti.getRecordTypeId();
                            break;
                        }
                    }
                    if (finalRecordTypeId == null || String.valueOf(finalRecordTypeId).endsWith('AAA')) {
                        for (Schema.RecordTypeInfo rti : dsr.getRecordTypeInfos()) {
                            if (rti.isAvailable() && !rti.isMaster()) {
                                finalRecordTypeId = rti.getRecordTypeId();
                                break;
                            }
                        }
                    }
                }
            }
            customLeadRecord.RecordTypeId = finalRecordTypeId;
            
            customLeadRecord.Course__c = String.isNotBlank(course) ? course.trim() : null;
            customLeadRecord.Stage__c = 'M3';
            customLeadRecord.Email__c = email;
            customLeadRecord.Phone__c = phone;
            customLeadRecord.Candidate__c = standardLead.Id;
            customLeadRecord.Disable_Round_Robin__c = disableRR;
            
            if (String.isNotBlank(nextFollowUpDate)) {
                customLeadRecord.Next_Follow_Up_Date__c = parseUiDateTime(nextFollowUpDate);
            }
            
            try {
                insert customLeadRecord;
            } catch (DmlException e) {
                throw new AuraHandledException('Error creating Custom Lead: ' + e.getDmlMessage(0) + ' (Value passed: ' + course + ')');
            }
            
            callLog.Lead__c = customLeadRecord.Id;
            callLog.L1__c = l1;
            callLog.L2__c = l2;
            callLog.Feedback__c = feedback;
            callLog.Untracked__c = false;
            update callLog;

            if (String.isNotBlank(nextFollowUpDate)) {
                callLog.Next_Follow_Up_Date__c = parseUiDateTime(nextFollowUpDate);
                update callLog;
            }
            
            createPhoneNumberRecordIfNotExists(callLog.Phone_Number__c, customLeadRecord.Candidate__c);
        }
    }
    
    private static void createPhoneNumberRecordIfNotExists(String phoneNumber, Id standardLeadId) {
        if (String.isNotBlank(phoneNumber) && standardLeadId != null) {
            List<Phone_Number__c> existingPhones = [
                SELECT Id 
                FROM Phone_Number__c 
                WHERE Name = :phoneNumber 
                AND Candidate__c = :standardLeadId 
                LIMIT 1
            ];
            
            if (existingPhones.isEmpty()) {
                Phone_Number__c phoneRec = new Phone_Number__c();
                phoneRec.Name = phoneNumber;
                phoneRec.Candidate__c = standardLeadId;
                insert phoneRec;
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