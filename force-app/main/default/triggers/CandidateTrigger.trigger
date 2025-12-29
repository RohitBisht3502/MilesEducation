trigger CandidateTrigger on Lead (before insert, after insert, before update, after update, before delete, after delete, after undelete) {

    // Initialize the framework handler
    CandidateTriggerFrameworkHandler handler = new CandidateTriggerFrameworkHandler(
        (List<Lead>)Trigger.new,
        (Trigger.isUpdate || Trigger.isDelete || Trigger.isUndelete) 
            ? (List<Lead>)Trigger.old 
            : new List<Lead>(),
        (Trigger.isInsert || Trigger.isUpdate) 
            ? (Map<Id, Lead>)Trigger.newMap 
            : new Map<Id, Lead>(),
        (Trigger.isUpdate || Trigger.isDelete || Trigger.isUndelete) 
            ? (Map<Id, Lead>)Trigger.oldMap 
            : new Map<Id, Lead>()
    );

    // ===== BEFORE =====
    if (Trigger.isBefore) {
        if (Trigger.isInsert) handler.beforeInsert();
        if (Trigger.isUpdate) handler.beforeUpdate();
        if (Trigger.isDelete) handler.beforeDelete();
    }

    // ===== AFTER =====
    if (Trigger.isAfter) {
        if (Trigger.isInsert) handler.afterInsert();
        if (Trigger.isUpdate) handler.afterUpdate();
        if (Trigger.isDelete) handler.afterDelete();
        if (Trigger.isUndelete) handler.afterUndelete();
    }
}