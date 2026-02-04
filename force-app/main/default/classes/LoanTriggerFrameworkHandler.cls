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

    public override void beforeInsert() {
        LoanUpdateTriggerHandler.validateBeforeInsert(getNewLoans());
    }

    public override void afterInsert() {
        List<Id> loanIds = new List<Id>();
        for (Loan__c l : getNewLoans()) {
            loanIds.add(l.Id);
        }
        if (!loanIds.isEmpty()) {
            LoanUpdateTriggerHandler.loanUpdate(loanIds);
        }
    }
}
