trigger LeadTrigger on Lead (before insert, after insert, before update, after update) {

    // ===== BEFORE INSERT =====
    if (Trigger.isBefore && Trigger.isInsert) {
        LeadTriggerHelperClass.handleBeforeInsert(Trigger.new);
    }

    // ===== BEFORE UPDATE =====
    if (Trigger.isBefore && Trigger.isUpdate) {
        LeadTriggerHelperClass.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
    }

    // ===== AFTER INSERT =====
    if (Trigger.isAfter && Trigger.isInsert) {
        LeadTriggerHelperClass.handleAfterInsert(Trigger.new);
    }

    // ===== AFTER UPDATE =====
    if (Trigger.isAfter && Trigger.isUpdate) {
        LeadTriggerHelperClass.handleAfterUpdate(Trigger.new, Trigger.oldMap);
    }
}