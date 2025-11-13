/*
    Author       : ROHIT SINGH BISHT
    Description  : 
*/
public without sharing class LeadZoomRegistrationJob implements Queueable, Database.AllowsCallouts {

    private final Set<Id> leadIds;
    private final Id fixedWebinarId; 

    public LeadZoomRegistrationJob(Set<Id> leadIds) {
        this.leadIds       = (leadIds == null) ? new Set<Id>() : new Set<Id>(leadIds);
        this.fixedWebinarId = null;
    }

    public LeadZoomRegistrationJob(Id leadId, Id webinarId) {
        this.leadIds = new Set<Id>();
        if (leadId != null) this.leadIds.add(leadId);
        this.fixedWebinarId = webinarId;
    }

    public void execute(QueueableContext qc) {
        System.debug('🚀 [LeadZoomRegistrationJob] Started | Leads=' + leadIds + ' | fixedWebinarId=' + fixedWebinarId);

        List<Integration_Log__c> logs = new List<Integration_Log__c>();
        Map<Id, String> leadIdToMeetingDetails = new Map<Id, String>(); 

        // Guardrails
        if (leadIds == null || leadIds.isEmpty()) {
            logs.add(IntegrationLogUtil.buildLog( 'Zoom Webinar Registration Job', 'LeadIds=null/empty, fixedWebinarId=' + String.valueOf(fixedWebinarId), null, 'Empty leadIds', 'FAILED', 400 ));

            if (!logs.isEmpty()) IntegrationLogUtil.insertLogs(logs);
            return;
        }

        List<Lead> leads = [ SELECT Id, FirstName, LastName, Email, Phone, City__c, Interested_Webinar_Id__c FROM Lead WHERE Id IN :leadIds ];

        if (leads.isEmpty()) {
            logs.add(IntegrationLogUtil.buildLog( 'Zoom Webinar Registration Job', 'LeadIds=' + JSON.serialize(leadIds), 'No leads found', null, 'NO_OP', 204 ));

            if (!logs.isEmpty()) IntegrationLogUtil.insertLogs(logs);
            return;
        }

        // 2) Call Zoom (token -> register for each lead)
        try {
            System.debug('🔐 Generating Zoom Access Token…');
            String token = ZoomIntegrationService.generateZoomAccessToken(logs);
            System.debug('✅ Token generated.');

            for (Lead ld : leads) {
                // Keep (or tweak) your skip rule
                // if (String.isBlank(ld.City__c)) {
                //     logs.add(IntegrationLogUtil.buildLog( 'Zoom Webinar Registration Job', 'LeadId=' + ld.Id,'Skipped: City__c is blank', null, 'SKIPPED', 200 ));

                //     continue;
                // }

                try {
                    String zoomResponse = ZoomIntegrationService.registerLeadForWebinar(ld, token, logs);
                    leadIdToMeetingDetails.put(ld.Id, zoomResponse);

                    logs.add(IntegrationLogUtil.buildLog( 'Zoom Webinar Registration Job',  'LeadId=' + ld.Id + ', fixedWebinarId=' + String.valueOf(fixedWebinarId), 'Registered Successfully', null, 'SUCCESS', 200 ));

                } catch (Exception innerEx) {
                    logs.add(IntegrationLogUtil.buildLog( 'Zoom Webinar Registration Job', 'LeadId=' + ld.Id + ', fixedWebinarId=' + String.valueOf(fixedWebinarId), null, innerEx.getMessage(), 'FAILED', null  ));
                }
            }

        } catch (Exception ex) {
            logs.add(IntegrationLogUtil.buildLog( 'Zoom Integration Job Error', 'LeadIds=' + JSON.serialize(leadIds) + ', fixedWebinarId=' + String.valueOf(fixedWebinarId), null, ex.getMessage(), 'FAILED', null ));
        }

        if (!leadIdToMeetingDetails.isEmpty()) {
            Map<Id, Id> leadToWebinar = new Map<Id, Id>();

            if (fixedWebinarId != null) {
                for (Id lId : leadIdToMeetingDetails.keySet()) {
                    leadToWebinar.put(lId, fixedWebinarId);
                }
            } else {
                Set<String> wantedWebinarIds = new Set<String>();
                for (Lead ld : leads) {
                    if (String.isNotBlank(ld.Interested_Webinar_Id__c) && leadIdToMeetingDetails.containsKey(ld.Id)) {
                        wantedWebinarIds.add(ld.Interested_Webinar_Id__c.trim());
                    }
                }

                if (!wantedWebinarIds.isEmpty()) {
                    Map<String, Id> webinarByExternal = new Map<String, Id>();
                    for (Webinar__c w : [
                        SELECT Id, Webinar_Id__c
                        FROM Webinar__c
                        WHERE Webinar_Id__c IN :wantedWebinarIds
                    ]) {
                        if (String.isNotBlank(w.Webinar_Id__c)) {
                            webinarByExternal.put(w.Webinar_Id__c.trim(), w.Id);
                        }
                    }

                    for (Lead ld : leads) {
                        if (String.isNotBlank(ld.Interested_Webinar_Id__c) && leadIdToMeetingDetails.containsKey(ld.Id)) {
                            Id resolved = webinarByExternal.get(ld.Interested_Webinar_Id__c.trim());
                            if (resolved != null) {
                                leadToWebinar.put(ld.Id, resolved);
                            } else {
                                logs.add(IntegrationLogUtil.buildLog( 'Webinar Resolve', 'LeadId=' + ld.Id + ', Interested_Webinar_Id__c=' + ld.Interested_Webinar_Id__c, null, 'No Webinar__c found for the given Interested_Webinar_Id__c', 'SKIPPED', 200 ));
                            }
                        }
                    }
                }
            }

            if (!leadToWebinar.isEmpty()) {
                upsertMembers(leadIdToMeetingDetails, leadToWebinar, logs);
            } else {
                System.debug('ℹ️ No (Lead, Webinar) pairs resolved — skipping Webinar_Member__c upsert.');
            }
        }

        if (!logs.isEmpty()) {
            IntegrationLogUtil.insertLogs(logs);
        }
        System.debug('🏁 [LeadZoomRegistrationJob] Finished.');
    }

    public static void upsertMembers( Map<Id, String> leadIdToMeetingDetails, Map<Id, Id> leadToWebinar, List<Integration_Log__c> logs) {
        Set<Id> pairLeads   = new Set<Id>(leadToWebinar.keySet());
        Set<Id> pairWebinars = new Set<Id>();
        pairWebinars.addAll(leadToWebinar.values());

        Map<String, Webinar_Member__c> existingByPair = new Map<String, Webinar_Member__c>();
        for (Webinar_Member__c wm : [ SELECT Id, Lead__c, Webinar__c, Meeting_Details__c FROM Webinar_Member__c WHERE Lead__c IN :pairLeads AND Webinar__c IN :pairWebinars ]) {
            existingByPair.put(key(wm.Lead__c, wm.Webinar__c), wm);
        }

        List<Webinar_Member__c> toInsert = new List<Webinar_Member__c>();
        List<Webinar_Member__c> toUpdate = new List<Webinar_Member__c>();

        for (Id lId : leadToWebinar.keySet()) {
            Id wId = leadToWebinar.get(lId);
            String details = leadIdToMeetingDetails.get(lId);
            if (details == null) continue; 

            String k = key(lId, wId);
            Webinar_Member__c existing = existingByPair.get(k);

            if (existing == null) {
                toInsert.add(new Webinar_Member__c(
                    Lead__c = lId,
                    Webinar__c = wId,
                    Meeting_Details__c = details
                ));
            } else {
                existing.Meeting_Details__c = details;
                toUpdate.add(existing);
            }
        }

        try {
            if (!toInsert.isEmpty()) insert toInsert;
            if (!toUpdate.isEmpty()) update toUpdate;

            logs.add(IntegrationLogUtil.buildLog( 'Webinar Member Upsert', 'Pairs=' + leadToWebinar.size(), 'Inserted=' + toInsert.size() + ', Updated=' + toUpdate.size(),  null, 'SUCCESS', 200));

        } catch (Exception eWM) {
            logs.add(IntegrationLogUtil.buildLog( 'Webinar Member Upsert', 'Pairs=' + leadToWebinar.size(), null, eWM.getMessage(), 'FAILED', null ));
        }
    }

    private static String key(Id leadId, Id webinarId) {
        return String.valueOf(leadId) + '|' + String.valueOf(webinarId);
    }
}