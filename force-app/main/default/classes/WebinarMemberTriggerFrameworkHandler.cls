public without sharing class WebinarMemberTriggerFrameworkHandler extends BaseTriggerHandler {

    public WebinarMemberTriggerFrameworkHandler(
        List<Webinar_Member__c> newList,
        List<Webinar_Member__c> oldList,
        Map<Id, Webinar_Member__c> newMap,
        Map<Id, Webinar_Member__c> oldMap
    ) {
        super(
            (List<SObject>)newList,
            (List<SObject>)oldList,
            (Map<Id, SObject>)newMap,
            (Map<Id, SObject>)oldMap
        );
    }

    private List<Webinar_Member__c> getNewMembers() {
        return (List<Webinar_Member__c>)newList;
    }
    private List<Webinar_Member__c> getOldMembers() {
        return (List<Webinar_Member__c>)oldList;
    }
    private Map<Id, Webinar_Member__c> getNewMemberMap() {
        return (Map<Id, Webinar_Member__c>)newMap;
    }
    private Map<Id, Webinar_Member__c> getOldMemberMap() {
        return (Map<Id, Webinar_Member__c>)oldMap;
    }

    public override void beforeInsert() {
        WebinarMemberTriggerHandler.beforeInsert(getNewMembers());
    }
    public override void beforeUpdate() {
        WebinarMemberTriggerHandler.beforeUpdate(getNewMembers(), getOldMemberMap());
    }
    public override void beforeDelete() {
        WebinarMemberTriggerHandler.beforeDelete(getOldMembers());
    }

    public override void afterInsert() {
        WebinarMemberTriggerHandler.afterInsert(getNewMembers());
    }
    public override void afterUpdate() {
        WebinarMemberTriggerHandler.afterUpdate(getNewMembers(), getOldMemberMap());
    }
    public override void afterDelete() {
        WebinarMemberTriggerHandler.afterDelete(getOldMembers());
    }
    public override void afterUndelete() {
        WebinarMemberTriggerHandler.afterUndelete(getNewMembers());
    }
}