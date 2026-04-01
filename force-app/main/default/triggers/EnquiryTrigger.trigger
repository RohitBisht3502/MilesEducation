trigger EnquiryTrigger on Enquiry__c (before update, after insert , after update) {

    // if (Trigger.isAfter && Trigger.isInsert) {
    //     EnquiryTriggerHandler.handleReEnquiryUpgrade(Trigger.new);
    // }
    if(Trigger.isBefore){
        if(Trigger.isInsert) EnquiryTriggerHandler.handleBeforeInsert(Trigger.new);
        if(Trigger.isUpdate) EnquiryTriggerHandler.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
    }

     if (Trigger.isAfter) {
        if (Trigger.isInsert) {
            EnqTriggerHandler.isInsert(Trigger.new);
            DataChangeEventHelper.publishEvents(Trigger.new, null, 'Enquiry__c');
        }

        if (Trigger.isUpdate) {
            EnqTriggerHandler.isAfterUpdate(Trigger.new, Trigger.oldMap);
            DataChangeEventHelper.publishEvents(Trigger.new, Trigger.oldMap, 'Enquiry__c');
        }
    }

}