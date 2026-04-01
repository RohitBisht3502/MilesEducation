public without sharing class GmeetCalloutSyncService {

    private static final String NC = 'GMeet_Scheduler';
    private static final String DEFAULT_CALENDAR_ID = 'meetings@mileseducation.com';
    private static final Set<String> CANCELLED_STAGES = new Set<String>{
        'Cancelled',
        'Canceled'
    };

    @future(callout=true)
    public static void syncUpdatedEvents(List<Id> eventIds) {
        if (eventIds == null || eventIds.isEmpty()) {
            return;
        }

        List<Event> events = [
            SELECT Id, Subject, Description, StartDateTime, EndDateTime, Location, OwnerId, Event_Id__c, Stage__c
            FROM Event
            WHERE Id IN :eventIds
        ];

        Map<Id, SObject> eventMapById = new Map<Id, SObject>(events);

        for (Id eventId : eventIds) {
            SObject ev = eventMapById.get(eventId);
            if (ev == null) {
                continue;
            }

            String googleEventId = getStringField(ev, 'Event_Id__c');
            if (String.isBlank(googleEventId)) {
                continue;
            }

            String stageValue = getStringField(ev, 'Stage__c');
            try {
                if (isCancelledStage(stageValue)) {
                    cancelGoogleEvent(googleEventId);
                } else {
                    patchGoogleEvent(ev, googleEventId);
                }
            } catch (Exception ex) {
                IntegrationLogUtil.insertLog(
                    'GmeetCalloutSyncService',
                    'EventId=' + eventId + ', GoogleEventId=' + googleEventId,
                    null,
                    'Update sync failed: ' + ex.getMessage(),
                    'Failed',
                    null
                );
            }
        }
    }

    @future(callout=true)
    public static void cancelDeletedEvents(List<String> googleEventIds) {
        if (googleEventIds == null || googleEventIds.isEmpty()) {
            return;
        }

        for (String googleEventId : googleEventIds) {
            if (String.isBlank(googleEventId)) {
                continue;
            }

            try {
                cancelGoogleEvent(googleEventId);
            } catch (Exception ex) {
                IntegrationLogUtil.insertLog(
                    'GmeetCalloutSyncService',
                    'GoogleEventId=' + googleEventId,
                    null,
                    'Delete sync failed: ' + ex.getMessage(),
                    'Failed',
                    null
                );
            }
        }
    }

    private static void patchGoogleEvent(SObject ev, String googleEventId) {
        Map<String, Object> body = new Map<String, Object>();
        body.put('summary', (String)ev.get('Subject'));

        String description = (String)ev.get('Description');
        if (String.isNotBlank(description)) {
            body.put('description', description);
        }

        Datetime startUtc = (Datetime)ev.get('StartDateTime');
        Datetime endUtc = (Datetime)ev.get('EndDateTime');
        if (startUtc != null) {
            body.put('start', new Map<String, Object>{
                'dateTime' => startUtc.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\''),
                'timeZone' => 'Asia/Kolkata'
            });
        }
        if (endUtc != null) {
            body.put('end', new Map<String, Object>{
                'dateTime' => endUtc.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\''),
                'timeZone' => 'Asia/Kolkata'
            });
        }

        String location = (String)ev.get('Location');
        if (String.isNotBlank(location)) {
            body.put('location', location);
        }

        HttpRequest req = new HttpRequest();
        req.setEndpoint(buildEventEndpoint(googleEventId, 'sendUpdates=all'));
        req.setMethod('PATCH');
        req.setHeader('Content-Type', 'application/json');
        String requestPayload = JSON.serialize(body);
        req.setBody(requestPayload);

        sendRequest(req, requestPayload, 'PATCH event ' + googleEventId);
    }

    private static void cancelGoogleEvent(String googleEventId) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(buildEventEndpoint(googleEventId, 'sendUpdates=all'));
        req.setMethod('DELETE');

        sendRequest(req, null, 'DELETE event ' + googleEventId);
    }

    private static void sendRequest(HttpRequest req, String requestPayload, String actionLabel) {
        HttpResponse res;

        try {
            res = new Http().send(req);
        } catch (Exception ex) {
            IntegrationLogUtil.insertLog(
                'GmeetCalloutSyncService',
                requestPayload,
                null,
                actionLabel + ' callout error: ' + ex.getMessage(),
                'Failed',
                null
            );
            throw ex;
        }

        Integer statusCode = res.getStatusCode();
        String responseBody = res.getBody();
        String truncatedResponse =
            (responseBody != null && responseBody.length() > 3000)
                ? responseBody.substring(0, 3000)
                : responseBody;

        if (statusCode < 200 || statusCode >= 300) {
            IntegrationLogUtil.insertLog(
                'GmeetCalloutSyncService',
                requestPayload,
                truncatedResponse,
                actionLabel + ' failed: ' + res.getStatus(),
                'Failed',
                statusCode
            );
            throw new AuraHandledException('Google Calendar sync failed: ' + res.getStatus());
        }

        IntegrationLogUtil.insertLog(
            'GmeetCalloutSyncService',
            requestPayload,
            truncatedResponse,
            actionLabel + ' success',
            'Success',
            statusCode
        );
    }

    private static String buildEventEndpoint(String googleEventId, String queryString) {
        String encodedCalendarId = EncodingUtil.urlEncode(DEFAULT_CALENDAR_ID, 'UTF-8');
        String encodedEventId = EncodingUtil.urlEncode(googleEventId, 'UTF-8');

        String endpoint =
            'callout:' + NC +
            '/calendar/v3/calendars/' + encodedCalendarId +
            '/events/' + encodedEventId;

        if (String.isNotBlank(queryString)) {
            endpoint += '?' + queryString;
        }

        return endpoint;
    }

    private static String getStringField(SObject sobj, String fieldApiName) {
        if (sobj == null || String.isBlank(fieldApiName)) {
            return null;
        }
        Map<String, Schema.SObjectField> fieldMap = sobj.getSObjectType().getDescribe().fields.getMap();
        if (!fieldMap.containsKey(fieldApiName)) {
            return null;
        }
        Object value = sobj.get(fieldApiName);
        return value == null ? null : String.valueOf(value);
    }

    private static Boolean isCancelledStage(String stageValue) {
        return String.isNotBlank(stageValue) && CANCELLED_STAGES.contains(stageValue.trim());
    }
}