trigger CertificationTrigger on Certification__c (before insert, after insert, before update, after update) {

    CertificationTriggerFrameworkHandler handler = new CertificationTriggerFrameworkHandler(
        (List<Certification__c>)Trigger.new,
        Trigger.isUpdate ? (List<Certification__c>)Trigger.old : new List<Certification__c>(),
        (Map<Id, Certification__c>)Trigger.newMap,
        Trigger.isUpdate ? (Map<Id, Certification__c>)Trigger.oldMap : new Map<Id, Certification__c>()
    );

    if (Trigger.isBefore) {
        if (Trigger.isInsert) handler.beforeInsert();
        if (Trigger.isUpdate) handler.beforeUpdate();
    }

    if (Trigger.isAfter) {
        if (Trigger.isInsert) {
            handler.afterInsert();
        }

        if (Trigger.isUpdate) {
            handler.afterUpdate();
        }
    }
}