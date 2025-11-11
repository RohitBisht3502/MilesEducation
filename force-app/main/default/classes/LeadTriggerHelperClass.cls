public with sharing class LeadTriggerHelperClass {

    public static void handleBeforeInsert(List<Lead> newLeads) {
        // RoundRobinService.assignForLeads(newLeads);
    }
    
    public static void handleBeforeUpdate(List<Lead> newLeads, Map<Id, Lead> oldMap) {
        TriggerRoundRobinService.handleBeforeUpdate(newLeads, oldMap);
    }

    public static void handleAfterInsert(List<Lead> newLeads) {
        if (newLeads == null || newLeads.isEmpty()) return;
        System.debug('Inside handleAfterInsert line 13 ');
        Set<Id> newLeadIds = new Set<Id>();
        for (Lead ld : newLeads) {
            if (ld.Id != null) newLeadIds.add(ld.Id);
        }
        if (!newLeadIds.isEmpty()) {
            LeadCityClassifier.enqueueLeadCityUpdate(newLeadIds);
        }

        Set<Id> leadsForZoom = new Set<Id>();
        for (Lead ld : newLeads) {
            System.debug('Inside ld line 13 '+ld);
            Boolean emailOk   = String.isNotBlank(ld.Email);
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

    // public static void handleAfterUpdate(List<Lead> newLeads, Map<Id, Lead> oldMap) {
    //     if (newLeads == null || newLeads.isEmpty() || oldMap == null) return;

    //     Set<Id> leadsForZoom = new Set<Id>();

    //     for (Lead ld : newLeads) {
    //         Lead oldLd = oldMap.get(ld.Id);

    //         Boolean nowChecked = (ld.Register_Zoom_Integration__c == true);
    //         Boolean wasChecked = (oldLd != null && oldLd.Register_Zoom_Integration__c == true);

    //       //  if (nowChecked && !wasChecked && String.isNotBlank(ld.Phone) && String.isNotBlank(ld.FirstName)) {
    //             leadsForZoom.add(ld.Id);
    //        // }
    //     }

    //     if (!leadsForZoom.isEmpty()) {
    //         System.enqueueJob(new LeadZoomRegistrationJob(leadsForZoom));
    //     }
    // }
}