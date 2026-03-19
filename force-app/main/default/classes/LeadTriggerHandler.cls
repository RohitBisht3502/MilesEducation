public without sharing class LeadTriggerHandler {

    public static void blockProtectedLeadDeletion(List<Lead__c> oldLeads) {
        for (Lead__c l : oldLeads) {
            if (l.Do_Not_Delete__c == true) {
                l.addError('âŒ This custom Lead record is protected and cannot be deleted.');
            }
        }
    }
}