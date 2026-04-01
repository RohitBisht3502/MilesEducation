/*
    Author       : Rohit Singh Bisht
*/
public class TranscationTriggerHandler {

    public static Boolean isFirstRun = true;

    public static void createActivityLogs(List<Transcation__c> newList, Map<Id, Transcation__c> oldMap) {

        if(!isFirstRun) return;
        isFirstRun = false;

        List<Activity_Log__c> activityList = new List<Activity_Log__c>();

        // Record Type 
        Id paymentRecordTypeId = Schema.SObjectType.Activity_Log__c
            .getRecordTypeInfosByDeveloperName()
            .get('Payment')
            .getRecordTypeId();

        Set<Id> poIds = new Set<Id>();

        for(Transcation__c trans : newList){
            if(trans.Purchase_Orders__c != null){
                poIds.add(trans.Purchase_Orders__c);
            }
        }

        Map<Id, Purchase_Order__c> poMap = new Map<Id, Purchase_Order__c>();

        if(!poIds.isEmpty()){
            poMap = new Map<Id, Purchase_Order__c>([
                SELECT Id, Lead__c, Candidate__c, Student__c
                FROM Purchase_Order__c
                WHERE Id IN :poIds
            ]);
        }

      
        for(Transcation__c trans : newList) {

          
            Boolean isInsert = (oldMap == null);
            Boolean isStatusChanged = false;
            Boolean isPaymentChanged = false;

            String oldStatus = '';
            Decimal oldPayment = 0;

            if(oldMap != null && oldMap.containsKey(trans.Id)) {
                Transcation__c oldRec = oldMap.get(trans.Id);

                //  Status Change
                if(String.valueOf(oldRec.Status__c) != String.valueOf(trans.Status__c)) {
                    isStatusChanged = true;
                    oldStatus = oldRec.Status__c;
                }

                // Payment Change
                if(oldRec.Payment__c != trans.Payment__c) {
                    isPaymentChanged = true;
                    oldPayment = oldRec.Payment__c;
                }
            }

            if(isInsert || isStatusChanged || isPaymentChanged) {

                Activity_Log__c log = new Activity_Log__c();

                //Basic Fields
                log.Name = 'Transaction Log - ' + trans.Name;
                log.RecordTypeId = paymentRecordTypeId;
                log.Transcation__c = trans.Id;
                log.Transcation_Amount__c = trans.Payment__c;
                log.Transcation_Status__c = trans.Status__c;
                log.Action_Performed_By__c = UserInfo.getUserId();
                log.Logging_Id__c = 'LOG-' + trans.Id + '-' + System.currentTimeMillis();
                log.Activity_Type__c = 'Payment';

                if(trans.Purchase_Orders__c != null){

                    log.Purchase_Order__c = trans.Purchase_Orders__c;

                    Purchase_Order__c po = poMap.get(trans.Purchase_Orders__c);

                    if(po != null){
                        log.Lead__c = po.Lead__c;
                        log.Candidate__c = po.Candidate__c;
                        log.Student__c = po.Student__c;
                    }
                }

                if(isInsert){
                    log.Description__c = 'Transaction created with status: ' + trans.Status__c +
                                         ' and amount: ' + trans.Payment__c;
                }
                else if(isStatusChanged && isPaymentChanged){
                    log.Description__c = 'Status changed from ' + oldStatus + ' to ' + trans.Status__c +
                                         ' and Payment changed from ' + oldPayment + ' to ' + trans.Payment__c;
                }
                else if(isStatusChanged){
                    log.Description__c = 'Status changed from ' + oldStatus + ' to ' + trans.Status__c;
                }
                else if(isPaymentChanged){
                    log.Description__c = 'Payment changed from ' + oldPayment + ' to ' + trans.Payment__c;
                }

                activityList.add(log);
            }
        }

        if(!activityList.isEmpty()){
            ActivityLogService.insertLogs(activityList);
        }
    }
}