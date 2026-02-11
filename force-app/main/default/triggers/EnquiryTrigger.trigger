trigger EnquiryTrigger on Enquiry__c (before update, after insert) {

    // if (Trigger.isAfter && Trigger.isInsert) {
    //     EnquiryTriggerHandler.handleReEnquiryUpgrade(Trigger.new);
    // }
    if(Trigger.isBefore){
        if(Trigger.isInsert) EnquiryTriggerHandler.handleBeforeInsert(Trigger.new);
        if(Trigger.isUpdate) EnquiryTriggerHandler.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
    }

}