/*
    Author       : ROHIT SINGH BISHT
    Description  : 
*/
public without sharing class LeadTriggerHelperClass {

    private static final Id M1_OWNER_ID = '005C1000005HJRZIA4';

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


    public static void assignOwnerForM1(List<Lead__c> newList, Map<Id, Lead__c> oldMap, Boolean isInsert) {

        for (Lead__c newLead : newList) {

            // Apply only when Stage__c = 'M1'
            if (newLead.Stage__c == 'M1') {

                // INSERT CASE → always assign owner
                if (isInsert) {
                    newLead.OwnerId = M1_OWNER_ID;
                }

                // UPDATE CASE → only when stage changed to M1
                else {
                    Lead__c oldLead = oldMap.get(newLead.Id);

                    if (oldLead.Stage__c != 'M1') {
                        newLead.OwnerId = M1_OWNER_ID;
                    }
                }
            }
        }
    }

}