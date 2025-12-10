/*
    Author       : ROHIT SINGH BISHT
    Description  : 
*/
public without sharing class GoogleMeetService {
    private static final String NC = 'GMeet_Scheduler'; // <-- your Named Credential
    private static final String ORG_MEETING_EMAIL = 'meetings@mileseducation.com';

    public class CreateResult {
        @AuraEnabled public String eventId;          // Google event id
        @AuraEnabled public String meetUrl;
        @AuraEnabled public String htmlLink;
        @AuraEnabled public String rawJson;
        @AuraEnabled public Id     salesforceEventId; // SF Event Id
    }

    // ====== PUBLIC: existing API (kept for backward compatibility) ======
    @AuraEnabled(cacheable=false)
    public static CreateResult createMeetEvent(
        String subject,
        String description,
        Datetime startUtc,
        Datetime endUtc,
        String timeZoneId,            // e.g. "Asia/Kolkata"
        List<String> attendeeEmails   // e.g. {'a@gmail.com','b@gmail.com'}
    ) {
        return createMeetEventInternal(
            'primary',
            subject,
            description,
            startUtc,
            endUtc,
            timeZoneId,
            attendeeEmails
        );
    }

    // ====== NEW: create Google Meet + Salesforce Event record ======
    @AuraEnabled(cacheable=false)
    public static CreateResult createMeetingWithEvent(
        Id recordId,                 // Lead__c id (used as WhatId)
        String subject,
        String description,
        Datetime startUtc,
        Datetime endUtc,
        String timeZoneId,
        List<String> attendeeEmails,
        String meetingType,          // Event.Meeting_type__c
        String offlineType,          // Event.Type_of_Offline_gmeet__c (only for Offline)
        Integer durationMinutes
    ) {
        if (String.isBlank(timeZoneId)) timeZoneId = 'Asia/Kolkata';
        if (attendeeEmails == null) attendeeEmails = new List<String>();

        // ensure org mail is always present
        Boolean hasOrg = false;
        for (String e : attendeeEmails) {
            if (!String.isBlank(e) && e.trim().toLowerCase() == ORG_MEETING_EMAIL.toLowerCase()) {
                hasOrg = true;
                break;
            }
        }
        if (!hasOrg) {
            attendeeEmails.add(ORG_MEETING_EMAIL);
        }

        // Create Google Calendar event in org calendar (meetings@mileseducation.com)
        CreateResult result = createMeetEventInternal(
            ORG_MEETING_EMAIL,
            subject,
            description,
            startUtc,
            endUtc,
            timeZoneId,
            attendeeEmails
        );

        // Create Salesforce Event record and store meeting details
        Event ev = new Event();
        ev.Subject       = subject;
        ev.Description   = description;
        ev.StartDateTime = startUtc;
        ev.EndDateTime   = endUtc;
        ev.OwnerId       = UserInfo.getUserId();
        if (!String.isBlank(result.meetUrl)) {
            ev.Location = result.meetUrl;
        }

        // relate Event to the custom Lead__c via WhatId
        if (recordId != null) {
            ev.WhatId = recordId;
        }

        Schema.DescribeSObjectResult evDescribe = Event.SObjectType.getDescribe();
        Map<String, Schema.SObjectField> fMap = evDescribe.fields.getMap();

        if (!String.isBlank(meetingType) && fMap.containsKey('Meeting_type__c')) {
            ev.put('Meeting_type__c', meetingType);
        }
        if (!String.isBlank(offlineType)
            && !String.isBlank(meetingType)
            && meetingType == 'Offline'
            && fMap.containsKey('Type_of_Offline_gmeet__c')) {
            ev.put('Type_of_Offline_gmeet__c', offlineType);
        }
        if (durationMinutes != null && fMap.containsKey('Duration__c')) {
            ev.put('Duration__c', durationMinutes);
        }

        insert ev;
        result.salesforceEventId = ev.Id;

        return result;
    }

    // ====== PRIVATE: shared Google callout logic ======
    private static CreateResult createMeetEventInternal(
        String calendarId,
        String subject,
        String description,
        Datetime startUtc,
        Datetime endUtc,
        String timeZoneId,
        List<String> attendeeEmails
    ) {
        if (String.isBlank(timeZoneId)) timeZoneId = 'Asia/Kolkata';
        if (String.isBlank(calendarId)) calendarId = 'primary';

        // Build payload
        Map<String, Object> body = new Map<String, Object>();
        body.put('summary', subject);
        if (!String.isBlank(description)) body.put('description', description);

        body.put('start', new Map<String,Object>{
            'dateTime' => startUtc.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\''),
            'timeZone' => timeZoneId
        });
        body.put('end', new Map<String,Object>{
            'dateTime' => endUtc.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\''),
            'timeZone' => timeZoneId
        });

        if (attendeeEmails != null && !attendeeEmails.isEmpty()) {
            List<Object> attendees = new List<Object>();
            for (String e : attendeeEmails) {
                if (String.isNotBlank(e)) {
                    attendees.add(new Map<String,Object>{ 'email' => e.trim() });
                }
            }
            if (!attendees.isEmpty()) body.put('attendees', attendees);
        }

        // Ask Google to create a Meet link
        body.put('conferenceData', new Map<String,Object>{
            'createRequest' => new Map<String,Object>{
                'requestId' => String.valueOf(Crypto.getRandomLong()),
                'conferenceSolutionKey' => new Map<String,Object>{ 'type' => 'hangoutsMeet' }
            }
        });

        // Call Google Calendar API using specific calendarId
        String encodedCalId = EncodingUtil.urlEncode(calendarId, 'UTF-8');
        HttpRequest req = new HttpRequest();
        req.setEndpoint(
            'callout:' + NC +
            '/calendar/v3/calendars/' + encodedCalId +
            '/events?conferenceDataVersion=1&sendUpdates=all'
        );
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(body));

        Http http = new Http();
        HTTPResponse res = http.send(req);

        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            throw new AuraHandledException('Google error: ' + res.getStatus() + ' — ' + res.getBody());
        }

        Map<String, Object> m = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        String meetUrl;

        // Prefer conferenceData.entryPoints[ type='video' ].uri
        if (m.containsKey('conferenceData')) {
            Map<String,Object> cd = (Map<String,Object>) m.get('conferenceData');
            if (cd != null && cd.containsKey('entryPoints')) {
                List<Object> eps = (List<Object>) cd.get('entryPoints');
                for (Object o : eps) {
                    Map<String,Object> ep = (Map<String,Object>) o;
                    if (ep.get('entryPointType') == 'video' && ep.containsKey('uri')) {
                        meetUrl = (String) ep.get('uri');
                        break;
                    }
                }
            }
        }
        // Fallback for older responses
        if (String.isBlank(meetUrl) && m.containsKey('hangoutLink')) {
            meetUrl = (String) m.get('hangoutLink');
        }

        CreateResult out = new CreateResult();
        out.eventId  = (String) m.get('id');
        out.htmlLink = (String) m.get('htmlLink');
        out.meetUrl  = meetUrl;
        out.rawJson  = res.getBody();
        return out;
    }

    // Convenience: create a Meet for an Opportunity and (if field exists) store link in Meeting_Link__c
    @AuraEnabled
    public static CreateResult createMeetForOpportunity(Id opportunityId, Datetime startUtc, Datetime endUtc, String attendeesCsv) {
        Opportunity opp = [SELECT Id, Name FROM Opportunity WHERE Id = :opportunityId LIMIT 1];
        List<String> emails = new List<String>();
        if (!String.isBlank(attendeesCsv)) {
            for (String s : attendeesCsv.split('[,;\\s]+')) if (String.isNotBlank(s)) emails.add(s.trim());
        }
        CreateResult r = createMeetEvent(
            'Meeting: ' + opp.Name,
            'Auto-created from Salesforce',
            startUtc,
            endUtc,
            'Asia/Kolkata',
            emails
        );

        // Save to Meeting_Link__c if that custom field exists
        Schema.DescribeSObjectResult d = Opportunity.SObjectType.getDescribe();
        if (d.fields.getMap().containsKey('Meeting_Link__c')) {
            opp.put('Meeting_Link__c', r.meetUrl);
            update opp;
        }
        return r;
    }

    @AuraEnabled(cacheable=true)
    public static String getCurrentUserEmail() {
        try {
            User currentUser = [SELECT Id, Email FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
            return currentUser.Email;
        } catch (Exception e) {
            throw new AuraHandledException('Error getting user email: ' + e.getMessage());
        }
    }
}