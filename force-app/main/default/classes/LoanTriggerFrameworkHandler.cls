public without sharing class LoanTriggerFrameworkHandler extends BaseTriggerHandler {
    public LoanTriggerFrameworkHandler(
        List<Loan__c> newList,
        List<Loan__c> oldList,
        Map<Id, Loan__c> newMap,
        Map<Id, Loan__c> oldMap
    ) {
        super(
            (List<SObject>) newList,
            (List<SObject>) oldList,
            (Map<Id, SObject>) newMap,
            (Map<Id, SObject>) oldMap
        );
    }

    private List<Loan__c> getNewLoans() {
        return (List<Loan__c>) newList;
    }

    private Map<Id, Loan__c> getOldLoanMap() {
        return (Map<Id, Loan__c>) oldMap;
    }

    public override void beforeInsert() {
      //  LoanUpdateTriggerHandler.validateBeforeInsert(getNewLoans());
    }

    public override void afterInsert() {
        // Loan vendor API is now called before insert from Quick Action.
    }

    public override void afterUpdate() {
        LoanActivityLogHandler.createLoanActivityLogs(getNewLoans(), getOldLoanMap());
    }
}
