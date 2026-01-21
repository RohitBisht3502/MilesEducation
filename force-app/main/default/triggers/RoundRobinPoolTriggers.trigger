trigger RoundRobinPoolTriggers on Round_Robin_Pool__c (after update) {
    if (Trigger.isAfter && Trigger.isUpdate) {

       
        Boolean weightChanged = false;

        for (Round_Robin_Pool__c r : Trigger.new) {
            Round_Robin_Pool__c oldR = Trigger.oldMap.get(r.Id);
            if (oldR != null && r.Assigned_Weight__c != oldR.Assigned_Weight__c) {
                weightChanged = true;
                break;
            }
        }

        if (!weightChanged) {
            return;
        }

        RoundRobinPoolHelpers.handleWeightChange(
            Trigger.new,
            Trigger.oldMap
        );
    }
}