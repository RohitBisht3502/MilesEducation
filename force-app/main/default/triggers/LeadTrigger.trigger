trigger LeadTrigger on Lead (before insert,after insert,after update,before update) {
        if (Trigger.isBefore && Trigger.isInsert) {
       // RoundRobinService.assignForLeads(Trigger.new);
    }
    
   if (Trigger.isBefore) {
        if (Trigger.isUpdate) {
            TriggerRoundRobinService.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
        }
    } 
}