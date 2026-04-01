public without sharing class WorkExperienceTriggerFrameworkHandler extends BaseTriggerHandler {

    public WorkExperienceTriggerFrameworkHandler(
        List<Work_Experience__c> newList,
        List<Work_Experience__c> oldList,
        Map<Id, Work_Experience__c> newMap,
        Map<Id, Work_Experience__c> oldMap
    ) {
        super(
            (List<SObject>)newList,
            (List<SObject>)oldList,
            (Map<Id, SObject>)newMap,
            (Map<Id, SObject>)oldMap
        );
    }

    private List<Work_Experience__c> getNewWorkExperiences() { return (List<Work_Experience__c>)newList; }
    private Map<Id, Work_Experience__c> getOldWorkExperienceMap() { return (Map<Id, Work_Experience__c>)oldMap; }

    public override void afterInsert() {
        DataChangeEventHelper.publishEvents(getNewWorkExperiences(), null, 'Work_Experience__c');
    }

    public override void afterUpdate() {
        DataChangeEventHelper.publishEvents(getNewWorkExperiences(), (Map<Id, SObject>)getOldWorkExperienceMap(), 'Work_Experience__c');
    }
}