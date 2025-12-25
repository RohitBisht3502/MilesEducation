/*
    Author       : ROHIT SINGH BISHT
    Description  : 
*/
public class LeadQueueManagementController {

    @AuraEnabled(cacheable=true)
    public static List<LeadQueueItemDTO> getUserLeads() {

        List<Lead__c> leads = [
            SELECT Id, Name, Phone__c, Email__c, Course__c, City__c,
                   Stage__c, Source__c, CreatedDate,
                   Primary_tag__c, Source_Bucket__c,
                   Next_Follow_Up_Date__c,
                   Candidate__c,Is_ReEnquiry__c
            FROM Lead__c 
             WHERE OwnerId = :UserInfo.getUserId()
             AND Is_DND__c = FALSE
             AND Is_Spam__c = FALSE
             AND Is_Merged__c = FALSE
             AND (Next_Follow_Up_Date__c = NULL OR Next_Follow_Up_Date__c <= :Datetime.now())
             ORDER BY CreatedDate DESC LIMIT 200 ];

        List<Call_Log__c> enquiries = [
            SELECT Id, Customer_Name__c, Phone_Number__c,CreatedDate
            FROM Call_Log__c
            WHERE (Untracked__c = TRUE)
            AND OwnerId = :UserInfo.getUserId()
            ORDER BY CreatedDate DESC LIMIT 200];

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

        if (nextFollowupDate != null) {
            if (nextFollowupDate >= startOfToday && nextFollowupDate < startOfTomorrow) {
                return 'Todays';
            }
            if (nextFollowupDate < startOfToday) {
                return 'Delays';
            }
        }

        if (!String.isBlank(callStatus) && callStatus.equalsIgnoreCase('Missed')) {
            return 'Missed calls';
        }

        if (isReEnquiry == true) {
            return 'MHP';
        }

        return 'NE';
    }

    @AuraEnabled
    public static void saveLeadFeedbackAuto(Id leadId, String callId, String feedback, Datetime nextFollowUpDate, String l1, String l2, String stage, String level) {
        System.debug('leadId  >>>'+leadId);
        System.debug('callId  >>>'+callId);
        if (leadId == null || String.isBlank(callId)) {
            throw new AuraHandledException('Lead Id and Call Id are required.');
        }

        List<Call_Log__c> logs = [ SELECT Id FROM Call_Log__c WHERE Lead__c = :leadId AND Call_Id__c = :callId LIMIT 1 ];

        if (logs.isEmpty()) {
            throw new AuraHandledException('No call log found for this Lead and Call Id.');
        }

        Call_Log__c logRecord = logs[0];

        logRecord.Feedback__c = feedback;
        logRecord.Next_Follow_Up_Date__c = nextFollowUpDate;
        logRecord.L1__c = l1;
        logRecord.L2__c = l2;
        logRecord.Stage__c = stage;
        logRecord.Course__c = level;

        update logRecord;

        SObjectType sType = leadId.getSObjectType();
        String objName = sType.getDescribe().getName();

        if (objName == 'Lead__c') {
            update new Lead__c(
                Id = leadId,
                Stage__c = stage,
                Course__c = level,
                Next_Follow_Up_Date__c = nextFollowUpDate
            );
        } else if (objName == 'Enquiry__c') {
            update new Enquiry__c(
                Id = leadId,
                Stage__c = stage,
                Course__c = level
            );
        }
    }

}