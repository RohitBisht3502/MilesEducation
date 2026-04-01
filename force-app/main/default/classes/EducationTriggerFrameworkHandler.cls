public without sharing class EducationTriggerFrameworkHandler extends BaseTriggerHandler {

    public EducationTriggerFrameworkHandler(
        List<Education__c> newList,
        List<Education__c> oldList,
        Map<Id, Education__c> newMap,
        Map<Id, Education__c> oldMap
    ) {
        super(
            (List<SObject>)newList,
            (List<SObject>)oldList,
            (Map<Id, SObject>)newMap,
            (Map<Id, SObject>)oldMap
        );
    }

    private List<Education__c> getNewEducations() { return (List<Education__c>)newList; }
    private Map<Id, Education__c> getOldEducationMap() { return (Map<Id, Education__c>)oldMap; }

    public override void afterInsert() {
        DataChangeEventHelper.publishEvents(getNewEducations(), null, 'Education__c');
    }

    public override void afterUpdate() {
        DataChangeEventHelper.publishEvents(getNewEducations(), (Map<Id, SObject>)getOldEducationMap(), 'Education__c');
    }
}