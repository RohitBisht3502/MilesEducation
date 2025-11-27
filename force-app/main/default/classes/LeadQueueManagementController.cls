public class LeadQueueManagementController {

    @AuraEnabled(cacheable=true)
    public static List<LeadQueueItemDTO> getUserLeads() {

        List<Lead__c> leads = [
            SELECT Id, Name, Phone__c, Email__c, Course__c, City__c,
                   Stage__c, Source__c, CreatedDate,
                   Primary_tag__c, Source_Bucket__c,
                   Next_Follow_Up_Date__c,
                   Candidate__c,
                   Is_ReEnquiry__c
            FROM Lead__c WHERE Next_Follow_Up_Date__c <= :Datetime.now()
            AND ownerId = :UserInfo.getUserId()
            ORDER BY CreatedDate DESC LIMIT 200];

        List<Enquiry__c> enquiries = [
            SELECT Id, Name, Phone_Number__c, Email__c, Course__c, City__c,
                   Coming_From__c, Stage__c, CreatedDate,
                   Primary_tag__c, Source_Bucket__c
            FROM Enquiry__c
            WHERE Stage__c = 'Untracked'
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
            dto.source      = l.Source__c;
            dto.createdDate = l.CreatedDate;
            dto.isEnquiry   = false;

            String lastCallStatus = latestCallStatusByLeadId.get(l.Id);

            dto.primaryTag = derivePrimaryTag(
                l.Next_Follow_Up_Date__c,
                lastCallStatus,
                l.Candidate__c,
                l.Is_ReEnquiry__c
            );

            dto.roleTag   = currentUser.UserRole != null ? currentUser.UserRole.Name : null;
            dto.bucketTag = l.Source_Bucket__c;
            allItems.add(dto);
        }

        for (Enquiry__c e : enquiries) {
            LeadQueueItemDTO dto = new LeadQueueItemDTO();
            dto.id          = e.Id;
            dto.name        = e.Name;
            dto.phone       = e.Phone_Number__c;
            dto.course      = e.Course__c;
            dto.city        = e.City__c;
            dto.stage       = e.Stage__c;
            dto.source      = e.Coming_From__c;
            dto.createdDate = e.CreatedDate;
            dto.isEnquiry   = true;
            dto.primaryTag  = 'Untracked';
            dto.roleTag     = currentUser.UserRole != null ? currentUser.UserRole.Name : null;
            dto.bucketTag   = e.Source_Bucket__c;
            allItems.add(dto);
        }

        List<LeadQueueItemDTO> prioritizedItems = QueuePriorityService.assignPriorities(allItems);

        for (LeadQueueItemDTO item : prioritizedItems) {
            item.displayStage = item.isEnquiry ? item.source : item.stage;
        }

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
public static void saveLeadFeedbackAuto(
    Id leadId,
    String callId,
    String feedback,
    Datetime nextFollowUpDate,
    String l1,
    String l2,
    String stage,
    String level
) {
    if (leadId == null || String.isBlank(callId)) {
        throw new AuraHandledException('Lead Id and Call Id are required.');
    }

    // Fetch existing call log safely
    List<Call_Log__c> logs = [
        SELECT Id
        FROM Call_Log__c
        WHERE Lead__c = :leadId
        AND Call_Id__c = :callId
        LIMIT 1
    ];

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

    // Update Lead or Enquiry
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