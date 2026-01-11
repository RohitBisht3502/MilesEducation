trigger RoundRobinPoolTriggers on Round_Robin_Pool__c (after update) {
    if (Trigger.isAfter && Trigger.isUpdate) {
        RoundRobinPoolHelpers.handleWeightChange(
            Trigger.new,
            Trigger.oldMap
        );
    }
}