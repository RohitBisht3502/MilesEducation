public without sharing class Webservice_WebinarAttendee {
    
    @AuraEnabled(cacheable=false)
    public static String getLiveWebinarAttendees(String webinarId) {
        try {
            HttpRequest req = new HttpRequest();
            req.setMethod('GET');

            String baseUrl = 'https://gvqz37ay7d.execute-api.ap-south-1.amazonaws.com/miles360/webinar_live_attendees';

            String finalUrl = baseUrl + '?webinar_id=' + EncodingUtil.urlEncode(webinarId, 'UTF-8');
            req.setEndpoint(finalUrl);

            req.setHeader('x-api-key', 'gAkgs8n3PQ8QnanrfsueA5KpXNOlpwJw6WtjD2hR');  // Your key
            req.setHeader('Content-Type', 'application/json');

            Http http = new Http();
            HttpResponse res = http.send(req);

            if (res.getStatusCode() != 200) {
                throw new CalloutException(
                    'API Error → ' + res.getStatusCode() + ' → ' + res.getBody()
                );
            }

            return res.getBody();

        } catch (Exception e) {
            throw new AuraHandledException('Error: ' + e.getMessage());
        }
    }
}