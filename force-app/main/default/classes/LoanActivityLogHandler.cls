public without sharing class LoanActivityLogHandler {

    public static void createLoanActivityLogs(List<Loan__c> newList, Map<Id, Loan__c> oldMap) {
        if (newList == null || newList.isEmpty() || oldMap == null) {
            return;
        }

        Id paymentRecordTypeId = getPaymentRecordTypeId();
        List<Activity_Log__c> logsToInsert = new List<Activity_Log__c>();

        for (Loan__c loanRec : newList) {
            Loan__c oldRec = oldMap.get(loanRec.Id);
            if (oldRec == null) {
                continue;
            }

            Boolean amountChanged = oldRec.Amount_requested__c != loanRec.Amount_requested__c;
            Boolean statusChanged = oldRec.Loan_status__c != loanRec.Loan_status__c;

            if (!amountChanged && !statusChanged) {
                continue;
            }

            Activity_Log__c log = new Activity_Log__c();
            log.Name = 'Loan Updated';
            log.Activity_Type__c = 'Payment';
            log.RecordTypeId = paymentRecordTypeId;
            log.Logging_Id__c = loanRec.Id;
            log.Lead__c = loanRec.Lead__c;
            log.Candidate__c = loanRec.Candidate__c;
            log.Action_Performed_By__c = loanRec.LastModifiedById;
            log.Changed_Date_Time__c = loanRec.LastModifiedDate;
            log.Created_By__c = UserInfo.getName();
            log.Loan_status__c = loanRec.Loan_status__c;
            log.Transcation_Amount__c = loanRec.Amount_requested__c;

            if (amountChanged && statusChanged) {
                log.Description__c =
                    'Loan amount changed from ' + oldRec.Amount_requested__c + ' to ' + loanRec.Amount_requested__c +
                    ' and loan status changed from ' + oldRec.Loan_status__c + ' to ' + loanRec.Loan_status__c + '.';
            } else if (amountChanged) {
                log.Description__c =
                    'Loan amount changed from ' + oldRec.Amount_requested__c + ' to ' + loanRec.Amount_requested__c + '.';
            } else {
                log.Description__c =
                    'Loan status changed from ' + oldRec.Loan_status__c + ' to ' + loanRec.Loan_status__c + '.';
            }

            logsToInsert.add(log);
        }

        if (!logsToInsert.isEmpty()) {
            insert logsToInsert;
        }
    }

    private static Id getPaymentRecordTypeId() {
        Map<String, Schema.RecordTypeInfo> recordTypeInfos =
            Schema.SObjectType.Activity_Log__c.getRecordTypeInfosByDeveloperName();
        return recordTypeInfos.containsKey('Payment')
            ? recordTypeInfos.get('Payment').getRecordTypeId()
            : null;
    }
}
