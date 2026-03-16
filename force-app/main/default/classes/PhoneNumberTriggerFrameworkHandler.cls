public without sharing class PhoneNumberTriggerFrameworkHandler extends BaseTriggerHandler {

    public PhoneNumberTriggerFrameworkHandler(
        List<Phone_Number__c> newList,
        List<Phone_Number__c> oldList,
        Map<Id, Phone_Number__c> newMap,
        Map<Id, Phone_Number__c> oldMap
    ) {
        super(
            (List<SObject>)newList,
            (List<SObject>)oldList,
            (Map<Id, SObject>)newMap,
            (Map<Id, SObject>)oldMap
        );
    }

    private List<Phone_Number__c> getNewPhoneNumbers() {
        return (List<Phone_Number__c>)newList;
    }

    private Map<Id, Phone_Number__c> getOldPhoneMap() {
        return (Map<Id, Phone_Number__c>)oldMap;
    }

    public override void afterInsert() {
        PrimaryContactSyncService.syncPrimaryPhoneNumbers(getNewPhoneNumbers(), null);
    }

    public override void afterUpdate() {
        PrimaryContactSyncService.syncPrimaryPhoneNumbers(getNewPhoneNumbers(), getOldPhoneMap());
    }
}