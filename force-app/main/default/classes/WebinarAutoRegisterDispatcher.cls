/*
    Author       : ROHIT SINGH BISHT
    Description  : Dispatches auto-registrations for records into webinars where Auto_Register__c = true
*/
public without sharing class WebinarAutoRegisterDispatcher {

    // keep below 100 callouts per transaction; use 80 as safety
    private static final Integer MAX_CALLOUTS_PER_JOB = 80;

    public static void dispatchForLeads(Set<Id> leadIds) {
        if (leadIds == null || leadIds.isEmpty()) return;

        //List<Webinar__c> autoWebinars = [SELECT Id, Webinar_Id__c FROM Webinar__c WHERE Auto_Register__c = true AND (IsActive__c = true OR IsActive__c = null)];
        List<Webinar__c> autoWebinars = [
            SELECT Id, Webinar_Id__c FROM Webinar__c WHERE Auto_Register__c = true AND (IsActive__c = true OR IsActive__c = null) AND Status__c = 'Created' AND Start_Date_Time__c >= :System.now() ];
        if (autoWebinars.isEmpty()) return;

        Set<Id> webinarIds = new Set<Id>();
        Map<String, Id> extWebinarIdToWebinarId = new Map<String, Id>();

        for (Webinar__c w : autoWebinars) {
            webinarIds.add(w.Id);
            if (w.Webinar_Id__c != null) {
                extWebinarIdToWebinarId.put(String.valueOf(w.Webinar_Id__c).trim(), w.Id);
            }
        }

        Integer webinarsCount = webinarIds.size();
        Integer maxLeadsPerJob = (webinarsCount == 0) ? 0 : (MAX_CALLOUTS_PER_JOB / webinarsCount);
        if (maxLeadsPerJob <= 0) maxLeadsPerJob = 1;

        List<Lead__c> leads = [SELECT Id, Register_For_Webinar__c, Interested_Webinar_Id__c FROM Lead__c WHERE Id IN :leadIds];

        List<Id> normalLeadIds = new List<Id>();
        Map<Id, List<Id>> skipWebinarToLeadIds = new Map<Id, List<Id>>();

        for (Lead__c l : leads) {
            Boolean optedOut = (l.Register_For_Webinar__c == false);
            String interested = String.isBlank(l.Interested_Webinar_Id__c) ? null : l.Interested_Webinar_Id__c.trim();

            if (optedOut && interested != null && extWebinarIdToWebinarId.containsKey(interested)) {
                Id skipWebinarId = extWebinarIdToWebinarId.get(interested);
                if (!skipWebinarToLeadIds.containsKey(skipWebinarId)) {
                    skipWebinarToLeadIds.put(skipWebinarId, new List<Id>());
                }
                skipWebinarToLeadIds.get(skipWebinarId).add(l.Id);
            } else {
                normalLeadIds.add(l.Id);
            }
        }

        for (Integer i = 0; i < normalLeadIds.size(); i += maxLeadsPerJob) {
            Integer endIdx = Math.min(i + maxLeadsPerJob, normalLeadIds.size());
            Set<Id> chunk = new Set<Id>();
            for (Integer j = i; j < endIdx; j++) chunk.add(normalLeadIds[j]);
            System.enqueueJob(new LeadZoomRegistrationJob(chunk, webinarIds));
        }

        for (Id skipW : skipWebinarToLeadIds.keySet()) {
            Set<Id> filteredWebinarIds = new Set<Id>(webinarIds);
            filteredWebinarIds.remove(skipW);

            Integer filteredCount = filteredWebinarIds.size();
            Integer maxLeadsPerJobFiltered = (filteredCount == 0) ? 0 : (MAX_CALLOUTS_PER_JOB / filteredCount);
            if (maxLeadsPerJobFiltered <= 0) maxLeadsPerJobFiltered = 1;

            List<Id> ids = skipWebinarToLeadIds.get(skipW);

            for (Integer i = 0; i < ids.size(); i += maxLeadsPerJobFiltered) {
                Integer endIdx = Math.min(i + maxLeadsPerJobFiltered, ids.size());
                Set<Id> chunk = new Set<Id>();
                for (Integer j = i; j < endIdx; j++) chunk.add(ids[j]);
                System.enqueueJob(new LeadZoomRegistrationJob(chunk, filteredWebinarIds));
            }
        }
    }

}