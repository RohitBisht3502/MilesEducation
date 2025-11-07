// GoogleMeetService.cls
public with sharing class GoogleMeetService {
    private static final String NC = 'GMeet_Scheduler'; // <-- your Named Credential

    public class CreateResult {
        @AuraEnabled public String eventId;
        @AuraEnabled public String meetUrl;
        @AuraEnabled public String htmlLink;
        @AuraEnabled public String rawJson;
    }

    @AuraEnabled(cacheable=false)
    public static CreateResult createMeetEvent(
        String subject,
        String description,
        Datetime startUtc,
        Datetime endUtc,
        String timeZoneId,            // e.g. "Asia/Kolkata"
        List<String> attendeeEmails   // e.g. {'a@gmail.com','b@gmail.com'}
    ) {
        if (String.isBlank(timeZoneId)) timeZoneId = 'Asia/Kolkata';

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
                if (String.isNotBlank(e)) attendees.add(new Map<String,Object>{ 'email' => e.trim() });
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

        // Call Google Calendar API
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:' + NC + '/calendar/v3/calendars/primary/events?conferenceDataVersion=1&sendUpdates=all');
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
                        meetUrl = (String) ep.get('uri'); break;
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
        CreateResult r = createMeetEvent('Meeting: ' + opp.Name, 'Auto-created from Salesforce',
                                         startUtc, endUtc, 'Asia/Kolkata', emails);

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