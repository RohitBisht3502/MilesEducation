public without sharing class RunoMissedCallLogService {
    public class MissedCallLogDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public Id recordId;
        @AuraEnabled public String callId;
        @AuraEnabled public String candidateName;
        @AuraEnabled public String canId;
        @AuraEnabled public String relatedCourses;
        @AuraEnabled public Datetime startTime;
        @AuraEnabled public Datetime createdDate;
        @AuraEnabled public Integer durationSeconds;
        @AuraEnabled public String status;
        @AuraEnabled public String l1;
        @AuraEnabled public String l2;
        @AuraEnabled public String stage;
    }

    @AuraEnabled
    public static List<MissedCallLogDTO> getUntrackedMissedCallLogs() {
        Id currentUserId = UserInfo.getUserId();

        List<Call_Log__c> logs = [SELECT Id, Call_Id__c, Lead__c, Candidate__c, Student__c, Customer_Name__c, Start_Time__c, CreatedDate, Duration_Seconds__c, Status__c, L1__c, L2__c, Stage__c FROM Call_Log__c WHERE Untracked__c = true AND OwnerId = :currentUserId ORDER BY Start_Time__c DESC NULLS LAST, CreatedDate DESC LIMIT 50];

        if (logs.isEmpty()) {
            return new List<MissedCallLogDTO>();
        }

        Set<Id> leadIds = new Set<Id>();
        Set<Id> candidateIds = new Set<Id>();
        Set<Id> studentIds = new Set<Id>();

        for (Call_Log__c logRec : logs) {
            if (logRec.Lead__c != null) {
                leadIds.add(logRec.Lead__c);
            }
            if (logRec.Candidate__c != null) {
                candidateIds.add(logRec.Candidate__c);
            }
            if (logRec.Student__c != null) {
                studentIds.add(logRec.Student__c);
            }
        }

        Map<Id, Lead__c> leadMap = leadIds.isEmpty()
            ? new Map<Id, Lead__c>()
            : new Map<Id, Lead__c>([
                SELECT Id, Name, Candidate__c, Student__c, Course__c
                FROM Lead__c
                WHERE Id IN :leadIds
            ]);

        for (Lead__c leadRec : leadMap.values()) {
            if (leadRec.Candidate__c != null) {
                candidateIds.add(leadRec.Candidate__c);
            }
            if (leadRec.Student__c != null) {
                studentIds.add(leadRec.Student__c);
            }
        }

        Map<Id, Lead> candidateMap = candidateIds.isEmpty()
            ? new Map<Id, Lead>()
            : new Map<Id, Lead>([
                SELECT Id, Name, Candidate_ID__c
                FROM Lead
                WHERE Id IN :candidateIds
            ]);

        Map<Id, Account> studentMap = studentIds.isEmpty()
            ? new Map<Id, Account>()
            : new Map<Id, Account>([
                SELECT Id, Name
                FROM Account
                WHERE Id IN :studentIds
            ]);

        Map<String, Set<String>> courseMapByOwnerKey = new Map<String, Set<String>>();
        if (!candidateIds.isEmpty() || !studentIds.isEmpty()) {
            for (Lead__c relatedLead : [
                SELECT Id, Candidate__c, Student__c, Course__c
                FROM Lead__c
                WHERE Candidate__c IN :candidateIds OR Student__c IN :studentIds
            ]) {
                String ownerKey = buildOwnerKey(relatedLead.Candidate__c, relatedLead.Student__c);
                if (String.isBlank(ownerKey) || String.isBlank(relatedLead.Course__c)) {
                    continue;
                }

                if (!courseMapByOwnerKey.containsKey(ownerKey)) {
                    courseMapByOwnerKey.put(ownerKey, new Set<String>());
                }
                courseMapByOwnerKey.get(ownerKey).add(relatedLead.Course__c);
            }
        }

        List<MissedCallLogDTO> result = new List<MissedCallLogDTO>();

        for (Call_Log__c cl : logs) {
            Lead__c linkedLead = cl.Lead__c != null ? leadMap.get(cl.Lead__c) : null;
            Id effectiveCandidateId = cl.Candidate__c != null ? cl.Candidate__c : (linkedLead != null ? linkedLead.Candidate__c : null);
            Id effectiveStudentId = cl.Student__c != null ? cl.Student__c : (linkedLead != null ? linkedLead.Student__c : null);
            Id effectiveRecordId = effectiveCandidateId != null ? effectiveCandidateId : (effectiveStudentId != null ? effectiveStudentId : cl.Id);
            String ownerKey = buildOwnerKey(effectiveCandidateId, effectiveStudentId);
            List<String> relatedCourses = new List<String>();
            if (!String.isBlank(ownerKey) && courseMapByOwnerKey.containsKey(ownerKey)) {
                relatedCourses.addAll(courseMapByOwnerKey.get(ownerKey));
                relatedCourses.sort();
            }

            MissedCallLogDTO dto = new MissedCallLogDTO();
            dto.id = cl.Id;
            dto.recordId = effectiveRecordId;
            dto.callId = cl.Call_Id__c;
            dto.candidateName = resolveCandidateName(cl, linkedLead, effectiveCandidateId, effectiveStudentId, candidateMap, studentMap);
            dto.canId = resolveCanId(linkedLead, effectiveCandidateId, candidateMap);
            dto.relatedCourses = relatedCourses.isEmpty() ? 'No related courses' : String.join(relatedCourses, ', ');
            dto.startTime = cl.Start_Time__c;
            dto.createdDate = cl.CreatedDate;
            dto.durationSeconds = cl.Duration_Seconds__c != null
                ? Integer.valueOf(cl.Duration_Seconds__c)
                : 0;
            dto.status = cl.Status__c;
            dto.l1 = cl.L1__c;
            dto.l2 = cl.L2__c;
            dto.stage = cl.Stage__c;
            result.add(dto);
        }

        return result;
    }

    private static String resolveCandidateName(
        Call_Log__c logRec,
        Lead__c linkedLead,
        Id candidateId,
        Id studentId,
        Map<Id, Lead> candidateMap,
        Map<Id, Account> studentMap
    ) {
        if (candidateId != null && candidateMap.containsKey(candidateId)) {
            return candidateMap.get(candidateId).Name;
        }
        if (studentId != null && studentMap.containsKey(studentId)) {
            return studentMap.get(studentId).Name;
        }
        if (linkedLead != null && String.isNotBlank(linkedLead.Name)) {
            return linkedLead.Name;
        }
        if (String.isNotBlank(logRec.Customer_Name__c)) {
            return logRec.Customer_Name__c;
        }
        return 'Unknown Customer';
    }

    private static String resolveCanId(Lead__c linkedLead, Id candidateId, Map<Id, Lead> candidateMap) {
        if (candidateId != null && candidateMap.containsKey(candidateId)) {
            return candidateMap.get(candidateId).Candidate_ID__c;
        }
        return null;
    }

    private static String buildOwnerKey(Id candidateId, Id studentId) {
        if (candidateId != null) {
            return 'C:' + String.valueOf(candidateId);
        }
        if (studentId != null) {
            return 'S:' + String.valueOf(studentId);
        }
        return null;
    }
}