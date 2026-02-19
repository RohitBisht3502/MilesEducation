public without sharing class CandidateTriggerFrameworkHandler extends BaseTriggerHandler {

    public CandidateTriggerFrameworkHandler(List<Lead> newList, List<Lead> oldList, Map<Id, Lead> newMap, Map<Id, Lead> oldMap) {
        super(
            (List<SObject>)newList,
            (List<SObject>)oldList,
            (Map<Id, SObject>)newMap,
            (Map<Id, SObject>)oldMap
        );
    }

    private List<Lead> getNewLeads() { return (List<Lead>)newList; }
    private Map<Id, Lead> getOldLeadMap() { return (Map<Id, Lead>)oldMap; }
    private List<Lead> getOldLeads() { return (List<Lead>)oldList; }

    public override void beforeInsert() {
        CandidateTriggerHelperClass.handleBeforeInsert(getNewLeads());
    }

    public override void beforeUpdate() {
        CandidateTriggerHelperClass.handleBeforeUpdate(getNewLeads(), getOldLeadMap());
        CandidateTriggerHelperClass.handleCandidateIdBeforeUpdate(getNewLeads(), getOldLeadMap());
    }

    public override void afterInsert() {
        CandidateTriggerHelperClass.handleAfterInsert(getNewLeads());
        CandidateTriggerHelperClass.handleCandidateIdAfterInsert(getNewLeads());
        // CandidateTriggerHelperClass.createBridgeCourseLeads(getNewLeads(), null);
    }

    public override void afterUpdate() {
        CandidateTriggerHelperClass.transferRecordsOnConversion(getNewLeads(), getOldLeadMap());
        CandidateTriggerHelperClass.syncGpUserToRelatedLeads(getNewLeads(), getOldLeadMap());
        // CandidateTriggerHelperClass.createBridgeCourseLeads(getNewLeads(), getOldLeadMap());
    }

    public override void beforeDelete() {
        // Add logic if needed
    }

    public override void afterDelete() {
        // Add logic if needed
    }

    public override void afterUndelete() {
        // Add logic if needed
    }
}