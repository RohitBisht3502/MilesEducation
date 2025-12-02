public without sharing class CallLogTriggerFrameworkHandler extends BaseTriggerHandler {

    public CallLogTriggerFrameworkHandler(List<Call_Log__c> newList, List<Call_Log__c> oldList, Map<Id, Call_Log__c> newMap, Map<Id, Call_Log__c> oldMap) {
        super(
            (List<SObject>)newList,
            (List<SObject>)oldList,
            (Map<Id, SObject>)newMap,
            (Map<Id, SObject>)oldMap
        );
    }

    private List<Call_Log__c> getNewLogs() {
        return (List<Call_Log__c>)newList;
    }

    private Map<Id, Call_Log__c> getOldLogMap() {
        return (Map<Id, Call_Log__c>)oldMap;
    }

    public override void afterInsert() {
        try {
            CallLogTriggerHandler.createActivityLogs(getNewLogs(), null, true);
        } catch (Exception e) {
            // kept same behavior: swallow errors
        }
    }

    public override void afterUpdate() {
        try {
            CallLogTriggerHandler.createActivityLogs(getNewLogs(), getOldLogMap(), false);
        } catch (Exception e) {
            // kept same behavior: swallow errors
        }
    }

    public override void beforeInsert() {}
    public override void beforeUpdate() {}
    public override void beforeDelete() {}
    public override void afterDelete() {}
    public override void afterUndelete() {}
}