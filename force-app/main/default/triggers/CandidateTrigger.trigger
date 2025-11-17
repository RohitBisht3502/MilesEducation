trigger CandidateTrigger on Lead (before insert, after insert, before update, after update) {

    // ===== BEFORE INSERT =====
    if (Trigger.isBefore && Trigger.isInsert) {
        CandidateTriggerHelperClass.handleBeforeInsert(Trigger.new);
    }

    // ===== BEFORE UPDATE =====
    if (Trigger.isBefore && Trigger.isUpdate) {
        CandidateTriggerHelperClass.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
    }

    // ===== AFTER INSERT =====
    if (Trigger.isAfter && Trigger.isInsert) {
        CandidateTriggerHelperClass.handleAfterInsert(Trigger.new);
    }

}