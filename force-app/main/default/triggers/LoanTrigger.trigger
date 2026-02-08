trigger LoanTrigger on Loan__c (before insert, after insert) {
    LoanTriggerFrameworkHandler handler = new LoanTriggerFrameworkHandler(
        (List<Loan__c>) Trigger.new,
        (Trigger.isUpdate || Trigger.isDelete || Trigger.isUndelete)
            ? (List<Loan__c>) Trigger.old
            : new List<Loan__c>(),
        (Trigger.isInsert || Trigger.isUpdate)
            ? (Map<Id, Loan__c>) Trigger.newMap
            : new Map<Id, Loan__c>(),
        (Trigger.isUpdate || Trigger.isDelete || Trigger.isUndelete)
            ? (Map<Id, Loan__c>) Trigger.oldMap
            : new Map<Id, Loan__c>()
    );

    if (Trigger.isBefore) {
        if (Trigger.isInsert) handler.beforeInsert();
    }

    if (Trigger.isAfter) {
        if (Trigger.isInsert) handler.afterInsert();
    }
}