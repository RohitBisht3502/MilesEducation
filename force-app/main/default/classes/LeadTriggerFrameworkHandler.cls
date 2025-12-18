public without sharing class LeadTriggerFrameworkHandler extends BaseTriggerHandler {

    public LeadTriggerFrameworkHandler(List<Lead__c> newList,List<Lead__c> oldList,Map<Id, Lead__c> newMap,Map<Id, Lead__c> oldMap) {
        super(
            (List<SObject>)newList,
            (List<SObject>)oldList,
            (Map<Id, SObject>)newMap,
            (Map<Id, SObject>)oldMap
        );
    }

    private List<Lead__c> getNewLeads() {
        return (List<Lead__c>)newList;
    }

    private Map<Id, Lead__c> getOldLeadMap() {
        return (Map<Id, Lead__c>)oldMap;
    }

    private List<Lead__c> getOldLeads() {
        return (List<Lead__c>)oldList;
    }

    public override void beforeInsert() {
        LeadTriggerHelperClass.handleBeforeInsert(getNewLeads());
        // If you want M1 owner logic on insert:
        // LeadTriggerHelperClass.assignOwnerForM1(getNewLeads(), null, true);
    }

    public override void beforeUpdate() {
        List<Lead__c> newLeads = getNewLeads();
        Map<Id, Lead__c> oldMapLead = getOldLeadMap();

       // EnquiryStageService.validateStageTransitions(newLeads, oldMapLead); COMMENTED FOR DEMO ONLY
        LeadTriggerHelperClass.handleBeforeUpdate(newLeads, oldMapLead);
        // If you want M1 owner logic on update:
        // LeadTriggerHelperClass.assignOwnerForM1(newLeads, oldMapLead, false);
    }

    public override void afterInsert() {
        List<Lead__c> newLeads = getNewLeads();

        LeadTriggerHelperClass.handleAfterInsert(newLeads);
        LeadTriggerHelperClass.handleAfterInsert1(newLeads);

        // LeadTriggerHelperClass.registerLeadForUpcomingWebinars(getNewLeads());
        LeadTriggerHelperClass.afterInsertAutoRegisterWebinar(newLeads);
        LeadTriggerHandler.createLeadActivityLogs(newLeads, null, true);
    }

    public override void afterUpdate() {
        List<Lead__c> newLeads = getNewLeads();
        Map<Id, Lead__c> oldMapLead = getOldLeadMap();

        LeadTriggerHandler.createLeadActivityLogs(newLeads, oldMapLead, false);

        LeadTriggerHelperClass.afterUpdateMergeLead((List<Lead__c>)newList, (Map<Id, Lead__c>)oldMap);  

        // Auto-register only when Is_ReEnquiry__c flips to true 
        LeadTriggerHelperClass.afterUpdateAutoRegisterWebinar((Map<Id, Lead__c>)newMap, oldMapLead);
        // 3. Create activity logs for Merged Leads (AFTER merge logic completes)
        LeadTriggerHandler.createMergeLeadActivityLogs(newLeads, oldMapLead);
        // sync owner to ()
        LeadSyncOwnerChange.syncOnOwnerChange(oldMapLead, (Map<Id, Lead__c>)newMap);
    }

    public override void beforeDelete() {
        List<Lead__c> oldLeads = getOldLeads();
        LeadTriggerHelperClass.blockProtectedLeadDeletion(oldLeads);
    }
}