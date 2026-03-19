// Developer Name : Chirag Sharma 
// Created Date : 26/11/2025
// Last Modified by : Chirag Sharma
// Last Modified Date : 28/11/2025

public with sharing class LeadActivityTimelineController {

    public class ActivityLogDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String activityType;
        @AuraEnabled public String loggingId;
        @AuraEnabled public Decimal availCreditScore;
        @AuraEnabled public String l1;
        @AuraEnabled public String l2;
        @AuraEnabled public Decimal callDurationSeconds;
        @AuraEnabled public String callRecordingUrl;
        @AuraEnabled public String previousLevel;
        @AuraEnabled public String newLevel;
        @AuraEnabled public String actionByName;
        @AuraEnabled public Datetime changedDateTime;
        @AuraEnabled public String description;
        @AuraEnabled public String callLogType; 
        @AuraEnabled public String createdByText;
        @AuraEnabled public String efStatus;
        @AuraEnabled public Decimal transactionAmount;
        @AuraEnabled public String transactionStatus;
        @AuraEnabled public String loanProvider;
        @AuraEnabled public String milesLoanCode;
        @AuraEnabled public Decimal loanAmount;
        @AuraEnabled public String loanStatus;
        @AuraEnabled public String previousOwnerName;
        @AuraEnabled public String newOwnerName;
    }

    public class LeadActivityResponse {
        @AuraEnabled public Id leadId;
        @AuraEnabled public String name;
        @AuraEnabled public String phone;
        @AuraEnabled public String email;
        @AuraEnabled public String city;
        @AuraEnabled public String course;
        @AuraEnabled public String source;
        @AuraEnabled public String createdByName;
        @AuraEnabled public List<ActivityLogDTO> logs;
    }

    @AuraEnabled(cacheable=true)
    public static LeadActivityResponse getLeadActivityData(Id leadId) {
        if (leadId == null) {
            return null;
        }

        LeadActivityResponse resp = new LeadActivityResponse();
        resp.logs = new List<ActivityLogDTO>();

        Schema.SObjectType sType = leadId.getSObjectType();

        if (sType == Lead__c.SObjectType) {
            Lead__c ld = [
                SELECT Id,
                       Name,
                       Phone__c,
                       Email__c,
                       City__c,
                       Course__c,
                       Source__c,
                       CreatedBy.Name
                FROM Lead__c
                WHERE Id = :leadId
                LIMIT 1
            ];

            resp.leadId        = ld.Id;
            resp.name          = ld.Name;
            resp.phone         = ld.Phone__c;
            resp.email         = ld.Email__c;
            resp.city          = ld.City__c;
            resp.course        = ld.Course__c;
            resp.source        = ld.Source__c;
            resp.createdByName = ld.CreatedBy != null ? ld.CreatedBy.Name : null;

            List<Activity_Log__c> logs = [
                SELECT Id,
                       Name,
                       Activity_Type__c,
                       Available_Credit_Score__c,
                       Logging_Id__c,
                       Lead__c,
                       Candidate__c,
                       L1__c,
                       L2__c,
                       Call_Duration_Seconds__c,
                       Call_Recording_URL__c,
                       Previous_Level__c,
                       New_Level__c,
                       Previous_Owner__r.Name,
                       New_Owner__r.Name,
                       Action_Performed_By__r.Name,
                       Changed_Date_Time__c,
                       Description__c,
                       Created_By__c,
                       Call_Log_Type__c,
                       EF_Status__c,
                       Transcation_Amount__c,
                       Transcation_Status__c,
                       CreatedDate
                FROM Activity_Log__c
                WHERE Lead__c = :leadId
                ORDER BY CreatedDate DESC
            ];

            Map<Id, Loan__c> loanMap = getLoanMapForActivityLogs(logs);
            for (Activity_Log__c al : logs) {
                resp.logs.add(toActivityLogDTO(al, loanMap));
            }

            appendCallLogs(resp.logs, leadId, 'Lead');
            sortLogsByChangedDate(resp.logs);

            return resp;
        }

        if (sType == Lead.SObjectType) {
            Map<String, Schema.SObjectField> fMap = Schema.SObjectType.Lead.fields.getMap();
            List<String> fieldsToSelect = new List<String>{'Id','Name','Phone','Email','City','CreatedBy.Name'};

            if (fMap.containsKey('Course__c')) fieldsToSelect.add('Course__c');
            if (fMap.containsKey('Source__c')) fieldsToSelect.add('Source__c');
            if (fMap.containsKey('LeadSource')) fieldsToSelect.add('LeadSource');

            String soql = 'SELECT ' + String.join(fieldsToSelect, ',') + ' FROM Lead WHERE Id = :leadId LIMIT 1';
            Lead ldStd = Database.query(soql);

            resp.leadId = ldStd.Id;
            resp.name   = ldStd.Name;
            resp.phone  = ldStd.Phone;
            resp.email  = ldStd.Email;
            resp.city   = ldStd.City;
            resp.createdByName = ldStd.CreatedBy != null ? ldStd.CreatedBy.Name : null;

            if (fMap.containsKey('Course__c')) resp.course = (String) ldStd.get('Course__c');
            if (fMap.containsKey('Source__c')) {
                resp.source = (String) ldStd.get('Source__c');
            } else if (fMap.containsKey('LeadSource')) {
                resp.source = (String) ldStd.get('LeadSource');
            }

            List<Activity_Log__c> logsStd = [
                SELECT Id,
                       Name,
                       Activity_Type__c,
                       Available_Credit_Score__c,
                       Logging_Id__c,
                       Lead__c,
                       Candidate__c,
                       L1__c,
                       L2__c,
                       Call_Duration_Seconds__c,
                       Call_Recording_URL__c,
                       Previous_Level__c,
                       New_Level__c,
                       Previous_Owner__r.Name,
                       New_Owner__r.Name,
                       Action_Performed_By__r.Name,
                       Changed_Date_Time__c,
                       Description__c,
                       Created_By__c,
                       Call_Log_Type__c,
                       EF_Status__c,
                       Transcation_Amount__c,
                       Transcation_Status__c,
                       CreatedDate
                FROM Activity_Log__c
                WHERE Candidate__c = :leadId
                ORDER BY CreatedDate DESC
            ];

            Map<Id, Loan__c> loanMap = getLoanMapForActivityLogs(logsStd);
            for (Activity_Log__c al : logsStd) {
                resp.logs.add(toActivityLogDTO(al, loanMap));
            }

            appendCallLogs(resp.logs, leadId, 'Candidate');
            sortLogsByChangedDate(resp.logs);

            return resp;
        }

        if (sType == Account.SObjectType) {
            Account student = [
                SELECT Id,
                       Name,
                       Phone,
                       Email__c,
                       BillingCity,
                       CreatedBy.Name
                FROM Account
                WHERE Id = :leadId
                LIMIT 1
            ];

            resp.leadId = student.Id;
            resp.name = student.Name;
            resp.phone = student.Phone;
            resp.email = (String) student.get('Email__c');
            resp.city = student.BillingCity;
            resp.createdByName = student.CreatedBy != null ? student.CreatedBy.Name : null;

            List<Lead__c> linkedLeads = [
                SELECT Course__c, Source__c
                FROM Lead__c
                WHERE Student__c = :leadId
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
            if (!linkedLeads.isEmpty()) {
                resp.course = linkedLeads[0].Course__c;
                resp.source = linkedLeads[0].Source__c;
            }

            List<Activity_Log__c> studentLogs = [
                SELECT Id,
                       Name,
                       Activity_Type__c,
                       Available_Credit_Score__c,
                       Logging_Id__c,
                       Lead__c,
                       Candidate__c,
                       Student__c,
                       L1__c,
                       L2__c,
                       Call_Duration_Seconds__c,
                       Call_Recording_URL__c,
                       Previous_Level__c,
                       New_Level__c,
                       Previous_Owner__r.Name,
                       New_Owner__r.Name,
                       Action_Performed_By__r.Name,
                       Changed_Date_Time__c,
                       Description__c,
                       Created_By__c,
                       Call_Log_Type__c,
                       EF_Status__c,
                       Transcation_Amount__c,
                       Transcation_Status__c,
                       CreatedDate
                FROM Activity_Log__c
                WHERE Student__c = :leadId
                ORDER BY CreatedDate DESC
            ];

            Map<Id, Loan__c> loanMap = getLoanMapForActivityLogs(studentLogs);
            for (Activity_Log__c al : studentLogs) {
                resp.logs.add(toActivityLogDTO(al, loanMap));
            }

            appendCallLogs(resp.logs, leadId, 'Student');
            sortLogsByChangedDate(resp.logs);

            return resp;
        }

        return null;
    }

    private static ActivityLogDTO toActivityLogDTO(Activity_Log__c al, Map<Id, Loan__c> loanMap) {
        ActivityLogDTO dto = new ActivityLogDTO();
        dto.id = al.Id;
        dto.name = al.Name;
        dto.activityType = al.Activity_Type__c;
        dto.availCreditScore = al.Available_Credit_Score__c;
        dto.loggingId = al.Logging_Id__c;
        dto.l1 = al.L1__c;
        dto.l2 = al.L2__c;
        dto.callDurationSeconds = al.Call_Duration_Seconds__c;
        dto.callRecordingUrl = al.Call_Recording_URL__c;
        dto.previousLevel = al.Previous_Level__c;
        dto.newLevel = al.New_Level__c;
        dto.previousOwnerName = al.Previous_Owner__r != null ? al.Previous_Owner__r.Name : null;
        dto.newOwnerName = al.New_Owner__r != null ? al.New_Owner__r.Name : null;
        dto.actionByName = al.Action_Performed_By__r != null ? al.Action_Performed_By__r.Name : null;
        dto.changedDateTime = al.Changed_Date_Time__c;
        dto.description = al.Description__c;
        dto.createdByText = al.Created_By__c;
        dto.callLogType = al.Call_Log_Type__c;
        dto.efStatus = (String) al.get('EF_Status__c');
        dto.transactionAmount = (Decimal) al.get('Transcation_Amount__c');
        dto.transactionStatus = (String) al.get('Transcation_Status__c');
        Id loanId = tryParseId(al.Logging_Id__c);
        if (loanId != null && loanMap != null && loanMap.containsKey(loanId)) {
            Loan__c loanRec = loanMap.get(loanId);
            dto.loanProvider = loanRec.Loan_Provider__c;
            dto.milesLoanCode = loanRec.miles_loan_code__c;
            dto.loanAmount = loanRec.Amount_requested__c;
            dto.loanStatus = loanRec.Loan_status__c;
        }
        return dto;
    }

    private static Map<Id, Loan__c> getLoanMapForActivityLogs(List<Activity_Log__c> logs) {
        Set<Id> loanIds = new Set<Id>();
        for (Activity_Log__c logRec : logs) {
            Id parsedId = tryParseId(logRec.Logging_Id__c);
            if (parsedId != null) {
                loanIds.add(parsedId);
            }
        }

        if (loanIds.isEmpty()) {
            return new Map<Id, Loan__c>();
        }

        return new Map<Id, Loan__c>([
            SELECT Id, Loan_Provider__c, miles_loan_code__c, Amount_requested__c, Loan_status__c
            FROM Loan__c
            WHERE Id IN :loanIds
        ]);
    }

    private static Id tryParseId(String rawId) {
        if (String.isBlank(rawId)) {
            return null;
        }
        try {
            return Id.valueOf(rawId);
        } catch (Exception ex) {
            return null;
        }
    }

    private static void appendCallLogs(List<ActivityLogDTO> logs, Id recordId, String recordContext) {
        List<Call_Log__c> callLogs;

        if (recordContext == 'Lead') {
            callLogs = [
                SELECT Id, L1__c, L2__c, Duration_Seconds__c, Type__c, CreatedDate, CreatedBy.Name
                FROM Call_Log__c
                WHERE Lead__c = :recordId
                ORDER BY CreatedDate DESC
            ];
        } else if (recordContext == 'Candidate') {
            callLogs = [
                SELECT Id, L1__c, L2__c, Duration_Seconds__c, Type__c, CreatedDate, CreatedBy.Name
                FROM Call_Log__c
                WHERE Candidate__c = :recordId
                ORDER BY CreatedDate DESC
            ];
        } else if (recordContext == 'Student') {
            callLogs = [
                SELECT Id, L1__c, L2__c, Duration_Seconds__c, Type__c, CreatedDate, CreatedBy.Name
                FROM Call_Log__c
                WHERE Student__c = :recordId
                ORDER BY CreatedDate DESC
            ];
        } else {
            callLogs = new List<Call_Log__c>();
        }

        for (Call_Log__c cl : callLogs) {
            ActivityLogDTO dto = new ActivityLogDTO();
            dto.id = cl.Id;
            dto.name = 'Call Log';
            dto.activityType = 'Call';
            dto.loggingId = cl.Id;
            dto.l1 = cl.L1__c;
            dto.l2 = cl.L2__c;
            dto.callDurationSeconds = cl.Duration_Seconds__c;
            dto.callLogType = cl.Type__c;
            dto.changedDateTime = cl.CreatedDate;
            dto.actionByName = cl.CreatedBy != null ? cl.CreatedBy.Name : null;
            dto.createdByText = cl.CreatedBy != null ? cl.CreatedBy.Name : null;
            logs.add(dto);
        }
    }

    private static void sortLogsByChangedDate(List<ActivityLogDTO> logs) {
        if (logs == null || logs.isEmpty()) {
            return;
        }

        logs.sort(new ActivityLogDateSorter());
    }

    public class ActivityLogDateSorter implements Comparator<ActivityLogDTO> {
        public Integer compare(ActivityLogDTO a, ActivityLogDTO b) {
            Datetime left = a != null ? a.changedDateTime : null;
            Datetime right = b != null ? b.changedDateTime : null;

            if (left == null && right == null) return 0;
            if (left == null) return 1;
            if (right == null) return -1;
            if (left == right) return 0;
            return left > right ? -1 : 1;
        }
    }
}
