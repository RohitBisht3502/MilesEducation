trigger EventTrigger on Event (before insert, after insert, before update, after update, before delete, after delete, after undelete) {
    EventTriggerFrameworkHandler handler = new EventTriggerFrameworkHandler(
        (List<Event>)Trigger.new,
        (Trigger.isUpdate || Trigger.isDelete || Trigger.isUndelete) 
            ? (List<Event>)Trigger.old 
            : new List<Event>(),
        (Trigger.isInsert || Trigger.isUpdate) 
            ? (Map<Id, Event>)Trigger.newMap 
            : new Map<Id, Event>(),
        (Trigger.isUpdate || Trigger.isDelete || Trigger.isUndelete) 
            ? (Map<Id, Event>)Trigger.oldMap 
            : new Map<Id, Event>()
    );

    if (Trigger.isBefore) {
        if (Trigger.isInsert) handler.beforeInsert();
        if (Trigger.isUpdate) handler.beforeUpdate();
        if (Trigger.isDelete) handler.beforeDelete();
    }

    if (Trigger.isAfter) {
        if (Trigger.isInsert) handler.afterInsert();
        if (Trigger.isUpdate) handler.afterUpdate();
        if (Trigger.isDelete) handler.afterDelete();
        if (Trigger.isUndelete) handler.afterUndelete();
    }
}