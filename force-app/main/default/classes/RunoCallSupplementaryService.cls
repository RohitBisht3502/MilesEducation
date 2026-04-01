public without sharing class RunoCallSupplementaryService {

    // ─── DTOs ───
    public class CourseStageDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public String course;
        @AuraEnabled public String stage;
    }

    public class LastCallDTO {
        @AuraEnabled public Datetime startTime;
        @AuraEnabled public String calledBy;
        @AuraEnabled public String l1;
        @AuraEnabled public String l2;
        @AuraEnabled public Integer durationSeconds;
        @AuraEnabled public String status;
    }

    public class ConversationDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public Datetime callDate;
        @AuraEnabled public String calledBy;
        @AuraEnabled public String feedback;
        @AuraEnabled public String l1;
        @AuraEnabled public String l2;
        @AuraEnabled public String course;
        @AuraEnabled public String stage;
    }

    public class EnquiryDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public Datetime enquiryDate;
        @AuraEnabled public String source;
    }

    public class SupplementaryDTO {
        @AuraEnabled public List<CourseStageDTO> courseStages;
        @AuraEnabled public LastCallDTO lastCall;
        @AuraEnabled public List<ConversationDTO> conversations;
        @AuraEnabled public List<EnquiryDTO> enquiries;
    }

    // ─── Main Method ───
    @AuraEnabled(cacheable=true)
    public static SupplementaryDTO getSupplementaryData(Id candidateId, Id studentId) {
        SupplementaryDTO result = new SupplementaryDTO();
        result.courseStages = new List<CourseStageDTO>();
        result.lastCall = null;
        result.conversations = new List<ConversationDTO>();
        result.enquiries = new List<EnquiryDTO>();

        if (candidateId == null && studentId == null) {
            return result;
        }

        // Query 1 — Course stages
        List<Lead__c> leads;
        if (candidateId != null && studentId != null) {
            leads = [
                SELECT Id, Course__c, Stage__c
                FROM Lead__c
                WHERE Candidate__c = :candidateId OR Student__c = :studentId
                ORDER BY CreatedDate DESC
                LIMIT 20
            ];
        } else if (candidateId != null) {
            leads = [
                SELECT Id, Course__c, Stage__c
                FROM Lead__c
                WHERE Candidate__c = :candidateId
                ORDER BY CreatedDate DESC
                LIMIT 20
            ];
        } else {
            leads = [
                SELECT Id, Course__c, Stage__c
                FROM Lead__c
                WHERE Student__c = :studentId
                ORDER BY CreatedDate DESC
                LIMIT 20
            ];
        }

        for (Lead__c ld : leads) {
            CourseStageDTO cs = new CourseStageDTO();
            cs.id = ld.Id;
            cs.course = ld.Course__c;
            cs.stage = ld.Stage__c;
            result.courseStages.add(cs);
        }

        // Query 2 — Call data (last call + conversations)
        List<Call_Log__c> callLogs;
        if (candidateId != null && studentId != null) {
            callLogs = [
                SELECT Id, Start_Time__c, CreatedDate, Duration_Seconds__c,
                       Status__c, L1__c, L2__c, Called_By__c, Feedback__c, Course__c, Stage__c
                FROM Call_Log__c
                WHERE Candidate__c = :candidateId OR Student__c = :studentId
                ORDER BY Start_Time__c DESC NULLS LAST, CreatedDate DESC
                LIMIT 50
            ];
        } else if (candidateId != null) {
            callLogs = [
                SELECT Id, Start_Time__c, CreatedDate, Duration_Seconds__c,
                       Status__c, L1__c, L2__c, Called_By__c, Feedback__c, Course__c, Stage__c
                FROM Call_Log__c
                WHERE Candidate__c = :candidateId
                ORDER BY Start_Time__c DESC NULLS LAST, CreatedDate DESC
                LIMIT 50
            ];
        } else {
            callLogs = [
                SELECT Id, Start_Time__c, CreatedDate, Duration_Seconds__c,
                       Status__c, L1__c, L2__c, Called_By__c, Feedback__c, Course__c, Stage__c
                FROM Call_Log__c
                WHERE Student__c = :studentId
                ORDER BY Start_Time__c DESC NULLS LAST, CreatedDate DESC
                LIMIT 50
            ];
        }

        if (!callLogs.isEmpty()) {
            // First row → lastCall DTO
            Call_Log__c first = callLogs[0];
            LastCallDTO lc = new LastCallDTO();
            lc.startTime = first.Start_Time__c != null ? first.Start_Time__c : first.CreatedDate;
            lc.calledBy = String.isNotBlank(first.Called_By__c) ? first.Called_By__c : 'Unknown';
            lc.l1 = first.L1__c;
            lc.l2 = first.L2__c;
            lc.durationSeconds = first.Duration_Seconds__c != null ? Integer.valueOf(first.Duration_Seconds__c) : 0;
            lc.status = first.Status__c;
            result.lastCall = lc;

            // All rows with non-blank Feedback__c → conversations
            for (Call_Log__c cl : callLogs) {
                if (String.isNotBlank(cl.Feedback__c)) {
                    ConversationDTO conv = new ConversationDTO();
                    conv.id = cl.Id;
                    conv.callDate = cl.Start_Time__c != null ? cl.Start_Time__c : cl.CreatedDate;
                    conv.calledBy = String.isNotBlank(cl.Called_By__c) ? cl.Called_By__c : 'Unknown';
                    conv.feedback = cl.Feedback__c.length() > 200
                        ? cl.Feedback__c.substring(0, 200)
                        : cl.Feedback__c;
                    conv.l1 = cl.L1__c;
                    conv.l2 = cl.L2__c;
                    conv.course = cl.Course__c;
                    conv.stage = cl.Stage__c;
                    result.conversations.add(conv);
                }
            }
        }

        // Query 3 — Enquiries
        List<Enquiry__c> enquiries;
        if (candidateId != null && studentId != null) {
            enquiries = [
                SELECT Id, CreatedDate, Coming_From__c
                FROM Enquiry__c
                WHERE Candidate__c = :candidateId OR Student__c = :studentId
                ORDER BY CreatedDate DESC
                LIMIT 20
            ];
        } else if (candidateId != null) {
            enquiries = [
                SELECT Id, CreatedDate, Coming_From__c
                FROM Enquiry__c
                WHERE Candidate__c = :candidateId
                ORDER BY CreatedDate DESC
                LIMIT 20
            ];
        } else {
            enquiries = [
                SELECT Id, CreatedDate, Coming_From__c
                FROM Enquiry__c
                WHERE Student__c = :studentId
                ORDER BY CreatedDate DESC
                LIMIT 20
            ];
        }

        for (Enquiry__c enq : enquiries) {
            EnquiryDTO dto = new EnquiryDTO();
            dto.id = enq.Id;
            dto.enquiryDate = enq.CreatedDate;
            dto.source = String.isNotBlank(enq.Coming_From__c) ? enq.Coming_From__c : 'Unknown';
            result.enquiries.add(dto);
        }

        return result;
    }
}