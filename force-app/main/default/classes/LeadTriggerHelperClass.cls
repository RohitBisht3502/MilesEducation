/*
    Author       : ROHIT SINGH BISHT
    Description  : 
*/
public without sharing class LeadTriggerHelperClass {
    
    public static void handleBeforeInsert(List<Lead__c> newLeads) {
        TriggerRoundRobinService.handleBeforeInsert(newLeads);
    }
    
    public static void handleBeforeUpdate(List<Lead__c> newLeads, Map<Id, Lead__c> oldMap) {
        TriggerRoundRobinService.handleBeforeUpdate(newLeads, oldMap);
    }
    
    public static void handleAfterInsert1(List<Lead__c> newLeads) {
        if (newLeads == null || newLeads.isEmpty()) return;
        System.debug('Inside handleAfterInsert line 13 ');
        Set<Id> newLeadIds = new Set<Id>();
        for (Lead__c ld : newLeads) {
            if (ld.Id != null) newLeadIds.add(ld.Id);
        }
        if (!newLeadIds.isEmpty()) {
          //  LeadCityClassifier.enqueueLeadCityUpdate(newLeadIds);
        }

        Set<Id> leadsForZoom = new Set<Id>();
        for (Lead__c ld : newLeads) {
            System.debug('Inside ld line 13 '+ld);
            Boolean emailOk   = String.isNotBlank(ld.Email__c);
            Boolean wantsWeb  = (ld.Register_For_Webinar__c == true);
            Boolean noWebinar = String.isNotBlank(ld.Interested_Webinar_Id__c);
            System.debug('>>>> '+emailOk);
            System.debug('>>>> '+wantsWeb);
            System.debug('>>>> '+noWebinar);
           if (emailOk && wantsWeb && noWebinar) {
                leadsForZoom.add(ld.Id);
            }
        }
        if (!leadsForZoom.isEmpty()) {
            System.debug('Inside handleAfterInsert queue ');
            System.enqueueJob(new LeadZoomRegistrationJob(leadsForZoom));
        }
    }

    
    
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