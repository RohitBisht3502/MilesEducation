public without sharing class GpFolderTriggerFrameworkHandler extends BaseTriggerHandler {

    public GpFolderTriggerFrameworkHandler(
        List<GP_Folder__c> newList,
        List<GP_Folder__c> oldList,
        Map<Id, GP_Folder__c> newMap,
        Map<Id, GP_Folder__c> oldMap
    ) {
        super(
            (List<SObject>) newList,
            (List<SObject>) oldList,
            (Map<Id, SObject>) newMap,
            (Map<Id, SObject>) oldMap
        );
    }

    private List<GP_Folder__c> getNewGpFolders() {
        return (List<GP_Folder__c>) newList;
    }

    private Map<Id, GP_Folder__c> getOldGpFolderMap() {
        return (Map<Id, GP_Folder__c>) oldMap;
    }

    public override void afterInsert() {
        GpFolderTaskHandler.handleAfterInsert(getNewGpFolders());
    }

    public override void afterUpdate() {
        GpFolderTaskHandler.handleAfterUpdate(getNewGpFolders(), getOldGpFolderMap());
    }
}
