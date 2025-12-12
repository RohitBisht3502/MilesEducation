public without sharing class EventTriggerFrameworkHandler extends BaseTriggerHandler {

    public EventTriggerFrameworkHandler(List<Event> newList, List<Event> oldList, Map<Id, Event> newMap, Map<Id, Event> oldMap) {
        super(
            (List<SObject>)newList,
            (List<SObject>)oldList,
            (Map<Id, SObject>)newMap,
            (Map<Id, SObject>)oldMap
        );
    }

    private List<Event> getNewEvents() {
        return (List<Event>)newList;
    }

    private List<Event> getOldEvents() {
        return (List<Event>)oldList;
    }

    private Map<Id, Event> getNewEventMap() {
        return (Map<Id, Event>)newMap;
    }

    private Map<Id, Event> getOldEventMap() {
        return (Map<Id, Event>)oldMap;
    }

    public override void beforeInsert() {
        EventTriggerHandler.beforeInsert(getNewEvents());
    }

    public override void beforeUpdate() {
        EventTriggerHandler.beforeUpdate(getNewEvents(), getOldEventMap());
    }

    public override void beforeDelete() {
        EventTriggerHandler.beforeDelete(getOldEvents());
    }

    public override void afterInsert() {
        EventTriggerHandler.afterInsert(getNewEvents());
    }

    public override void afterUpdate() {
        EventTriggerHandler.afterUpdate(getNewEvents(), getOldEventMap());
    }

    public override void afterDelete() {
        EventTriggerHandler.afterDelete(getOldEvents());
    }

    public override void afterUndelete() {
        EventTriggerHandler.afterUndelete(getNewEvents());
    }
}