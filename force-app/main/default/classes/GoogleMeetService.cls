/*
    Author       : ROHIT SINGH BISHT
    Description  : 
*/
public without sharing class GoogleMeetService {
    private static final String NC = 'GMeet_Scheduler';
    private static final String ORG_MEETING_EMAIL = 'meetings@mileseducation.com';

    public class CreateResult {
        @AuraEnabled public String eventId;
        @AuraEnabled public String meetUrl;
        @AuraEnabled public String htmlLink;
        @AuraEnabled public String rawJson;
        @AuraEnabled public Id     salesforceEventId;
        @AuraEnabled public String conferenceId;
    }

    @AuraEnabled(cacheable=false)
    public static CreateResult createMeetEvent(String subject, String description, Datetime startUtc, Datetime endUtc, String timeZoneId, List<String> attendeeEmails) {
        return createMeetEventInternal('primary', subject, description, startUtc, endUtc, timeZoneId, attendeeEmails);
    }

    @AuraEnabled(cacheable=false)
  public static CreateResult createMeetingWithEvent(
    Id recordId,
    String subject,
    String description,
    Datetime startUtc,
    Datetime endUtc,
    String timeZoneId,
    List<String> attendeeEmails,
    String meetingType,
    String typeOfMeeting,
    Integer durationMinutes
)
 {
        if (String.isBlank(timeZoneId)) timeZoneId = 'Asia/Kolkata';
        if (attendeeEmails == null) attendeeEmails = new List<String>();

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

        CreateResult result = createMeetEventInternal(ORG_MEETING_EMAIL, subject, description, startUtc, endUtc, timeZoneId, attendeeEmails );

        Event ev = new Event();
        ev.Subject       = subject;
        ev.Description   = description;
        ev.StartDateTime = startUtc;
        ev.EndDateTime   = endUtc;
        ev.OwnerId       = UserInfo.getUserId();
        if (!String.isBlank(result.meetUrl)) {
            ev.Location = result.meetUrl;
        }

        if (recordId != null) {
            ev.WhatId = recordId;
        }

        Schema.DescribeSObjectResult evDescribe = Event.SObjectType.getDescribe();
        Map<String, Schema.SObjectField> fMap = evDescribe.fields.getMap();

        if (!String.isBlank(meetingType) && fMap.containsKey('Meeting_type__c')) {
            ev.put('Meeting_type__c', meetingType);
        }
        if (!String.isBlank(typeOfMeeting) && fMap.containsKey('Type_of_Meeting__c')) {
    ev.put('Type_of_Meeting__c', typeOfMeeting);
}

        if (durationMinutes != null && fMap.containsKey('Duration__c')) {
            ev.put('Duration__c', durationMinutes);
        }

        if (fMap.containsKey('ConferenceId__c') && !String.isBlank(result.conferenceId)) {
            ev.put('ConferenceId__c', result.conferenceId);
        }

        if (fMap.containsKey('Event_Id__c') && !String.isBlank(result.eventId)) {
            ev.put('Event_Id__c', result.eventId);
        }



        insert ev;
        result.salesforceEventId = ev.Id;

        return result;
    }

    private static CreateResult createMeetEventInternal(String calendarId, String subject, String description, Datetime startUtc, Datetime endUtc, String timeZoneId, List<String> attendeeEmails) {
        if (String.isBlank(timeZoneId)) timeZoneId = 'Asia/Kolkata';
        if (String.isBlank(calendarId)) calendarId = 'primary';

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

        body.put('conferenceData', new Map<String,Object>{
            'createRequest' => new Map<String,Object>{
                'requestId' => String.valueOf(Crypto.getRandomLong()),
                'conferenceSolutionKey' => new Map<String,Object>{ 'type' => 'hangoutsMeet' }
            }
        });

        String encodedCalId = EncodingUtil.urlEncode(calendarId, 'UTF-8');
        HttpRequest req = new HttpRequest();
        req.setEndpoint(
            'callout:' + NC +
            '/calendar/v3/calendars/' + encodedCalId +
            '/events?conferenceDataVersion=1&sendUpdates=all'
        );
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');

        String requestPayload = JSON.serialize(body);
        req.setBody(requestPayload);

        Http http = new Http();
        HttpResponse res;
        try {
            res = http.send(req);
        } catch (Exception e) {
            IntegrationLogUtil.insertLog('GoogleMeetService', requestPayload, null, 'Callout error: ' + e.getMessage(), 'Failed',  null );
            throw new AuraHandledException('Google Meet callout failed: ' + e.getMessage());
        }

        Integer code = res.getStatusCode();
        String responseBody = res.getBody();
        String truncatedResponse = (responseBody != null && responseBody.length() > 3000)
            ? responseBody.substring(0, 3000)
            : responseBody;

        if (code < 200 || code >= 300) {
            IntegrationLogUtil.insertLog( 'GoogleMeetService', requestPayload, truncatedResponse,'Non-2xx response: ' + res.getStatus(),'Failed', code);
            throw new AuraHandledException('Google error: ' + res.getStatus() + ' — ' + responseBody);
        }

        Map<String, Object> m = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
        String meetUrl;
        String conferenceId;
        
        if (m.containsKey('conferenceData')) {
            Map<String,Object> cd = (Map<String,Object>) m.get('conferenceData');
            if (cd != null && cd.containsKey('conferenceId')) {
                conferenceId = (String) cd.get('conferenceId');
            }

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
        if (String.isBlank(meetUrl) && m.containsKey('hangoutLink')) {
            meetUrl = (String) m.get('hangoutLink');
        }

        IntegrationLogUtil.insertLog('GoogleMeetService', requestPayload, truncatedResponse, 'Success', 'Success', code );

        CreateResult out = new CreateResult();
        out.eventId  = (String) m.get('id');
        out.htmlLink = (String) m.get('htmlLink');
        out.meetUrl  = meetUrl;
        out.rawJson  = responseBody;
        out.conferenceId = conferenceId;
        return out;
    }

    @AuraEnabled
    public static CreateResult createMeetForOpportunity( Id opportunityId, Datetime startUtc, Datetime endUtc, String attendeesCsv ) {
        Opportunity opp = [SELECT Id, Name FROM Opportunity WHERE Id = :opportunityId LIMIT 1];
        List<String> emails = new List<String>();
        if (!String.isBlank(attendeesCsv)) {
            for (String s : attendeesCsv.split('[,;\\s]+')) {
                if (String.isNotBlank(s)) emails.add(s.trim());
            }
        }
        CreateResult r = createMeetEvent( 'Meeting: ' + opp.Name, 'Auto-created from Salesforce', startUtc, endUtc, 'Asia/Kolkata', emails);

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

   @AuraEnabled(cacheable=true)
public static List<Map<String, String>> getEventPicklistValues(
    String fieldApiName
) {
    if (String.isBlank(fieldApiName)) {
        throw new AuraHandledException('Field API name is required');
    }

    Map<String, Schema.SObjectField> fieldMap =
        Event.SObjectType.getDescribe().fields.getMap();

    if (!fieldMap.containsKey(fieldApiName)) {
        throw new AuraHandledException(
            'Field does not exist on Event: ' + fieldApiName
        );
    }

    Schema.DescribeFieldResult dfr =
        fieldMap.get(fieldApiName).getDescribe();

    List<Map<String, String>> options = new List<Map<String, String>>();

    for (Schema.PicklistEntry pe : dfr.getPicklistValues()) {
        if (pe.isActive()) {
            options.add(new Map<String, String>{
                'label' => pe.getLabel(),
                'value' => pe.getValue()
            });
        }
    }

    return options;
}

@AuraEnabled
public static Boolean checkExistingMeetings(Datetime startUtc, Datetime endUtc) {
    try {
        // Query for meetings with EXACT same start and end datetime
        List<Event> existingEvents = [
            SELECT Id 
            FROM Event 
            WHERE StartDateTime = :startUtc
            AND EndDateTime = :endUtc
            LIMIT 1
        ];
        
        // Return true if duplicate found
        return !existingEvents.isEmpty();
        
    } catch(Exception e) {
        System.debug('Error: ' + e.getMessage());
        return false;
    }
}

}