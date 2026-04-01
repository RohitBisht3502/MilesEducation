public without sharing class CertificationTriggerFrameworkHandler extends BaseTriggerHandler {

    public CertificationTriggerFrameworkHandler(
        List<Certification__c> newList,
        List<Certification__c> oldList,
        Map<Id, Certification__c> newMap,
        Map<Id, Certification__c> oldMap
    ) {
        super(
            (List<SObject>)newList,
            (List<SObject>)oldList,
            (Map<Id, SObject>)newMap,
            (Map<Id, SObject>)oldMap
        );
    }

    private List<Certification__c> getNewCertifications() { return (List<Certification__c>)newList; }
    private Map<Id, Certification__c> getOldCertificationMap() { return (Map<Id, Certification__c>)oldMap; }

    public override void afterInsert() {
        DataChangeEventHelper.publishEvents(getNewCertifications(), null, 'Certification__c');
    }

    public override void afterUpdate() {
        DataChangeEventHelper.publishEvents(getNewCertifications(), (Map<Id, SObject>)getOldCertificationMap(), 'Certification__c');
    }
}