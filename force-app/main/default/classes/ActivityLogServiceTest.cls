@IsTest
public without sharing class ActivityLogServiceTest {

    public class Request {
        public String name;
        public String activityType;
        public String description;
        public String createdBy;
        public Datetime changedDateTime;
        public Id actionPerformedBy;
        public String loggingId; 
        public Id leadId;
        public Id candidateId;
        public Id studentId;
        public Id enquiryId;
        public Id purchaseOrderId;
        public Id transcationId;
        public Id roundRobinPoolId;
        public Id previousOwnerId;
        public Id newOwnerId;
        public Id recordTypeId;
        public Map<String, Object> extraFields = new Map<String, Object>();
    }

    public static Activity_Log__c createLog(Request request) {
        Activity_Log__c logRec = new Activity_Log__c();
        applyRequest(logRec, request);
        return logRec;
    }

    public static void applyRequest(Activity_Log__c logRec, Request request) {
        if (logRec == null || request == null) {
            return;
        }

        Map<String, Schema.SObjectField> fieldMap = Activity_Log__c.SObjectType.getDescribe().fields.getMap();

        logRec.Name = request.name;
        logRec.Activity_Type__c = request.activityType;
        logRec.Description__c = request.description;
        logRec.Created_By__c = request.createdBy;
        logRec.Changed_Date_Time__c = request.changedDateTime;
        logRec.Action_Performed_By__c = request.actionPerformedBy;

        // SAFE handling
        if (String.isNotBlank(request.loggingId)) {
            logRec.Logging_Id__c = request.loggingId;
        }

        logRec.Lead__c = request.leadId;
        logRec.Candidate__c = request.candidateId;
        logRec.Student__c = request.studentId;
        logRec.Enquiry__c = request.enquiryId;
        logRec.Previous_Owner__c = request.previousOwnerId;
        logRec.New_Owner__c = request.newOwnerId;

        if (request.recordTypeId != null) {
            logRec.RecordTypeId = request.recordTypeId;
        }

        putIfFieldExists(fieldMap, logRec, 'Purchase_Order__c', request.purchaseOrderId);
        putIfFieldExists(fieldMap, logRec, 'Transcation__c', request.transcationId);
        putIfFieldExists(fieldMap, logRec, 'Round_Robin_Pool__c', request.roundRobinPoolId);

        if (request.extraFields != null) {
            for (String fieldApiName : request.extraFields.keySet()) {
                putIfFieldExists(fieldMap, logRec, fieldApiName, request.extraFields.get(fieldApiName));
            }
        }
    }

    public static void insertLogs(List<Activity_Log__c> logs) {
        if (logs == null || logs.isEmpty()) {
            return;
        }
        ActivityLogContextService.applyContext(logs);
        insert logs;
    }

    public static void updateLogs(List<Activity_Log__c> logs) {
        if (logs == null || logs.isEmpty()) {
            return;
        }
        ActivityLogContextService.applyContext(logs);
        update logs;
    }

    private static void putIfFieldExists(
        Map<String, Schema.SObjectField> fieldMap,
        Activity_Log__c logRec,
        String fieldApiName,
        Object value
    ) {
        if (fieldMap.containsKey(fieldApiName)) {
            logRec.put(fieldApiName, value);
        }
    }
}