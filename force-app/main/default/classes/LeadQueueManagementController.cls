/*
    Author       : ROHIT SINGH BISHT
    Description  : 
*/
public class LeadQueueManagementController {

    @AuraEnabled(cacheable=true)
    public static List<LeadQueueItemDTO> getUserLeads() {
        List<Lead__c> leads = [SELECT Id, Name, Phone__c, Email__c, Course__c, City__c, Stage__c, Source__c, CreatedDate, Primary_tag__c, Source_Bucket__c, Next_Follow_Up_Date__c, Candidate__c, Candidate__r.Candidate_ID__c, Is_ReEnquiry__c FROM Lead__c WHERE OwnerId = :UserInfo.getUserId() AND Is_DND__c = FALSE AND Is_Spam__c = FALSE AND Is_Merged__c = FALSE AND (Next_Follow_Up_Date__c = NULL OR Next_Follow_Up_Date__c <= :Datetime.now()) ORDER BY CreatedDate DESC LIMIT 200];

        System.debug('LeadQueueManagementController.getUserLeads: fetched leads count = ' + leads);
        List<Call_Log__c> callLogs = [SELECT Id, Customer_Name__c, Phone_Number__c, CreatedDate, Type__c, Candidate__c, Candidate__r.Candidate_ID__c FROM Call_Log__c WHERE OwnerId = :UserInfo.getUserId() AND Lead__c = null AND Next_Follow_Up_Date__c = null AND (Untracked__c = TRUE OR (Type__c = 'missed' AND Candidate__c != null)) ORDER BY CreatedDate DESC LIMIT 200];

        User currentUser = [SELECT Id, UserRole.Name FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1 ];

        Map<Id, String> latestCallStatusByLeadId = new Map<Id, String>();

        if (!leads.isEmpty()) {
            Set<Id> leadIds = new Set<Id>();
            for (Lead__c l : leads) {
                leadIds.add(l.Id);
            }

            List<Call_Log__c> leadCallLogs = [ SELECT Id, Lead__c, Type__c, Created_At__c FROM Call_Log__c WHERE Lead__c IN :leadIds ORDER BY Lead__c, Created_At__c DESC ];

            for (Call_Log__c log : leadCallLogs) {
                if (!latestCallStatusByLeadId.containsKey(log.Lead__c)) {
                    latestCallStatusByLeadId.put(log.Lead__c, log.Type__c);
                }
            }
        }

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

            String lastCallStatus = latestCallStatusByLeadId.get(l.Id);

            dto.primaryTag = derivePrimaryTag(l.Next_Follow_Up_Date__c, lastCallStatus, l.Candidate__c, l.Is_ReEnquiry__c);

            dto.roleTag   = currentUser.UserRole != null ? currentUser.UserRole.Name : null;
            dto.bucketTag = l.Source_Bucket__c;
            dto.nextFollowUpDate = l.Next_Follow_Up_Date__c;
            dto.candidateId = l.Candidate__c;
            dto.candidateCode = l.Candidate__r != null ? l.Candidate__r.Candidate_ID__c : null;
            allItems.add(dto);
        }

        for (Call_Log__c e : callLogs) {
            LeadQueueItemDTO dto = new LeadQueueItemDTO();
            dto.id          = e.Id;
            dto.name        = e.Customer_Name__c;
            dto.phone       = e.Phone_Number__c;
            dto.course      = 'NA';
            dto.city        = 'NA';
            dto.stage       = 'NA';
            dto.source      = 'NA';
            dto.createdDate = e.CreatedDate;
            dto.iscallLog   = true;
            dto.primaryTag  = (!String.isBlank(e.Type__c) && e.Type__c.equalsIgnoreCase('missed'))
                ? 'Missed calls'
                : 'Untracked calls';
            // dto.primaryTag  = 'Unknown';
            dto.roleTag     = currentUser.UserRole != null ? currentUser.UserRole.Name : null;
            dto.bucketTag   = 'ALL';
            dto.candidateId = e.Candidate__c;
            dto.candidateCode = e.Candidate__r != null ? e.Candidate__r.Candidate_ID__c : null;
            allItems.add(dto);
        }

        List<LeadQueueItemDTO> prioritizedItems = QueuePriorityService.assignPriorities(allItems);
        System.debug('LeadQueueManagementController.getUserLeads: prioritizedItems = ' + prioritizedItems);
        return prioritizedItems;
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