/*
    Author       : ROHIT SINGH BISHT
    Description  : Dispatches auto-registrations for records into webinars where Auto_Register__c = true
*/
public without sharing class WebinarAutoRegisterDispatcher {

    // keep below 100 callouts per transaction; use 80 as safety
    private static final Integer MAX_CALLOUTS_PER_JOB = 80;

    public static void dispatchForLeads(Set<Id> leadIds) {
        if (leadIds == null || leadIds.isEmpty()) return;


        List<Webinar__c> autoWebinars = [SELECT Id FROM Webinar__c WHERE Auto_Register__c = true AND (IsActive__c = true OR IsActive__c = null)];

        if (autoWebinars.isEmpty()) return;

        Set<Id> webinarIds = new Set<Id>();
        for (Webinar__c w : autoWebinars) webinarIds.add(w.Id);

        Integer webinarsCount = webinarIds.size();
        Integer maxLeadsPerJob = (webinarsCount == 0) ? 0 : (MAX_CALLOUTS_PER_JOB / webinarsCount);
        if (maxLeadsPerJob <= 0) maxLeadsPerJob = 1;

        List<Id> ids = new List<Id>(leadIds);

        for (Integer i = 0; i < ids.size(); i += maxLeadsPerJob) {
            Integer endIdx = Math.min(i + maxLeadsPerJob, ids.size());
            Set<Id> chunk = new Set<Id>();
            for (Integer j = i; j < endIdx; j++) chunk.add(ids[j]);

            System.enqueueJob(new LeadZoomRegistrationJob(chunk, webinarIds));
        }
    }
}