public without sharing class EmailTriggerFrameworkHandler extends BaseTriggerHandler {

    public EmailTriggerFrameworkHandler(
        List<Email__c> newList,
        List<Email__c> oldList,
        Map<Id, Email__c> newMap,
        Map<Id, Email__c> oldMap
    ) {
        super(
            (List<SObject>)newList,
            (List<SObject>)oldList,
            (Map<Id, SObject>)newMap,
            (Map<Id, SObject>)oldMap
        );
    }

    private List<Email__c> getNewEmails() {
        return (List<Email__c>)newList;
    }

    private Map<Id, Email__c> getOldEmailMap() {
        return (Map<Id, Email__c>)oldMap;
    }

    public override void afterInsert() {
        PrimaryContactSyncService.syncPrimaryEmails(getNewEmails(), null);
    }

    public override void afterUpdate() {
        PrimaryContactSyncService.syncPrimaryEmails(getNewEmails(), getOldEmailMap());
    }
}