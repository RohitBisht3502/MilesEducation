public without sharing class WebinarTriggerFrameworkHandler extends BaseTriggerHandler {

    public WebinarTriggerFrameworkHandler(
        List<Webinar__c> newList,
        List<Webinar__c> oldList,
        Map<Id, Webinar__c> newMap,
        Map<Id, Webinar__c> oldMap
    ) {
        super(
            (List<SObject>)newList,
            (List<SObject>)oldList,
            (Map<Id, SObject>)newMap,
            (Map<Id, SObject>)oldMap
        );
    }

    private List<Webinar__c> getNewWebinars() {
        return (List<Webinar__c>)newList;
    }
    private List<Webinar__c> getOldWebinars() {
        return (List<Webinar__c>)oldList;
    }
    private Map<Id, Webinar__c> getNewWebinarMap() {
        return (Map<Id, Webinar__c>)newMap;
    }
    private Map<Id, Webinar__c> getOldWebinarMap() {
        return (Map<Id, Webinar__c>)oldMap;
    }

    public override void beforeInsert() {
        WebinarTriggerHandler.beforeInsert(getNewWebinars());
    }
    public override void beforeUpdate() {
        WebinarTriggerHandler.beforeUpdate(getNewWebinars(), getOldWebinarMap());
    }
    public override void beforeDelete() {
        WebinarTriggerHandler.beforeDelete(getOldWebinars());
    }

    public override void afterInsert() {
        WebinarTriggerHandler.afterInsert(getNewWebinars());
    }
    public override void afterUpdate() {
        WebinarTriggerHandler.afterEndGetAttendanceData(getNewWebinars(), getOldWebinarMap());
        WebinarTriggerHandler.updateWebinarMemberFieldsOnWebinarStart(getNewWebinars(), getOldWebinarMap());
    }
    public override void afterDelete() {
        WebinarTriggerHandler.afterDelete(getOldWebinars());
    }
    public override void afterUndelete() {
        WebinarTriggerHandler.afterUndelete(getNewWebinars());
    }
}