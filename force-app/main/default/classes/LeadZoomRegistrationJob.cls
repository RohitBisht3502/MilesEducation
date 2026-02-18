/*
    Author       : ROHIT SINGH BISHT
    Description  :
*/
public without sharing class LeadZoomRegistrationJob implements Queueable, Database.AllowsCallouts {

    private final Set<Id> leadIds;              // Can contain Lead__c + Enquiry__c ids
    private final Id fixedWebinarId;            // Single webinar path
    private final Set<Id> autoWebinarIds;       // ✅: multi-webinar path (Auto Register)

    public LeadZoomRegistrationJob(Set<Id> leadIds) {
        this.leadIds         = (leadIds == null) ? new Set<Id>() : new Set<Id>(leadIds);
        this.fixedWebinarId  = null;
        this.autoWebinarIds  = null;
    }

    public LeadZoomRegistrationJob(Id recordId, Id webinarId) {
        this.leadIds = new Set<Id>();
        if (recordId != null) this.leadIds.add(recordId);
        this.fixedWebinarId = webinarId;
        this.autoWebinarIds = null;
    }

    // ✅ NEW ctor: register these records into these webinars
    public LeadZoomRegistrationJob(Set<Id> recordIds, Set<Id> webinarIds) {
        this.leadIds        = (recordIds == null) ? new Set<Id>() : new Set<Id>(recordIds);
        this.fixedWebinarId = null;
        this.autoWebinarIds = (webinarIds == null) ? new Set<Id>() : new Set<Id>(webinarIds);
    }

    public void execute(QueueableContext qc) {
        System.debug('🚀 [LeadZoomRegistrationJob] Started | recordIds=' + leadIds + ' | fixedWebinarId=' + fixedWebinarId + ' | autoWebinarIds=' + autoWebinarIds);

        List<Integration_Log__c> logs = new List<Integration_Log__c>();

        if (leadIds == null || leadIds.isEmpty()) {
            logs.add(IntegrationLogUtil.buildLog(
                'Zoom Webinar Registration Job',
                'recordIds=null/empty, fixedWebinarId=' + String.valueOf(fixedWebinarId),
                null,
                'Empty recordIds',
                'FAILED',
                400
            ));
            if (!logs.isEmpty()) IntegrationLogUtil.insertLogs(logs);
            return;
        }

        // Split ids by type
        Set<Id> leadOnlyIds    = new Set<Id>();
        Set<Id> enquiryOnlyIds = new Set<Id>();

        for (Id rid : leadIds) {
            if (rid == null) continue;
            Schema.SObjectType t = rid.getSObjectType();
            if (t == Lead__c.SObjectType) leadOnlyIds.add(rid);
            else if (t == Enquiry__c.SObjectType) enquiryOnlyIds.add(rid);
        }

        List<Lead__c> leads = leadOnlyIds.isEmpty()
            ? new List<Lead__c>()
            : [
                SELECT Id, Name, Email__c, Phone__c, City__c, Stage__c, OwnerId, Interested_Webinar_Id__c, Candidate__c FROM Lead__c WHERE Id IN :leadOnlyIds ];

        List<Enquiry__c> enquiries = enquiryOnlyIds.isEmpty()
            ? new List<Enquiry__c>()
            : [
                SELECT Id, Name, Email__c, Phone_Number__c, City__c, Stage__c, OwnerId, Interested_Webinar_Id__c FROM Enquiry__c WHERE Id IN :enquiryOnlyIds ];

        if (leads.isEmpty() && enquiries.isEmpty()) {
            logs.add(IntegrationLogUtil.buildLog(
                'Zoom Webinar Registration Job',
                'RecordIds=' + JSON.serialize(leadIds),
                'No records found',
                null,
                'NO_OP',
                204
            ));
            if (!logs.isEmpty()) IntegrationLogUtil.insertLogs(logs);
            return;
        }

        // ✅ Build record -> Webinar__c pairs
        Map<Id, Set<Id>> recordToWebinars = new Map<Id, Set<Id>>();

        // A) Multi-webinar (Auto Register) path
        if (autoWebinarIds != null && !autoWebinarIds.isEmpty()) {
            for (Id rid : leadIds) {
                recordToWebinars.put(rid, new Set<Id>(autoWebinarIds));
            }
        }
        // B) Single webinar path
        else if (fixedWebinarId != null) {
            for (Id rid : leadIds) {
                recordToWebinars.put(rid, new Set<Id>{ fixedWebinarId });
            }
        }

        Map<Id, String> recordIdToZoomWebinarExternal = new Map<Id, String>();

        // Call Zoom once (token)
        Map<String, String> pairKeyToMeetingDetails = new Map<String, String>(); // key(record|webinarId) -> zoom response
        try {
            String token = ZoomIntegrationService.generateZoomAccessToken(logs);

            // ✅ If we already have Webinar__c Ids (auto or fixed), we need Webinar__c.Webinar_Id__c to call Zoom.
            Map<Id, Webinar__c> webinarMap = new Map<Id, Webinar__c>();
            Set<Id> neededWebinarIds = new Set<Id>();
            for (Set<Id> ws : recordToWebinars.values()) neededWebinarIds.addAll(ws);

            if (!neededWebinarIds.isEmpty()) {
                for (Webinar__c w : [SELECT Id, Webinar_Id__c FROM Webinar__c WHERE Id IN :neededWebinarIds ]) {
                    webinarMap.put(w.Id, w);
                }
            }

            // ===== Leads =====
            for (Lead__c ld : leads) {

                // If recordToWebinars has entries => auto/fixed path
                if (recordToWebinars.containsKey(ld.Id)) {
                    for (Id wId : recordToWebinars.get(ld.Id)) {
                        Webinar__c w = webinarMap.get(wId);
                        String zoomWebinarId = (w != null && String.isNotBlank(w.Webinar_Id__c)) ? w.Webinar_Id__c.trim() : null;

                        if (String.isBlank(zoomWebinarId)) {
                            logs.add(IntegrationLogUtil.buildLog('Webinar Resolve', 'LeadId=' + ld.Id + ', WebinarId=' + wId, null, 'Webinar__c.Webinar_Id__c is blank', 'SKIPPED', 200));
                            continue;
                        }

                        String resp = ZoomIntegrationService.registerLeadForWebinar(ld, zoomWebinarId, token, logs);
                        pairKeyToMeetingDetails.put(key(ld.Id, wId), resp);
                    }
                }
                // Else: fallback to Interested_Webinar_Id__c (existing behavior)
                else {
                    if (String.isBlank(ld.Interested_Webinar_Id__c)) continue;
                    recordIdToZoomWebinarExternal.put(ld.Id, ld.Interested_Webinar_Id__c.trim());
                }
            }

            // ===== Enquiries =====
            for (Enquiry__c eq : enquiries) {

                if (recordToWebinars.containsKey(eq.Id)) {
                    for (Id wId : recordToWebinars.get(eq.Id)) {
                        Webinar__c w = webinarMap.get(wId);
                        String zoomWebinarId = (w != null && String.isNotBlank(w.Webinar_Id__c)) ? w.Webinar_Id__c.trim() : null;

                        if (String.isBlank(zoomWebinarId)) {
                            logs.add(IntegrationLogUtil.buildLog('Webinar Resolve', 'EnquiryId=' + eq.Id + ', WebinarId=' + wId, null, 'Webinar__c.Webinar_Id__c is blank', 'SKIPPED', 200));
                            continue;
                        }

                        String resp = ZoomIntegrationService.registerEnquiryForWebinar(eq, zoomWebinarId, token, logs);
                        pairKeyToMeetingDetails.put(key(eq.Id, wId), resp);
                    }
                } else {
                    if (String.isBlank(eq.Interested_Webinar_Id__c)) continue;
                    recordIdToZoomWebinarExternal.put(eq.Id, eq.Interested_Webinar_Id__c.trim());
                }
            }

            // ===== Existing behavior: resolve Interested_Webinar_Id__c -> Webinar__c.Id, then call zoom once per record =====
            if (!recordIdToZoomWebinarExternal.isEmpty()) {
                Set<String> externalIds = new Set<String>();
                externalIds.addAll(recordIdToZoomWebinarExternal.values());

                Map<String, Webinar__c> webinarByExternal = new Map<String, Webinar__c>();
                for (Webinar__c w : [SELECT Id, Webinar_Id__c FROM Webinar__c WHERE Webinar_Id__c IN :externalIds]) {
                    if (String.isNotBlank(w.Webinar_Id__c)) webinarByExternal.put(w.Webinar_Id__c.trim(), w);
                }

                // Lead
                for (Lead__c ld : leads) {
                    String ext = recordIdToZoomWebinarExternal.get(ld.Id);
                    if (String.isBlank(ext)) continue;

                    Webinar__c w = webinarByExternal.get(ext);
                    if (w == null) continue;

                    String resp = ZoomIntegrationService.registerLeadForWebinar(ld, ext, token, logs);
                    pairKeyToMeetingDetails.put(key(ld.Id, w.Id), resp);
                }

                // Enquiry
                for (Enquiry__c eq : enquiries) {
                    String ext = recordIdToZoomWebinarExternal.get(eq.Id);
                    if (String.isBlank(ext)) continue;

                    Webinar__c w = webinarByExternal.get(ext);
                    if (w == null) continue;

                    String resp = ZoomIntegrationService.registerEnquiryForWebinar(eq, ext, token, logs);
                    pairKeyToMeetingDetails.put(key(eq.Id, w.Id), resp);
                }
            }

        } catch (Exception ex) {
            logs.add(IntegrationLogUtil.buildLog(
                'Zoom Integration Job Error',
                'RecordIds=' + JSON.serialize(leadIds),
                null,
                ex.getMessage(),
                'FAILED',
                null
            ));
        }

        // ✅ Upsert Webinar_Member__c per pair
        if (!pairKeyToMeetingDetails.isEmpty()) {
            upsertMembersByPairs(pairKeyToMeetingDetails, logs);
        }

        if (!logs.isEmpty()) IntegrationLogUtil.insertLogs(logs);
        System.debug('🏁 [LeadZoomRegistrationJob] Finished.');
    }

    // ✅ NEW helper: upsert using (recordId|webinarId) keys
    private static void upsertMembersByPairs(Map<String, String> pairKeyToMeetingDetails, List<Integration_Log__c> logs) {

        Set<Id> recordIds  = new Set<Id>();
        Set<Id> webinarIds = new Set<Id>();

        for (String k : pairKeyToMeetingDetails.keySet()) {
            List<String> parts = k.split('\\|');
            if (parts.size() != 2) continue;
            recordIds.add((Id)parts[0]);
            webinarIds.add((Id)parts[1]);
        }

        // Split record ids
        Set<Id> leadOnlyIds   = new Set<Id>();
        Set<Id> enquiryOnlyIds = new Set<Id>();
        for (Id rid : recordIds) {
            if (rid.getSObjectType() == Lead__c.SObjectType) leadOnlyIds.add(rid);
            else if (rid.getSObjectType() == Enquiry__c.SObjectType) enquiryOnlyIds.add(rid);
        }

        // Existing members
        Map<String, Webinar_Member__c> existingByPair = new Map<String, Webinar_Member__c>();
        for (Webinar_Member__c wm : [
            SELECT Id, Lead__c, Enquiry__c, Webinar__c, Meeting_Details__c,Registrant_Id__c,Lead_Owner_at_Registration__c, Lead_Stage_at_Registration__c
            FROM Webinar_Member__c WHERE Webinar__c IN :webinarIds AND ( (Lead__c IN :leadOnlyIds) OR (Enquiry__c IN :enquiryOnlyIds)) ]) {
            Id rid = (wm.Lead__c != null) ? wm.Lead__c : wm.Enquiry__c;
            existingByPair.put(key(rid, wm.Webinar__c), wm);
        }

        Map<Id, Lead__c> leadMap = leadOnlyIds.isEmpty()
            ? new Map<Id, Lead__c>()
            : new Map<Id, Lead__c>([SELECT Id, Stage__c, OwnerId, Candidate__c FROM Lead__c WHERE Id IN :leadOnlyIds ]);

        Map<Id, Enquiry__c> enquiryMap = enquiryOnlyIds.isEmpty()
            ? new Map<Id, Enquiry__c>()
            : new Map<Id, Enquiry__c>([SELECT Id, Stage__c, OwnerId FROM Enquiry__c WHERE Id IN :enquiryOnlyIds]);

        List<Webinar_Member__c> toInsert = new List<Webinar_Member__c>();
        List<Webinar_Member__c> toUpdate = new List<Webinar_Member__c>();

        for (String k : pairKeyToMeetingDetails.keySet()) {
            List<String> parts = k.split('\\|');
            if (parts.size() != 2) continue;

            Id rid = (Id)parts[0];
            Id wid = (Id)parts[1];

            String details = pairKeyToMeetingDetails.get(k);
            if (String.isBlank(details)) continue;

            Boolean isLead = (rid.getSObjectType() == Lead__c.SObjectType);
            Id ownerId;
            String stageVal;
            Id candidateId;

            if (isLead) {
                Lead__c ld = leadMap.get(rid);
                if (ld != null) { ownerId = ld.OwnerId; stageVal = ld.Stage__c; candidateId = ld.Candidate__c; }
            } else {
                Enquiry__c eq = enquiryMap.get(rid);
                if (eq != null) { ownerId = eq.OwnerId; stageVal = eq.Stage__c; }
            }

            Webinar_Member__c existing = existingByPair.get(k);

            if (existing == null) {
                Webinar_Member__c wm = new Webinar_Member__c();
                wm.Webinar__c = wid;
                wm.Meeting_Details__c = details;
                wm.Registrant_Id__c = extractRegistrantId(details);

                if (isLead) wm.Lead__c = rid;
                else wm.Enquiry__c = rid;
                if (candidateId != null) wm.Candidate__c = candidateId;

                wm.Lead_Owner_at_Registration__c = UserInfo.getUserId();
                wm.Lead_Stage_at_Registration__c = stageVal;

                toInsert.add(wm);
            } else {
                existing.Meeting_Details__c = details;
                existing.Registrant_Id__c = extractRegistrantId(details);

                if (isLead) { existing.Lead__c = rid; existing.Enquiry__c = null; }
                else { existing.Enquiry__c = rid; existing.Lead__c = null; }
                existing.Candidate__c = candidateId;

                existing.Lead_Owner_at_Registration__c = UserInfo.getUserId();
                existing.Lead_Stage_at_Registration__c = stageVal;

                toUpdate.add(existing);
            }
        }

        try {
            if (!toInsert.isEmpty()) insert toInsert;
            if (!toUpdate.isEmpty()) update toUpdate;

            logs.add(IntegrationLogUtil.buildLog(
                'Webinar Member Upsert',
                'Pairs=' + pairKeyToMeetingDetails.size(),
                'Inserted=' + toInsert.size() + ', Updated=' + toUpdate.size(),
                null,
                'SUCCESS',
                200
            ));
        } catch (Exception e) {
            logs.add(IntegrationLogUtil.buildLog(
                'Webinar Member Upsert',
                'Pairs=' + pairKeyToMeetingDetails.size(),
                null,
                e.getMessage(),
                'FAILED',
                null
            ));
        }
    }

    private static String key(Id recordId, Id webinarId) {
        return String.valueOf(recordId) + '|' + String.valueOf(webinarId);
    }

    private static String extractRegistrantId(String details) {
    if (String.isBlank(details)) return null;
    try {
        Object raw = JSON.deserializeUntyped(details);
        if (raw instanceof Map<String, Object>) {
            Object v = ((Map<String, Object>)raw).get('registrant_id');
            return (v == null) ? null : String.valueOf(v);
        }
    } catch (Exception e) {
        System.debug('⚠️ extractRegistrantId failed. details=' + details + ' | err=' + e.getMessage());
    }
    return null;
}

}