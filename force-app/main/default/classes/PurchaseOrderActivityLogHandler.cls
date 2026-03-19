public class PurchaseOrderActivityLogHandler {

    private static final String ENROLMENT_FORM_VALUE = 'Enrolment Form';

    public static void handleAfterInsert(List<Purchase_Order__c> newList) {
        createPurchaseOrderActivityLogs(newList, null, true);
    }

    public static void handleAfterUpdate(
        List<Purchase_Order__c> newList,
        Map<Id, Purchase_Order__c> oldMap
    ) {
        createPurchaseOrderActivityLogs(newList, oldMap, false);
    }

    private static void createPurchaseOrderActivityLogs(
        List<Purchase_Order__c> newList,
        Map<Id, Purchase_Order__c> oldMap,
        Boolean isInsert
    ) {
        if (newList == null || newList.isEmpty()) {
            return;
        }

        Map<String, Schema.SObjectField> activityFieldMap = Schema.SObjectType.Activity_log__c.fields.getMap();
        Id enrolmentFormRecordTypeId = getEnrolmentFormRecordTypeId();
        List<Activity_log__c> logsToInsert = new List<Activity_log__c>();

        for (Purchase_Order__c po : newList) {
            if (po == null) {
                continue;
            }

            Purchase_Order__c oldPo = oldMap != null ? oldMap.get(po.Id) : null;
            if (!isInsert && oldPo != null && oldPo.EF_Status__c == po.EF_Status__c) {
                continue;
            }

            Activity_log__c log = new Activity_log__c();
            log.Activity_Type__c = ENROLMENT_FORM_VALUE;
            log.Logging_Id__c = po.Id;
            log.Lead__c = po.Lead__c;
            log.Candidate__c = po.Candidate__c;
            log.Action_Performed_By__c = isInsert ? po.CreatedById : po.LastModifiedById;
            log.Changed_Date_Time__c = isInsert ? po.CreatedDate : po.LastModifiedDate;
            log.Created_By__c = UserInfo.getName();
            if (enrolmentFormRecordTypeId != null) {
                log.RecordTypeId = enrolmentFormRecordTypeId;
            }

            if (activityFieldMap.containsKey('Purchase_Order__c')) {
                log.put('Purchase_Order__c', po.Id);
            }
            if (activityFieldMap.containsKey('EF_Status__c')) {
                log.put('EF_Status__c', po.EF_Status__c);
            }

            if (isInsert) {
                log.Name = 'Purchase Order Created';
                log.Description__c = 'Purchase order created.';
            } else {
                String oldStatus = String.isBlank(oldPo.EF_Status__c) ? 'blank' : oldPo.EF_Status__c;
                String newStatus = String.isBlank(po.EF_Status__c) ? 'blank' : po.EF_Status__c;
                log.Name = 'Purchase Order EF Status Updated';
                log.Description__c =
                    'Purchase order EF status changed from ' + oldStatus + ' to ' + newStatus + '.';
            }

            logsToInsert.add(log);
        }

        if (!logsToInsert.isEmpty()) {
            insert logsToInsert;
        }
    }

    private static Id getEnrolmentFormRecordTypeId() {
        Map<String, Schema.RecordTypeInfo> recordTypeInfos =
            Schema.SObjectType.Activity_log__c.getRecordTypeInfosByDeveloperName();

        if (recordTypeInfos.containsKey('Enrolment_Form')) {
            return recordTypeInfos.get('Enrolment_Form').getRecordTypeId();
        }

        for (Schema.RecordTypeInfo recordTypeInfo :
            Schema.SObjectType.Activity_log__c.getRecordTypeInfos()) {
            if (recordTypeInfo != null &&
                recordTypeInfo.isAvailable() &&
                recordTypeInfo.getName() == ENROLMENT_FORM_VALUE) {
                return recordTypeInfo.getRecordTypeId();
            }
        }

        return null;
    }
}