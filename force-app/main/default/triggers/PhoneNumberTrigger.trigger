trigger PhoneNumberTrigger on Phone_Number__c (after insert, after update) {

    PhoneNumberTriggerFrameworkHandler handler = new PhoneNumberTriggerFrameworkHandler(
        (List<Phone_Number__c>)Trigger.new,
        Trigger.isUpdate
            ? (List<Phone_Number__c>)Trigger.old
            : new List<Phone_Number__c>(),
        (Map<Id, Phone_Number__c>)Trigger.newMap,
        Trigger.isUpdate
            ? (Map<Id, Phone_Number__c>)Trigger.oldMap
            : new Map<Id, Phone_Number__c>()
    );

    if (Trigger.isAfter) {
        if (Trigger.isInsert){
            
             handler.afterInsert();
 DataChangeEventHelper.publishEvents(Trigger.new, null, 'Phone_Number__c');


        }
        if (Trigger.isUpdate){
            
             handler.afterUpdate();
             DataChangeEventHelper.publishEvents(Trigger.new, Trigger.oldMap, 'Phone_Number__c');


        }
    }
}