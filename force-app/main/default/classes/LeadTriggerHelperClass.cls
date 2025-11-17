/*
    Author       : ROHIT SINGH BISHT
    Description  : 
*/
public without sharing class LeadTriggerHelperClass {

    public static void handleAfterInsert(List<Lead__c> newLeads) {
        if (newLeads == null || newLeads.isEmpty()) return;
        System.debug('Inside handleAfterInsert line 13 ');
        Set<Id> newLeadIds = new Set<Id>();
        for (Lead__c ld : newLeads) {
            if (ld.Id != null) newLeadIds.add(ld.Id);
        }
        if (!newLeadIds.isEmpty()) {
            LeadCityClassifier.enqueueLeadCityUpdate(newLeadIds);
        }
    }

}