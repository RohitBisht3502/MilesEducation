trigger GpFolderTrigger on GP_Folder__c (after insert, after update) {
    GpFolderTriggerFrameworkHandler handler = new GpFolderTriggerFrameworkHandler(
        (List<GP_Folder__c>) Trigger.new,
        Trigger.isUpdate ? (List<GP_Folder__c>) Trigger.old : new List<GP_Folder__c>(),
        (Map<Id, GP_Folder__c>) Trigger.newMap,
        Trigger.isUpdate ? (Map<Id, GP_Folder__c>) Trigger.oldMap : new Map<Id, GP_Folder__c>()
    );

    if (Trigger.isAfter) {
        if (Trigger.isInsert) {
            handler.afterInsert();
        }

        if (Trigger.isUpdate) {
            handler.afterUpdate();
        }
    }
}