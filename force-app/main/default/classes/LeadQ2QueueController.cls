public without sharing class LeadQ2QueueController {

    @AuraEnabled(cacheable=true)
    public static List<LeadQueueItemDTO> getQ2Leads() {
        User currentUser = [SELECT Id, City__c, UserRole.Name FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        String userCity = currentUser.City__c;
        String queueSearchName = userCity + ' Public Queue';
        List<Lead> candidates = [SELECT Id, Name, Candidate_ID__c, Next_Follow_Up_Date__c, (SELECT Id, Name, Phone__c, Email__c, Course__c, City__c, Stage__c, Source_Bucket__c, CreatedDate, Primary_tag__c, Candidate__c, Is_ReEnquiry__c, Queue_Stage__c FROM Leads__r WHERE Owner.Type = 'Queue' AND Owner.Name = :queueSearchName AND Queue_Stage__c = 'Q2' AND Is_DND__c = FALSE AND Is_Spam__c = FALSE AND Is_Merged__c = FALSE ORDER BY CreatedDate DESC) FROM Lead WHERE Id IN (SELECT Candidate__c FROM Lead__c WHERE Candidate__c != null AND Owner.Type = 'Queue' AND Owner.Name = :queueSearchName AND Queue_Stage__c = 'Q2' AND Is_DND__c = FALSE AND Is_Spam__c = FALSE AND Is_Merged__c = FALSE) LIMIT 200];
        return QueuePriorityService.assignPriorities(buildQueueItems(candidates, currentUser));
    }

    private static List<LeadQueueItemDTO> buildQueueItems(List<Lead> candidates, User currentUser) {
        List<LeadQueueItemDTO> items = new List<LeadQueueItemDTO>();
        for (Lead candidate : candidates) {
            List<SObject> relatedLeadRecords = candidate.getSObjects('Leads__r');
            if (relatedLeadRecords == null || relatedLeadRecords.isEmpty()) {
                continue;
            }

            for (SObject relatedLeadRecord : relatedLeadRecords) {
                Lead__c relatedLead = (Lead__c) relatedLeadRecord;
                LeadQueueItemDTO dto = new LeadQueueItemDTO();
                dto.id = relatedLead.Id;
                dto.name = relatedLead.Name;
                dto.phone = relatedLead.Phone__c;
                dto.course = relatedLead.Course__c;
                dto.city = relatedLead.City__c;
                dto.stage = relatedLead.Stage__c;
                dto.source = relatedLead.Source_Bucket__c;
                dto.createdDate = relatedLead.CreatedDate;
                dto.iscallLog = false;
                dto.primaryTag = derivePrimaryTag(candidate.Next_Follow_Up_Date__c, null, candidate.Id, relatedLead.Is_ReEnquiry__c);
                dto.roleTag = currentUser.UserRole != null ? currentUser.UserRole.Name : null;
                dto.bucketTag = relatedLead.Source_Bucket__c;
                dto.nextFollowUpDate = candidate.Next_Follow_Up_Date__c;
                dto.candidateId = candidate.Id;
                dto.candidateCode = candidate.Candidate_ID__c;
                dto.candidateName = candidate.Name;
                items.add(dto);
            }
        }
        return items;
    }

    @AuraEnabled
    public static void startProcessingLead(Id leadId, String status) {
        if (leadId == null) return;
        Queue_Lead_Status__e evt = new Queue_Lead_Status__e();
        evt.Lead_Id__c = leadId;
        evt.Status__c = String.isBlank(status) ? 'Processing' : status;
        EventBus.publish(evt);
    }

    @AuraEnabled
    public static void updateLeadOwner(Id leadId, Id candidateId) {
        if (leadId == null && candidateId == null) return;

        List<SObject> recordsToUpdate = new List<SObject>();

        if (leadId != null) {
            recordsToUpdate.add(new Lead__c(
                Id = leadId,
                OwnerId = UserInfo.getUserId()
            ));
        }

        if (candidateId != null) {
            recordsToUpdate.add(new Lead(
                Id = candidateId,
                OwnerId = UserInfo.getUserId()
            ));
        }

        if (!recordsToUpdate.isEmpty()) {
            update recordsToUpdate;
        }
    }

    public static String derivePrimaryTag(Datetime nextFollowupDate, String callStatus, Id canId, Boolean isReEnquiry) {
        Datetime nowDt = Datetime.now();
        Date todayDate = nowDt.date();
        Datetime startOfToday = Datetime.newInstance(todayDate, Time.newInstance(0, 0, 0, 0));
        Datetime startOfTomorrow = startOfToday.addDays(1);

        if (!String.isBlank(callStatus) && callStatus.equalsIgnoreCase('missed')) {
            return 'Missed calls';
        }
                
        if (nextFollowupDate != null) {
            if (nextFollowupDate >= startOfToday && nextFollowupDate < startOfTomorrow) {
                return 'Todays';
            }
            if (nextFollowupDate < startOfToday) {
                return 'Delays';
            }
        }

        if (isReEnquiry == true) {
            return 'MHP';
        }

        return 'NE';
    }
}