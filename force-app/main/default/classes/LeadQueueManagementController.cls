/*
    Author       : ROHIT SINGH BISHT
    Description  : 
*/
public class LeadQueueManagementController {

    @AuraEnabled(cacheable=true)
    public static List<LeadQueueItemDTO> getUserLeads() {
        Map<Id, String> latestTrackedCallTypeByLeadId = new Map<Id, String>();
        Set<Id> missedTrackedLeadIds = new Set<Id>();

        for (Call_Log__c cl : [SELECT Lead__c, Type__c, Created_At__c FROM Call_Log__c WHERE OwnerId = :UserInfo.getUserId() AND Lead__c != null ORDER BY Created_At__c DESC LIMIT 500]) {
            if (cl.Lead__c == null || latestTrackedCallTypeByLeadId.containsKey(cl.Lead__c)) {
                continue;
            }

            latestTrackedCallTypeByLeadId.put(cl.Lead__c, cl.Type__c);
            if (!String.isBlank(cl.Type__c) && cl.Type__c.equalsIgnoreCase('missed')) {
                missedTrackedLeadIds.add(cl.Lead__c);
            }
        }

        List<Lead__c> leads = [SELECT Id, Name, Phone__c, Email__c, Course__c, City__c, Stage__c, Source__c, CreatedDate, Primary_tag__c, Source_Bucket__c, Next_Follow_Up_Date__c, Candidate__c, Is_ReEnquiry__c FROM Lead__c WHERE OwnerId = :UserInfo.getUserId() AND Is_DND__c = FALSE AND Is_Spam__c = FALSE AND Is_Merged__c = FALSE AND (Next_Follow_Up_Date__c = NULL OR Next_Follow_Up_Date__c <= :Datetime.now() OR Id IN :missedTrackedLeadIds) ORDER BY CreatedDate DESC LIMIT 200];

        System.debug('LeadQueueManagementController.getUserLeads: fetched leads count = ' + leads);
        List<Call_Log__c> enquiries = [SELECT Id, Customer_Name__c, Phone_Number__c, CreatedDate FROM Call_Log__c WHERE (Untracked__c = TRUE) AND OwnerId = :UserInfo.getUserId() AND Lead__c = null ORDER BY CreatedDate DESC LIMIT 200];

        User currentUser = [SELECT Id, UserRole.Name FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1 ];

        Map<Id, String> latestCallStatusByLeadId = new Map<Id, String>();

        if (!leads.isEmpty()) {
            Set<Id> leadIds = new Set<Id>();
            for (Lead__c l : leads) {
                leadIds.add(l.Id);
            }

            List<Call_Log__c> callLogs = [ SELECT Id, Lead__c, Type__c, Created_At__c FROM Call_Log__c WHERE Lead__c IN :leadIds ORDER BY Lead__c, Created_At__c DESC ];

            for (Call_Log__c log : callLogs) {
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
            allItems.add(dto);
        }

        for (Call_Log__c e : enquiries) {
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
            dto.primaryTag  = 'Untracked calls';
            // dto.primaryTag  = 'Unknown';
            dto.roleTag     = currentUser.UserRole != null ? currentUser.UserRole.Name : null;
            dto.bucketTag   = 'ALL';
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