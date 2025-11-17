trigger LeadTrigger on Lead__c (before insert, after insert, before update, after update) {
    
    if (Trigger.isBefore && Trigger.isUpdate) {
        EnquiryStageService.validateStageTransitions(Trigger.new, Trigger.oldMap);
    }
    
     // ===== AFTER INSERT =====
    if (Trigger.isAfter && Trigger.isInsert) {
        LeadTriggerHelperClass.handleAfterInsert(Trigger.new);
    }
    
    
}