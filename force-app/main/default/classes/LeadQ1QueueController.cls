public without sharing class LeadQ1QueueController {

    @AuraEnabled(cacheable=true)
    public static List<LeadQueueItemDTO> getQ1Leads() {
        User currentUser = [SELECT Id, City__c, UserRole.Name FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        String userCity = currentUser.City__c;

        String queueSearchName = userCity + ' High Priorty Queue';
        
        // 1. Verify if the current user is a member of this specific Queue
        List<GroupMember> membership = [
            SELECT Id 
            FROM GroupMember 
            WHERE Group.Type = 'Queue' 
            AND Group.Name = :queueSearchName 
            AND UserOrGroupId = :UserInfo.getUserId()
            LIMIT 1
        ];

        // 2. If user is not a member (and not a system admin), return empty list
        if (membership.isEmpty()) {
            return new List<LeadQueueItemDTO>();
        }

        // 3. Fetch leads if membership confirmed
        List<Lead__c> leads = [
            SELECT Id, Name, Phone__c, Email__c, Course__c, City__c, Stage__c, Source_Bucket__c, CreatedDate, 
                   Primary_tag__c, Next_Follow_Up_Date__c, Candidate__c, Is_ReEnquiry__c, Queue_Stage__c
            FROM Lead__c 
            WHERE Owner.Type = 'Queue' 
            AND Owner.Name = :queueSearchName
            AND Queue_Stage__c = 'Q1'
            AND Is_DND__c = FALSE 
            AND Is_Spam__c = FALSE 
            AND Is_Merged__c = FALSE 
            ORDER BY CreatedDate DESC 
            LIMIT 200
        ];

        List<LeadQueueItemDTO> allItems = new List<LeadQueueItemDTO>();
        for (Lead__c l : leads) {
            LeadQueueItemDTO dto = new LeadQueueItemDTO();
            dto.id          = l.Id;
            dto.name        = l.Name;
            dto.phone       = l.Phone__c;
            dto.course      = l.Course__c;
            dto.city        = l.City__c;
            dto.stage       = l.Stage__c;
            dto.source      = l.Source_Bucket__c;
            dto.createdDate = l.CreatedDate;
            dto.iscallLog   = false;
            
            // Reusing derivation logic if available or default to something sensible
            dto.primaryTag   = derivePrimaryTag(l.Next_Follow_Up_Date__c, null, l.Candidate__c, l.Is_ReEnquiry__c);

            dto.roleTag     = currentUser.UserRole != null ? currentUser.UserRole.Name : null;
            dto.bucketTag   = l.Source_Bucket__c;
            dto.nextFollowUpDate = l.Next_Follow_Up_Date__c;
            dto.candidateId = l.Candidate__c;
            allItems.add(dto);
        }

        return allItems;
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
    public static void updateLeadOwner(Id leadId) {
        if (leadId == null) return;
        Lead__c l = [SELECT Id, OwnerId FROM Lead__c WHERE Id = :leadId LIMIT 1];
        l.OwnerId = UserInfo.getUserId();
        update l;
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