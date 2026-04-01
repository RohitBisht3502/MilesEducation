public class EnqTriggerHandler {

    private static final String ENQUIRY_ACTIVITY_TYPE = 'Enquiry';

    public static void isInsert(List<Enquiry__c> newList) {
        List<Activity_Log__c> logsToInsert = new List<Activity_Log__c>();
        Id enquiryRecordTypeId = getActivityLogRecordTypeId('Enquiry');

        for (Enquiry__c newEq : newList) {
            Activity_Log__c log = new Activity_Log__c();

            log.Name = 'Enquiry created';
            log.Enquiry__c = newEq.Id;
            log.Activity_Type__c = ENQUIRY_ACTIVITY_TYPE;
            log.Enquiry_TimeStamp__c = System.now();
            log.Action_Performed_By__c = UserInfo.getUserId();
            log.Stage__c = newEq.Stage__c;
            log.Logging_Id__c = newEq.Id;
            log.Description__c = 'Enquiry created.';
            if (enquiryRecordTypeId != null) {
                log.RecordTypeId = enquiryRecordTypeId;
            }
            logsToInsert.add(log);
        }

        if (!logsToInsert.isEmpty()) {
            ActivityLogService.insertLogs(logsToInsert);
        }
    }

    public static void isAfterUpdate(List<Enquiry__c> newList, Map<Id, Enquiry__c> oldMap) {

        List<Activity_Log__c> logsToInsert = new List<Activity_Log__c>();
        Id enquiryRecordTypeId = getActivityLogRecordTypeId('Enquiry');

        for (Enquiry__c newRec : newList) {

            Enquiry__c oldRec = oldMap.get(newRec.Id);

            if (oldRec.Stage__c == 'Untracked' && newRec.Stage__c == 'Tracked') {

                Activity_Log__c log = new Activity_Log__c();

                log.Name = 'Stage changed from Untracked to Tracked';
                log.Enquiry__c = newRec.Id;
                log.Activity_Type__c = ENQUIRY_ACTIVITY_TYPE;
                log.Enquiry_TimeStamp__c = System.now();
                log.Action_Performed_By__c = UserInfo.getUserId();
                log.Stage__c = newRec.Stage__c;
                log.Logging_Id__c = newRec.Id;
                log.Description__c = 'Enquiry stage changed from Untracked to Tracked.';
                if (enquiryRecordTypeId != null) {
                    log.RecordTypeId = enquiryRecordTypeId;
                }

                logsToInsert.add(log);
            }
        }

        if (!logsToInsert.isEmpty()) {
            ActivityLogService.insertLogs(logsToInsert);
        }
    }

    private static Id getActivityLogRecordTypeId(String recordTypeName) {
        if (String.isBlank(recordTypeName)) {
            return null;
        }

        Map<String, Schema.RecordTypeInfo> recordTypeInfos =
            Schema.SObjectType.Activity_Log__c.getRecordTypeInfosByName();

        if (recordTypeInfos != null && recordTypeInfos.containsKey(recordTypeName)) {
            return recordTypeInfos.get(recordTypeName).getRecordTypeId();
        }

        return null;
    }
}